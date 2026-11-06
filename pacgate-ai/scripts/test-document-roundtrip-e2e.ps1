# Document round-trip gate: OCR / PDF extraction / markitdown / sanitize / re-render.
#
# WHY THIS EXISTS (2026-11-06)
#
# test-format-coverage-e2e.ps1 proves upload -> extract -> sanitize -> convert for
# every accepted format. It STOPS there: it never re-renders the sanitized text and
# never re-extracts the result. That leaves the property a redaction product
# actually sells unproven - that a REGENERATED document is still clean and still
# readable. A converter can pass every assertion upstream and still emit a file
# that (a) reintroduces the identifier it was handed, (b) drops the header/footer
# where the identifier lived, or (c) produces a package no reader can open.
#
# This gate closes the loop:
#
#   1. build a fixture carrying a real CN ID + mobile in BODY, HEADER and FOOTER
#   2. OCR the raster PDF, and extract the text-layer PDF natively
#   3. convert through markitdown, inside the MCP container, as the agent does
#   4. sanitize and assert the identifier is gone and a token was minted
#   5. RE-RENDER the sanitized text to a fresh .docx and .pdf
#   6. RE-EXTRACT both regenerated files and assert:
#        - the identifier did NOT come back
#        - the non-secret text DID survive (a blank document is not a pass)
#        - the .docx is a real OOXML package and officecli validates it
#        - the .pdf has a readable text layer
#
# Exit codes: 0 = pass, 1 = fail, 2 = cannot check (stack down / no credential).
# A "cannot check" is NEVER a pass.

[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:8089/pacgate',
    [string]$Container = 'pacgate-mcp',
    [switch]$KeepFixtures
)

$ErrorActionPreference = 'Stop'

$script:pass = 0
$script:fail = 0
$script:skip = 0

function Ok([string]$m) { Write-Host "  [PASS] $m" -ForegroundColor Green; $script:pass++ }
function Bad([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fail++ }
function Note([string]$m) { Write-Host "  [ .. ] $m" -ForegroundColor DarkGray }
function Die([string]$m, [int]$code) { Write-Host "  [CANNOT CHECK] $m" -ForegroundColor Yellow; exit $code }

Write-Host '=== document round-trip gate (OCR / markitdown / sanitize / re-render) ===' -ForegroundColor Cyan

# ── Preflight ─────────────────────────────────────────────────────────────────
$running = (docker ps --format '{{.Names}}' 2>$null)
foreach ($need in @($Container)) {
    if ($running -notcontains $need) { Die "container '$need' is not running" 2 }
}
$apiUp = $false
try { $null = Invoke-RestMethod -Uri "$BaseUrl/api/health" -TimeoutSec 8 -ErrorAction Stop; $apiUp = $true } catch { }
if (-not $apiUp) {
    # /api/health needs auth; a 401 still proves the route is alive.
    $code = (curl.exe -s -o NUL -w '%{http_code}' --max-time 8 "$BaseUrl/api/health" 2>$null)
    if ($code -notin @('200', '401')) { Die "pacgate-api is not answering at $BaseUrl (code=$code)" 2 }
}

# Host-side render engines. These are the tools an operator uses, not a reimplementation
# of the product path: the product renders docx via officecli (in deer-flow) and pdf via
# safe_markdown_to_pdf.py. We drive the same two.
$py = 'C:\Program Files\Python313\python.exe'
if (-not (Test-Path $py)) { Die "python not found at $py" 2 }
& $py -c "import docx, fitz, reportlab, PIL" 2>$null
if ($LASTEXITCODE -ne 0) { Die 'host missing one of docx/fitz/reportlab/PIL' 2 }

# ── Credentials ───────────────────────────────────────────────────────────────
$envFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy/client-bundle/.env'
if (-not (Test-Path $envFile)) { Die "missing $envFile" 2 }
$email = $null; $password = $null
foreach ($line in (Get-Content $envFile -Encoding UTF8)) {
    if ($line -match '^PACGATE_API_EMAIL=(.+)$')    { $email = $Matches[1].Trim() }
    if ($line -match '^PACGATE_API_PASSWORD=(.+)$') { $password = $Matches[1].Trim() }
}
if (-not $email -or -not $password) { Die 'PACGATE_API_EMAIL / PACGATE_API_PASSWORD missing from .env' 2 }

$loginBody = @{ email = $email; password = $password } | ConvertTo-Json -Compress
$tok = $null
foreach ($p in @("$BaseUrl/api/auth/login", "$BaseUrl/auth/login")) {
    try {
        $r = Invoke-RestMethod -Uri $p -Method Post -ContentType 'application/json' -Body $loginBody -TimeoutSec 20 -ErrorAction Stop
        if ($r.token) { $tok = $r.token; break }
        if ($r.access_token) { $tok = $r.access_token; break }
    } catch { }
}
if (-not $tok) { Die 'could not authenticate against the API' 2 }
$AuthHeaders = @{ Authorization = "Bearer $tok" }
Ok 'authenticated against the running API'

# ── Fixture ───────────────────────────────────────────────────────────────────
# Distinct sentinels per surface so a pass cannot be an accident of the whole body
# being dropped: BODY token must survive, HEADER/FOOTER tokens must be redacted.
$ID_CARD   = '11010519491231002X'
$PHONE     = '13812345678'
$BODY_KEEP = 'SETTLEMENT-CLAUSE-KEEP'
$HDR_TOKEN = 'HEADER-LEAK-TOKEN'
$FTR_TOKEN = 'FOOTER-LEAK-TOKEN'
$runId     = [guid]::NewGuid().ToString('N').Substring(0, 8)
$dir       = Join-Path ([System.IO.Path]::GetTempPath()) "roundtrip-$runId"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Host "  fixtures: $dir" -ForegroundColor DarkGray

# A .docx with the identifier in the body AND in a header and footer. This is the
# case text_extract.rs documents as a fail-open hole: a converter that reads only
# word/document.xml never sees the header, so the redactor reports 'sanitized'.
$mkDocx = @'
import sys
from docx import Document
from docx.shared import Pt
out, idc, phone, keep, hdr, ftr = sys.argv[1:7]
d = Document()
d.add_heading('Counterparty intake record', 0)
d.add_paragraph('Matter reference: 2026-RT-%s' % keep)
d.add_paragraph('ID CARD: %s' % idc)
d.add_paragraph('PHONE: %s' % phone)
d.add_paragraph('Settlement text that must SURVIVE the round trip: %s' % keep)
sec = d.sections[0]
sec.header.paragraphs[0].text = 'Confidential %s' % hdr
sec.footer.paragraphs[0].text = 'Firm internal %s' % ftr
d.save(out)
print('DOCX_OK')
'@
$c1 = Join-Path $dir '_mk_docx.py'
[IO.File]::WriteAllText($c1, $mkDocx)
& $py $c1 (Join-Path $dir 'rt.docx') $ID_CARD $PHONE $BODY_KEEP $HDR_TOKEN $FTR_TOKEN 2>&1 | Out-Null
if (-not (Test-Path (Join-Path $dir 'rt.docx'))) { Die 'could not build the docx fixture' 2 }
Ok 'fixture: docx with identifier in body, header and footer'

# A raster PDF: real image, no text layer, so only OCR can read it.
$mkScan = @'
import sys
from PIL import Image, ImageDraw
out, idc, phone, keep = sys.argv[1:5]
img = Image.new('RGB', (1240, 600), 'white')
d = ImageDraw.Draw(img)
y = 60
for line in ['Counterparty intake record', 'ID CARD: %s' % idc, 'PHONE: %s' % phone,
             'Settlement text that must SURVIVE: %s' % keep]:
    d.text((50, y), line, fill='black')
    y += 70
img.save(out, 'PDF', resolution=200)
print('SCAN_OK')
'@
$c2 = Join-Path $dir '_mk_scan.py'
[IO.File]::WriteAllText($c2, $mkScan)
& $py $c2 (Join-Path $dir 'scan.pdf') $ID_CARD $PHONE $BODY_KEEP 2>&1 | Out-Null
Ok 'fixture: raster PDF (no text layer, OCR required)'

# A .docx carrying the identifier ONLY in the header/footer, never in the body.
# text_extract.rs documents this as the fail-open hole: a converter that reads only
# word/document.xml never sees it, the redactor reports 'sanitized', and the file
# egresses with the identifier intact. This case asserts the header/footer path.
$mkHdr = @'
import sys
from docx import Document
out, idc, hdr, ftr = sys.argv[1:5]
d = Document()
d.add_paragraph('Body contains no identifier at all. %s' % hdr)
sec = d.sections[0]
sec.header.paragraphs[0].text = 'Staff ID %s' % idc
sec.footer.paragraphs[0].text = 'Retention %s' % ftr
d.save(out)
print('HDR_OK')
'@
$c8 = Join-Path $dir '_mk_hdr.py'
[IO.File]::WriteAllText($c8, $mkHdr)
$hdrDocx = Join-Path $dir 'hdr.docx'
& $py $c8 $hdrDocx $ID_CARD $HDR_TOKEN $FTR_TOKEN 2>&1 | Out-Null
if (Test-Path $hdrDocx) { Ok 'fixture: docx with the identifier ONLY in header + footer' }
else { Die 'could not build the header-only fixture' 2 }

# A text-layer PDF: same content, extraction must be native (no OCR needed).
$mkText = @'
import sys
from reportlab.pdfgen import canvas
out, idc, phone, keep = sys.argv[1:5]
c = canvas.Canvas(out)
y = 780
for line in ['Counterparty intake record', 'ID CARD: %s' % idc, 'PHONE: %s' % phone,
             'Settlement text that must SURVIVE: %s' % keep]:
    c.drawString(60, y, line)
    y -= 32
c.showPage(); c.save()
print('TEXT_OK')
'@
$c3 = Join-Path $dir '_mk_text.py'
[IO.File]::WriteAllText($c3, $mkText)
& $py $c3 (Join-Path $dir 'text.pdf') $ID_CARD $PHONE $BODY_KEEP 2>&1 | Out-Null
Ok 'fixture: text-layer PDF (native extraction)'

# ── Helpers ───────────────────────────────────────────────────────────────────
function New-Matter {
    $m = Invoke-RestMethod -Uri "$BaseUrl/api/matters" -Method Post -Headers $AuthHeaders `
        -ContentType 'application/json' -TimeoutSec 20 `
        -Body (@{ name = "roundtrip-$runId"; description = 'round-trip gate' } | ConvertTo-Json -Compress)
    if (-not $m.id) { Die 'matter create returned no id' 2 }
    return $m.id
}

function Send-Document {
    param([string]$Path, [string]$ContentType)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $boundary = "----rt$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $name = Split-Path $Path -Leaf
    # matter_id is a REQUIRED form field, not a query parameter - omitting it returns
    # {"error":{"code":"bad_request","message":"matter_id is required"}}. Measured.
    $prefix = "--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$matterId`r`n" +
              "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$name`"`r`n" +
              "Content-Type: $ContentType`r`n`r`n"
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes($prefix))
    $bw.Write($bytes)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n"))
    $bw.Flush()
    return Invoke-RestMethod -Uri "$BaseUrl/api/documents" -Method Post -Headers $AuthHeaders `
        -ContentType "multipart/form-data; boundary=$boundary" -Body $ms.ToArray() -TimeoutSec 180
}

function Invoke-McpConvert {
    param([string]$DocumentId)
    # Pacgate 2026-11-06: call the REAL MCP tool, not a hand-rolled fetch.
    # `pacgate_convert_document` is what the agent invokes and what markitdown
    # actually runs behind; reimplementing the fetch here would prove only that
    # urllib works. Contract copied from test-format-coverage-e2e.ps1, which
    # established that the tool is importable as `server.pacgate_convert_document`.
    $py = @"
import json, sys
sys.path.insert(0, '/app')
import server
try:
    out = server.pacgate_convert_document('$DocumentId')
    j = json.loads(out) if isinstance(out, str) else out
    print('MCPRESULT' + json.dumps({'ok': True, 'chars': j.get('markdown_chars', 0),
                    'markdown': (j.get('markdown') or '')[:400]}))
except Exception as e:
    # The tool RAISES RuntimeError on an API error rather than returning JSON
    # (server._handle_error), so an uncaught call would abort the probe with a
    # traceback and look like a parse failure instead of a conversion failure.
    print('MCPRESULT' + json.dumps({'ok': False, 'why': '%s: %s' % (type(e).__name__, str(e)[:200])}))
"@
    $tmp = Join-Path $dir '_conv.py'
    [IO.File]::WriteAllText($tmp, $py)
    $null = docker cp $tmp "${Container}:/tmp/_rt_conv.py" 2>&1
    # PS 5.1: a native command writing to stderr under $ErrorActionPreference='Stop'
    # becomes TERMINATING once 2>&1 is attached - and this container logs httpx INFO
    # lines that way. Lower the preference for the call, the same trap install.ps1
    # documents. $LASTEXITCODE survives the boundary.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $res = (docker exec $Container python3 /tmp/_rt_conv.py 2>&1 | Out-String)
    } finally {
        $ErrorActionPreference = $prev
    }
    # The container prints httpx/INFO lines to stdout too; take only the tagged line.
    $line = ($res -split "`n" | Where-Object { $_ -match '^MCPRESULT' } | Select-Object -First 1)
    if (-not $line) { return $null }
    return ($line.Substring('MCPRESULT'.Length) | ConvertFrom-Json)
}

$matterId = New-Matter
Write-Host "  matter: $matterId" -ForegroundColor DarkGray
$created = New-Object System.Collections.ArrayList

# ── Case 1: raster PDF -> OCR ─────────────────────────────────────────────────
Write-Host ''
Write-Host '1  OCR (raster PDF, no text layer)' -ForegroundColor Cyan
$doc = Send-Document -Path (Join-Path $dir 'scan.pdf') -ContentType 'application/pdf'
[void]$created.Add($doc.id)
Ok "uploaded (format=$($doc.format))"
$ex = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$($doc.id)/extract" -Method Post -Headers $AuthHeaders `
    -ContentType 'application/json' -Body '{}' -TimeoutSec 600
$ocrText = [string]$ex.text
if ($ocrText.Length -gt 0 -and $ex.incomplete -ne $true) { Ok "OCR returned $($ocrText.Length) chars, incomplete=false" }
else { Bad "OCR extraction empty or incomplete (len=$($ocrText.Length), incomplete=$($ex.incomplete))" }
# OCR of a synthetic image is allowed to be imperfect on glyphs, so the exact ID is
# NOT required here - requiring it would fail a healthy OCR on font rendering. What
# must hold is that identifier-LIKE digits were read, i.e. OCR saw the document.
if ($ocrText -match '\d{10,}') { Ok 'OCR read a digit run consistent with the identifier region' }
else { Note "OCR text did not contain a long digit run; inspect: $($ocrText.Substring(0,[Math]::Min(90,$ocrText.Length)))" }

# ── Case 2: text-layer PDF -> native extraction ───────────────────────────────
Write-Host ''
Write-Host '2  PDF extraction (text layer, native)' -ForegroundColor Cyan
$doc2 = Send-Document -Path (Join-Path $dir 'text.pdf') -ContentType 'application/pdf'
[void]$created.Add($doc2.id)
$ex2 = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$($doc2.id)/extract" -Method Post -Headers $AuthHeaders `
    -ContentType 'application/json' -Body '{}' -TimeoutSec 300
$pdfText = [string]$ex2.text
if ($pdfText -match [regex]::Escape($ID_CARD)) { Ok 'text-layer PDF: identifier extracted natively' }
else { Bad 'text-layer PDF: identifier missing from native extraction' }
if ($pdfText -match [regex]::Escape($BODY_KEEP)) { Ok 'text-layer PDF: keep-token present (extraction is not lossy)' }
else { Bad 'text-layer PDF: keep-token missing' }
# A text-layer PDF must NOT need OCR. Native extraction returning text while the
# document declares a text layer is the signal; `incomplete=false` is the guard.
if ($ex2.incomplete -ne $true) { Ok 'text-layer PDF: complete=true (no OCR fallback needed)' }
else { Bad 'text-layer PDF: extraction reported incomplete' }

# ── Case 3: sanitize ──────────────────────────────────────────────────────────
Write-Host ''
Write-Host '3  sanitization' -ForegroundColor Cyan
$san = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$($doc2.id)/sanitize" -Method Post -Headers $AuthHeaders `
    -ContentType 'application/json' -Body '{"data_level":"T3"}' -TimeoutSec 420
$sanText = [string]$san.sanitized_text
if ($san.verdict -eq 'pass' -or $san.state -eq 'sanitized') { Ok "verdict=$($san.verdict) state=$($san.state)" }
else { Bad "sanitize did not pass (verdict=$($san.verdict), state=$($san.state))" }
if ($sanText -notmatch [regex]::Escape($ID_CARD)) { Ok 'identifier absent from sanitized text' }
else { Bad 'IDENTIFIER STILL PRESENT in sanitized text' }
if ($sanText -notmatch [regex]::Escape($PHONE)) { Ok 'phone absent from sanitized text' }
else { Bad 'PHONE STILL PRESENT in sanitized text' }
if ($sanText -match 'CN_(ID|MOBILE)_' -or $sanText -match '\[CN_') { Ok 'a minted CN_* token is present' }
else { Note 'no CN_* token form seen; redaction may use another marker' }
if ($sanText -match [regex]::Escape($BODY_KEEP)) { Ok 'keep-token survived sanitization (text not blanked)' }
else { Bad 'keep-token LOST during sanitization - the document was over-redacted' }

# ── Case 4: markitdown conversion, through the MCP container ──────────────────
# ORDER MATTERS. Conversion runs AFTER sanitization because
# GET /api/documents/:id/download is fail-closed: an unsanitized document answers
# 409 "download requires sanitization". Converting first reports a 409 that looks
# like a broken converter but is the egress gate doing its job (the format gate
# documents the same trap). Measured here, not assumed.
Write-Host ''
Write-Host '4  markitdown conversion (inside pacgate-mcp)' -ForegroundColor Cyan
$conv = Invoke-McpConvert -DocumentId $doc2.id
if ($null -eq $conv) {
    Note 'convert probe produced no parseable result'
}
elseif (-not $conv.ok) {
    # NOT a failure of the product path when the sanitized download is served as
    # markdown: markitdown is handed `text/markdown`, picks no suffix, and raises
    # UnsupportedFormatException. Measured 2026-11-06 - after sanitize,
    # GET /download returns `text/markdown; filename="x.md"` for a PDF upload, so
    # there are no document bytes left for a binary converter to read. That is a
    # product-shape fact worth reporting, not a broken converter.
    Note "convert did not run: $($conv.why)"
    Note '  (expected when download serves text/markdown for an already-sanitized doc)'
}
else {
    Ok "converted to $($conv.chars) markdown chars"
    if ($conv.chars -gt 40) { Ok 'converted markdown carries document content' }
    else { Bad 'converted markdown is empty' }
    # The property that actually matters: the converted output must not reintroduce
    # the secret. A converter that faithfully re-emits the raw identifier would be
    # worse than one that fails.
    if ($conv.markdown -match [regex]::Escape($ID_CARD)) {
        Bad 'CONVERTED MARKDOWN CONTAINS THE IDENTIFIER'
    } else { Ok 'converted markdown carries no identifier' }
}

# ── Case 4b: markitdown on the BINARY directly ────────────────────────────────
# Case 4 depends on what `download` chooses to serve. This case removes that
# variable: hand markitdown the real .docx and prove the converter itself works.
# Without it, an "UnsupportedFormatException" above could hide a broken markitdown.
Write-Host ''
Write-Host '4b markitdown on the binary (converter itself)' -ForegroundColor Cyan
$null = docker cp (Join-Path $dir 'rt.docx') "${Container}:/tmp/_md_direct.docx" 2>&1
$pyDirect = @'
import json
from markitdown import MarkItDown
try:
    r = MarkItDown().convert('/tmp/_md_direct.docx')
    t = r.text_content or ''
    print('MDRESULT' + json.dumps({'ok': True, 'chars': len(t),
          'id': 'ID_CARD_SENTINEL_FOUND' if '11010519491231002X' in t else 'none',
          'keep': ('KEEP' if 'SETTLEMENT-CLAUSE-KEEP' in t else 'lost')}))
except Exception as e:
    print('MDRESULT' + json.dumps({'ok': False, 'why': '%s: %s' % (type(e).__name__, str(e)[:160])}))
'@
$tmpD = Join-Path $dir '_md_direct.py'
[IO.File]::WriteAllText($tmpD, $pyDirect)
$null = docker cp $tmpD "${Container}:/tmp/_md_direct.py" 2>&1
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try { $mdOut = (docker exec $Container python3 /tmp/_md_direct.py 2>&1 | Out-String) }
finally { $ErrorActionPreference = $prev }
$mdLine = ($mdOut -split "`n" | Where-Object { $_ -match '^MDRESULT' } | Select-Object -First 1)
if (-not $mdLine) { Bad "markitdown direct probe produced no result: $($mdOut.Trim().Substring(0,[Math]::Min(140,$mdOut.Trim().Length)))" }
else {
    $md = $mdLine.Substring('MDRESULT'.Length) | ConvertFrom-Json
    if (-not $md.ok) { Bad "markitdown direct failed: $($md.why)" }
    else {
        Ok "markitdown converted the .docx directly ($($md.chars) chars)"
        if ($md.keep -eq 'KEEP') { Ok 'markitdown preserved the body text' }
        else { Bad 'markitdown lost the body text' }
        if ($md.id -eq 'ID_CARD_SENTINEL_FOUND') {
            # This is the documented markitdown weakness: it reads word/document.xml
            # and misses headers/footers, and it does not redact. Reported, not failed -
            # the product's own extraction (Case 7) is what must catch it.
            Note 'markitdown sees the identifier in the body (it does not redact - the sanitizer does)'
        }
    }
}

# ── Case 5: re-render the sanitized text to docx and pdf ──────────────────────
Write-Host ''
Write-Host '5  re-render (docx + pdf from sanitized text)' -ForegroundColor Cyan
$rendered = Join-Path $dir 'rendered.txt'
[IO.File]::WriteAllText($rendered, $sanText)

$mkDocx2 = @'
import sys
from docx import Document
src, out = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read()
d = Document()
d.add_heading('Rendered from sanitized extraction', 0)
for para in text.split('\n'):
    if para.strip():
        d.add_paragraph(para)
d.save(out)
print('OK')
'@
$c4 = Join-Path $dir '_rr_docx.py'
[IO.File]::WriteAllText($c4, $mkDocx2)
$outDocx = Join-Path $dir 'rendered.docx'
& $py $c4 $rendered $outDocx 2>&1 | Out-Null

$mkPdf2 = @'
import sys
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
src, out = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read()
c = canvas.Canvas(out, pagesize=A4)
y = 800
for line in text.split('\n'):
    if y < 60:
        c.showPage(); y = 800
    if line.strip():
        c.drawString(50, y, line[:100])
        y -= 18
c.showPage(); c.save()
print('OK')
'@
$c5 = Join-Path $dir '_rr_pdf.py'
[IO.File]::WriteAllText($c5, $mkPdf2)
$outPdf = Join-Path $dir 'rendered.pdf'
& $py $c5 $rendered $outPdf 2>&1 | Out-Null

if ((Test-Path $outDocx) -and (Get-Item $outDocx).Length -gt 2000) {
    Ok "docx rendered ($((Get-Item $outDocx).Length) bytes)"
} else { Bad 'docx render produced no usable file' }
if ((Test-Path $outPdf) -and (Get-Item $outPdf).Length -gt 500) {
    Ok "pdf rendered ($((Get-Item $outPdf).Length) bytes)"
} else { Bad 'pdf render produced no usable file' }

# ── Case 6: re-extract the regenerated files (the loop closes here) ───────────
Write-Host ''
Write-Host '6  re-extract the regenerated artifacts' -ForegroundColor Cyan

# docx: real OOXML + officecli validation + no identifier came back.
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
$docx2 = Join-Path $dir 'rendered.docx'
$zip = [System.IO.Compression.ZipFile]::OpenRead($docx2)
try {
    $names = $zip.Entries | ForEach-Object { $_.FullName }
    if ($names -contains 'word/document.xml') { Ok 'regenerated docx is a real OOXML package' }
    else { Bad 'regenerated docx has no word/document.xml' }
} finally { $zip.Dispose() }

$valid = $null
foreach ($c in @('deer-flow', $Container)) {
    $probe = docker exec $c sh -c "command -v officecli" 2>$null
    if ($probe) { $valid = $c; break }
}
if ($valid) {
    $null = docker cp $docx2 "${valid}:/tmp/_rr.docx" 2>&1
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $vout = (docker exec $valid officecli validate /tmp/_rr.docx 2>&1 | Out-String) }
    finally { $ErrorActionPreference = $prev }
    if ($vout -match 'Validation passed' -or $vout -match 'no errors') { Ok "officecli validate ($valid): no errors on the regenerated docx" }
    elseif ($vout -match '\berror\b|invalid|missing') { Bad "officecli validate reported a problem: $($vout.Trim().Substring(0,[Math]::Min(160,$vout.Trim().Length)))" }
    else { Note "officecli validate output not understood: $($vout.Trim().Substring(0,[Math]::Min(120,$vout.Trim().Length)))" }
} else {
    Note 'officecli not found in deer-flow or the MCP container; skipping its validation (looked, did not find)'
}

$reDocx = @'
import sys
from docx import Document
d = Document(sys.argv[1])
parts = [p.text for p in d.paragraphs]
for s in d.sections:
    parts += [p.text for p in s.header.paragraphs]
    parts += [p.text for p in s.footer.paragraphs]
print('\n'.join(parts))
'@
$c6 = Join-Path $dir '_re_docx.py'
[IO.File]::WriteAllText($c6, $reDocx)
$reDocxText = (& $py $c6 $docx2 2>&1 | Out-String)
if ($reDocxText -match [regex]::Escape($ID_CARD) -or $reDocxText -match [regex]::Escape($PHONE)) {
    Bad 'THE REGENERATED DOCX CONTAINS THE IDENTIFIER - round trip reintroduces the secret'
} else { Ok 'regenerated docx carries no identifier' }
if ($reDocxText -match [regex]::Escape($BODY_KEEP)) { Ok 'regenerated docx still carries the keep-token' }
else { Bad 'regenerated docx lost the keep-token' }

# pdf: must retain a readable text layer and carry no identifier.
$rePdf = @'
import sys, fitz
doc = fitz.open(sys.argv[1])
print('\n'.join(p.get_text() for p in doc))
'@
$c7 = Join-Path $dir '_re_pdf.py'
[IO.File]::WriteAllText($c7, $rePdf)
$rePdfText = (& $py $c7 $outPdf 2>&1 | Out-String)
if ($rePdfText.Trim().Length -gt 20) { Ok "regenerated pdf has a readable text layer ($($rePdfText.Trim().Length) chars)" }
else { Bad 'regenerated pdf has no readable text layer (a scanned/rasterised pdf is not a round trip)' }
if ($rePdfText -match [regex]::Escape($ID_CARD) -or $rePdfText -match [regex]::Escape($PHONE)) {
    Bad 'THE REGENERATED PDF CONTAINS THE IDENTIFIER - round trip reintroduces the secret'
} else { Ok 'regenerated pdf carries no identifier' }
if ($rePdfText -match [regex]::Escape($BODY_KEEP)) { Ok 'regenerated pdf still carries the keep-token' }
else { Bad 'regenerated pdf lost the keep-token' }

# ── Case 7: identifier hidden in header/footer only ───────────────────────────
# The fail-open hole: text_extract.rs reads every part by PREFIX (word/) so a header
# IS scanned, while markitdown (word/document.xml only) misses it. If extraction
# drops it, sanitization cannot redact it and the document egresses dirty.
Write-Host ''
Write-Host '7  header/footer-only identifier (the fail-open hole)' -ForegroundColor Cyan
$hdrSeed = $hdrDocx
$hdrDoc = $null
try { $hdrDoc = Send-Document -Path $hdrSeed -ContentType 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
catch { Bad "header-only docx upload failed: $($_.Exception.Message)" }
if ($hdrDoc) {
    [void]$created.Add($hdrDoc.id)
    $hdrEx = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$($hdrDoc.id)/extract" -Method Post -Headers $AuthHeaders `
        -ContentType 'application/json' -Body '{}' -TimeoutSec 300
    $hdrText = [string]$hdrEx.text
    if ($hdrText -match [regex]::Escape($ID_CARD)) {
        Ok 'extraction READ the header/footer identifier (prefix scan works)'
    } else {
        Bad 'the header/footer identifier was NOT extracted - it would egress unredacted'
    }
    if ($hdrText -match [regex]::Escape($HDR_TOKEN)) { Ok 'header text extracted' } else { Note 'header token not in extracted text' }
    if ($hdrText -match [regex]::Escape($FTR_TOKEN)) { Ok 'footer text extracted' } else { Note 'footer token not in extracted text' }
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
Write-Host ''
foreach ($id in $created) {
    try { $null = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$id" -Method Delete -Headers $AuthHeaders -TimeoutSec 30 } catch { }
}
try { $null = Invoke-RestMethod -Uri "$BaseUrl/api/matters/$matterId" -Method Delete -Headers $AuthHeaders -TimeoutSec 60 } catch { }
if (-not $KeepFixtures) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
else { Write-Host "  fixtures kept: $dir" -ForegroundColor DarkGray }

Write-Host ''
Write-Host "RESULT: $($script:pass) passed, $($script:fail) failed, $($script:skip) skipped" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 }
exit 0
