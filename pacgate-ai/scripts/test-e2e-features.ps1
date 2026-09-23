# E2E feature smoke test for the PacGate 0.1.17 stack.
#
# Exercises EVERY user-facing feature against the LIVE stack through nginx
# (localhost:8089), the same path a client browser uses:
#   auth -> matters -> upload -> kb search -> external search -> sanitize ->
#   extract -> workflow list/detail/categories/execute -> api chat ->
#   deer-flow gateway -> MCP -> openviking memory -> qm -> OCR -> frontend
#
# RESULTS ONLY. No secrets printed. Each lane reports PASS / FAIL / SKIP
# distinctly; SKIP is never counted as a pass.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <this> [-Model <tag>]

param(
    [string]$Model = 'gemma4:12b-it-q8_0',
    [switch]$SkipLlm
)

$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai'
$cb   = Join-Path $repo 'deploy\client-bundle'
$API  = 'http://localhost:8089/pacgate'
$NGX  = 'http://localhost:8089'

$script:pass = 0; $script:fail = 0; $script:skip = 0; $script:known = 0
$script:failures = @()

function Ok($m)   { $script:pass++; Write-Host ("  [PASS] " + $m) -ForegroundColor Green }
function No($m)   { $script:fail++; $script:failures += $m; Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }
function Sk($m)   { $script:skip++; Write-Host ("  [SKIP] " + $m) -ForegroundColor Yellow }
function Hd($m)   { Write-Host ''; Write-Host ("=== " + $m + " ===") -ForegroundColor Cyan }

function ReadEnv($key) {
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $cb '.env'))) {
        if ($line -match ("^" + [regex]::Escape($key) + "=(.*)$")) { return $Matches[1].Trim() }
    }
    return $null
}

# JSON body via temp file (PS 5.1 curl quote-mangling trap), and the RESPONSE
# goes to a file too, read back as UTF-8. Reading curl's stdout directly decodes
# it with the GBK console codepage, which corrupts the Chinese connector names
# and makes ConvertFrom-Json throw "invalid JSON" on perfectly valid JSON.
$script:jsonTmp  = Join-Path $env:TEMP 'pg-e2e-body.json'
$script:outTmp   = Join-Path $env:TEMP 'pg-e2e-out.json'
function CurlJson($method, $url, $headers, $obj, $timeoutSec = 120) {
    $args = @('-sS', '-o', $script:outTmp, '-w', '%{http_code}', '--max-time', $timeoutSec, '-X', $method)
    foreach ($h in $headers) { $args += @('-H', $h) }
    if ($null -ne $obj) {
        $json = if ($obj -is [string]) { $obj } else { $obj | ConvertTo-Json -Compress -Depth 8 }
        [System.IO.File]::WriteAllText($script:jsonTmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        $args += @('--data-binary', "@$script:jsonTmp")
    }
    $args += $url
    $codeTxt = (& curl.exe @args 2>&1 | Out-String).Trim()
    $code = 0
    if ($codeTxt -match '(\d{3})') { $code = [int]$Matches[1] }
    $body = ''
    if (Test-Path $script:outTmp) { $body = [System.IO.File]::ReadAllText($script:outTmp, [System.Text.Encoding]::UTF8) }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

# PS 5.1 wraps a top-level JSON ARRAY as ONE object, so `@($json | ConvertFrom-Json)`
# reports Count 1 and `$arr.id` yields nothing. These two helpers unwrap correctly.
function JsonList($body) {
    try { $x = $body | ConvertFrom-Json } catch { return @() }
    if ($null -eq $x) { return @() }
    if ($x -is [System.Array]) { return $x }
    return @($x)
}
function JsonFirst($body) {
    $l = JsonList $body
    if ($l.Count -gt 0) { return $l[0] }
    return $null
}

Write-Host '############ PacGate 0.1.17 E2E FEATURE SMOKE ############' -ForegroundColor Magenta
Write-Host ("  api    = $API")
Write-Host ("  model  = $Model   (skip llm = $SkipLlm)")

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L1  AUTH  (pacgate-api)'
$email = ReadEnv 'PACGATE_API_EMAIL'; $password = ReadEnv 'PACGATE_API_PASSWORD'
if (-not $email -or -not $password) { No 'credentials missing from .env'; }
else {
    $r = CurlJson 'POST' "$API/api/auth/login" @('Content-Type: application/json') @{ email=$email; password=$password } 40
    if ($r.Code -eq 200 -and $r.Body -match '"token"') { Ok "login -> 200" ; $tok = ($r.Body | ConvertFrom-Json).token }
    else { No ("login -> HTTP " + $r.Code) }
}
if (-not $tok) { Write-Host '  cannot continue without a token'; exit 2 }
$H = @("Authorization: Bearer $tok")

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L2  MATTERS'
$matterId = $null
$r = CurlJson 'POST' "$API/api/matters" ($H + @('Content-Type: application/json')) @{ name = ('E2E Smoke ' + (Get-Date -Format 'HHmmss')) } 40
if ($r.Code -eq 200 -or $r.Code -eq 201) {
    try { $matterId = ($r.Body | ConvertFrom-Json).id } catch {}
    if ($matterId) { Ok ("create matter -> " + $r.Code + "  id=" + $matterId.Substring(0,8) + '...') } else { No 'create matter returned no id' }
} else { No ("create matter -> HTTP " + $r.Code + ' ' + $r.Body) }
$r = CurlJson 'GET' "$API/api/matters" $H $null 30
if ($r.Code -eq 200) { Ok ('list matters -> 200 (' + (JsonList $r.Body).Count + ')') } else { No ("list matters -> HTTP " + $r.Code) }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L3  DOCUMENTS  (upload)'
# NOTE: upload a REAL PDF. The OCR lane is PDF-only (pdf2image/PaddleOCR), so a
# .md/.docx upload extracts as `incomplete` and then BLOCKS sanitization forever.
# A PDF exercises the supported path; the non-PDF gap is reported at L6b.
$docId = $null
if ($matterId) {
    $srcPdf = Join-Path $repo 'deploy\USER-MANUAL.pdf'
    if (-not (Test-Path $srcPdf)) { $srcPdf = Join-Path $repo 'deploy\AIPC-DEPLOYMENT-HANDBOOK-ZH.pdf' }
    if ($env:E2E_PDF -and (Test-Path $env:E2E_PDF)) { $srcPdf = $env:E2E_PDF }
    if (-not (Test-Path $srcPdf)) { Sk 'no sample PDF available for upload' }
    else {
        Write-Host ('       source = ' + $srcPdf)
        $out = & curl.exe -sS -o $script:outTmp -w '%{http_code}' -X POST -H "Authorization: Bearer $tok" -F "matter_id=$matterId" -F "file=@$srcPdf" "$API/api/documents" 2>&1
        $code = [int](($out | Out-String).Trim())
        $body = if (Test-Path $script:outTmp) { [System.IO.File]::ReadAllText($script:outTmp, [System.Text.Encoding]::UTF8) } else { '' }
        if ($code -eq 200 -or $code -eq 201) {
            try { $docId = ($body | ConvertFrom-Json).id } catch {}
            if ($docId) { Ok ("upload PDF -> $code  id=" + $docId.Substring(0,8) + '...') } else { No 'upload returned no id' }
        } else { No ("upload PDF -> HTTP $code") }
    }
} else { Sk 'upload (no matter)' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L4  INTERNAL RAG  (kb search)'
if ($matterId) {
    $r = CurlJson 'GET' "$API/api/kb/search?q=Acme&matter_id=$matterId" $H $null 30
    if ($r.Code -eq 200) { Ok ('kb search -> 200') } elseif ($r.Code -eq 404) { Sk ('kb search -> 404 (route absent)') } else { No ("kb search -> HTTP " + $r.Code) }
} else { Sk 'kb search (no matter)' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L5  EXTERNAL LEGAL CONNECTORS  (registry / health)'
$r = CurlJson 'GET' "$API/api/search/registry" $H $null 30
if ($r.Code -eq 200) {
    $n = (JsonList $r.Body).Count
    Ok ("search registry -> 200 ($n connectors)")
} else { No ("search registry -> HTTP " + $r.Code) }
$r = CurlJson 'GET' "$API/api/search/health" $H $null 40
if ($r.Code -eq 200) { Ok 'search health -> 200' } else { No ("search health -> HTTP " + $r.Code) }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L6  SANITIZATION  (the red-line feature)'
if ($docId) {
    # SanitizeRequest = { data_level: "T1"|"T2"|"T3"|"T4" } - NOT { level }.
    $r = CurlJson 'POST' "$API/api/documents/$docId/sanitize" ($H + @('Content-Type: application/json')) @{ data_level = 'T3' } 300
    if ($r.Code -eq 200 -or $r.Code -eq 201) {
        $j = $r.Body | ConvertFrom-Json
        Ok ("sanitize T3 -> $($r.Code)  verdict=$($j.verdict) redactions=$($j.redaction_count) mappings=$($j.mapping_count)")
    }
    else { No ("sanitize T3 -> HTTP " + $r.Code + ' ' + $r.Body.Substring(0,[Math]::Min(200,$r.Body.Length))) }
    $r = CurlJson 'GET' "$API/api/documents/$docId/sanitize-status" $H $null 30
    if ($r.Code -eq 200) { Ok 'sanitize-status -> 200' } else { No ("sanitize-status -> HTTP " + $r.Code) }
} else { Sk 'sanitization (no document)' }

# Non-PDF input: a KNOWN LIMITATION, reported but not failed.
# ocr-service rasterises with pdf2image and handles ONLY pdf/images; every other
# suffix is handed to PaddleOCR as if it were an image, so the page fails, the
# service answers 200 with incomplete=true, and pacgate-api's fail-closed check
# rejects it - the document can then NEVER be sanitized. The data model and the
# upload path both accept docx/txt/markdown, so this is a real gap, but closing
# it needs an ocr-service dependency + image rebuild, not a config change.
Hd 'L6b  NON-PDF INPUT  (known limitation - reported, not failed)'
if ($matterId) {
    $tmpNon = Join-Path $env:TEMP 'pg-e2e-nonpdf.md'
    [System.IO.File]::WriteAllText($tmpNon, "# Engagement Letter`n`nClient: Acme Holdings Ltd. Contact zhang.wei@example.com.`n", (New-Object System.Text.UTF8Encoding($false)))
    $o = & curl.exe -sS -o $script:outTmp -w '%{http_code}' -X POST -H "Authorization: Bearer $tok" -F "matter_id=$matterId" -F "file=@$tmpNon;filename=nonpdf-probe.md" "$API/api/documents" 2>&1
    $c1 = [int](($o | Out-String).Trim())
    $bid = ''
    try { $bid = ([System.IO.File]::ReadAllText($script:outTmp, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).id } catch {}
    if ($bid) {
        $e2 = CurlJson 'POST' "$API/api/documents/$bid/extract" ($H + @('Content-Type: application/json')) @{} 300
        $inc = 'n/a'
        try { $inc = ($e2.Body | ConvertFrom-Json).incomplete } catch {}
        $s2 = CurlJson 'POST' "$API/api/documents/$bid/sanitize" ($H + @('Content-Type: application/json')) @{ data_level = 'T3' } 300
        Write-Host ("       upload=$c1  extract=$($e2.Code) incomplete=$inc  sanitize=$($s2.Code)")
        if ($s2.Code -ne 200) {
            Write-Host '       KNOWN LIMITATION: non-PDF cannot be sanitized (ocr-service is PDF-only).' -ForegroundColor Yellow
            Write-Host '       Needs: ocr-service dependency (e.g. python-docx/markitdown) + image rebuild.' -ForegroundColor Yellow
            $script:known++
        } else { Ok 'non-PDF extraction + sanitize -> 200 (limitation may be resolved)' }
    } else { Sk ('non-PDF probe upload failed (http ' + $c1 + ')') }
} else { Sk 'non-PDF probe (no matter)' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L7  OCR / EXTRACTION  (ocr-service)'
$ocrUp = (& docker ps --filter 'name=ocr-service' --format '{{.Names}}' 2>&1 | Out-String)
if ($ocrUp -match 'ocr-service') {
    if ($docId) {
        $r = CurlJson 'POST' "$API/api/documents/$docId/extract" ($H + @('Content-Type: application/json')) @{} 300
        if ($r.Code -eq 200 -or $r.Code -eq 201) { Ok ("extract -> " + $r.Code) }
        elseif ($r.Code -eq 404) { Sk ('extract -> 404 (route absent)') }
        else { No ("extract -> HTTP " + $r.Code) }
    } else { Sk 'extract (no document)' }
} else { Sk 'ocr-service not running' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L8  WORKFLOW LIBRARY  (list / detail / categories / execute)'
$r = CurlJson 'GET' "$API/api/workflows" $H $null 40
$wfs = @()
if ($r.Code -eq 200) { $wfs = JsonList $r.Body; Ok ("workflows list -> 200 ($($wfs.Count))") } else { No ("workflows list -> HTTP " + $r.Code) }
$r = CurlJson 'GET' "$API/api/workflows/categories" $H $null 40
if ($r.Code -eq 200) { Ok ('workflow categories -> 200 (' + (JsonList $r.Body).Count + ')') } else { No ("workflow categories -> HTTP " + $r.Code) }
$wfId = $null
if ($wfs.Count -gt 0) {
    $wfId = $wfs[0].id
    $r2 = CurlJson 'GET' "$API/api/workflows/$wfId" $H $null 40
    if ($r2.Code -eq 200) { Ok 'workflow detail -> 200' } else { No ("workflow detail -> HTTP " + $r2.Code) }
}
if ($wfId -and $matterId -and -not $SkipLlm) {
    $r = CurlJson 'POST' "$API/api/workflows/$wfId/execute" ($H + @('Content-Type: application/json')) @{ matter_id = $matterId } 300
    if ($r.Code -eq 200) { Ok 'workflow execute -> 200 (tier resolved, LLM reachable)' }
    elseif ($r.Body -match 'nemotron3:33b|qwen3\.6:27b|qwen3\.5:9b') {
        No 'workflow execute -> 500 KNOWN DEFECT: pacgate-api asks for a model that is not installed'
        Write-Host '       pacgate-api builds its tiers from ModelConfig::default_local_with_base_url (hardcoded'   -ForegroundColor DarkYellow
        Write-Host '       nemotron3:33b / qwen3.6:27b / qwen3.5:9b). None exist in Ollama, so EVERY workflow run'     -ForegroundColor DarkYellow
        Write-Host '       fails 404. Only the tenant config_json.model_overrides can change it; live tenant = {}.'      -ForegroundColor DarkYellow
    }
    else { No ("workflow execute -> HTTP " + $r.Code + ' ' + $r.Body.Substring(0,[Math]::Min(300,$r.Body.Length))) }
} elseif ($SkipLlm) { Sk 'workflow execute (llm skipped)' } else { Sk 'workflow execute (missing ids)' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L9  API CHAT  (pacgate-agent + LLM router)'
if ($matterId -and -not $SkipLlm) {
    $r = CurlJson 'POST' "$API/api/chat" ($H + @('Content-Type: application/json')) @{ matter_id = $matterId; message = 'Reply with exactly: API-CHAT-OK' } 300
    if ($r.Code -eq 200) { Ok 'api chat -> 200 (agent loop + local LLM)' }
    elseif ($r.Body -match 'nemotron3:33b|qwen3\.6:27b|qwen3\.5:9b') {
        No 'api chat -> 500 KNOWN DEFECT: same uninstalled tier model as workflow execute'
    }
    else { No ("api chat -> HTTP " + $r.Code + ' ' + $r.Body.Substring(0,[Math]::Min(300,$r.Body.Length))) }
} elseif ($SkipLlm) { Sk 'api chat (llm skipped)' } else { Sk 'api chat (no matter)' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L10  DD AGENT CONFIGS'
$r = CurlJson 'GET' "$API/api/dd-configs" $H $null 30
if ($r.Code -eq 200) { Ok ('dd-configs -> 200 (' + (JsonList $r.Body).Count + ')') } else { No ("dd-configs -> HTTP " + $r.Code) }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L11  DEER-FLOW GATEWAY  (auth surface + registration gate)'
$r = CurlJson 'POST' "$NGX/api/v1/auth/register" @('Content-Type: application/json') @{ email='probe-e2e@invalid.test'; password='x' } 30
if ($r.Code -eq 403) { Ok 'gateway self-registration CLOSED -> 403 (correct)' }
elseif ($r.Code -eq 200 -or $r.Code -eq 201) { No ("gateway self-registration OPEN -> $($r.Code)  <-- GATE LEAK") }
else { No ("gateway register -> HTTP " + $r.Code) }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L12  MCP LANE  (pacgate server tools)'
$mcpRunning = (& docker ps --filter 'name=pacgate-mcp' --format '{{.Names}}' 2>&1 | Out-String)
if ($mcpRunning -match 'pacgate-mcp') {
    $probe = Join-Path $repo 'scripts\probe-mcp-workflow-count.py'
    if (Test-Path $probe) {
        & docker cp $probe 'pacgate-mcp:/tmp/pwc.py' 2>&1 | Out-Null
        $pout = (& docker exec pacgate-mcp python3 /tmp/pwc.py 2>&1 | Out-String)
        $pcode = $LASTEXITCODE
        $pout -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host ('       ' + $_) }
        if ($pcode -eq 0) { Ok 'MCP pacgate_list_workflows returned the library' }
        elseif ($pcode -eq 1) { No 'MCP lane serves the built-ins only' }
        else { Sk ("MCP probe inconclusive (exit $pcode)") }
    } else { Sk 'probe script missing' }
} else { Sk 'pacgate-mcp not running' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L13  OPENVIKING MEMORY  (MCP recall lane uses the root key)'
$ovKey = ReadEnv 'OPENVIKING_ROOT_API_KEY'
if ($ovKey) {
    $payload = @{ jsonrpc='2.0'; id=1; method='tools/call'; params=@{ name='health'; arguments=@{} } } | ConvertTo-Json -Compress -Depth 8
    [System.IO.File]::WriteAllText($script:jsonTmp, $payload, (New-Object System.Text.UTF8Encoding($false)))
    $out = & curl.exe -sS -X POST -w "`nHTTP_CODE=%{http_code}" --max-time 30 -H "X-API-Key: $ovKey" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' --data-binary "@$script:jsonTmp" 'http://localhost:1933/mcp' 2>&1
    $t = ($out | Out-String); $c = if ($t -match 'HTTP_CODE=(\d+)') { [int]$Matches[1] } else { 0 }
    if ($c -eq 200) { Ok 'openviking MCP tools/call health -> 200 (memory lane live)' }
    else { No ("openviking MCP -> HTTP " + $c) }
} else { Sk 'openviking root key missing' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L14  QM CO-WORK SPACE'
$qmCore = (& docker ps --filter 'name=qm-pacgate-core' --format '{{.Status}}' 2>&1 | Out-String).Trim()
if ($qmCore) {
    Ok ("qm core running ($qmCore)")
    $pi = (& docker inspect qm-pacgate-core 2>$null | ConvertFrom-Json).Config.Env | Where-Object { $_ -match '^PI_MODEL=' }
    if ($pi) { Write-Host ("       qm PI_MODEL = " + $pi) }
} else { Sk 'qm not running' }

# ─────────────────────────────────────────────────────────────────────────────
Hd 'L15  FRONTEND  (deer-flow Next.js)'
foreach ($u in 'http://localhost:8090', "$NGX/version") {
    try { $w = Invoke-WebRequest $u -TimeoutSec 20 -UseBasicParsing; Ok ("$u -> " + $w.StatusCode) }
    catch { No ("$u -> failed") }
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '############################ E2E SUMMARY ############################' -ForegroundColor Magenta
Write-Host ("  PASS = " + $script:pass + "   FAIL = " + $script:fail + "   SKIP = " + $script:skip + "   KNOWN = " + $script:known) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:known -gt 0) {
    Write-Host "  KNOWN (reported, not counted as failures): $($script:known)" -ForegroundColor Yellow
    Write-Host '    - ocr-service is PDF-only: docx/txt/markdown extract as incomplete and can never be sanitized.' -ForegroundColor Yellow
}
if ($script:fail -gt 0) {
    Write-Host '  FAILURES:' -ForegroundColor Red
    $script:failures | ForEach-Object { Write-Host ('    - ' + $_) -ForegroundColor Red }
    Write-Host ''
    Write-Host ("RESULT: $($script:fail) FEATURE(S) FAILED ($($script:pass) passed, $($script:skip) skipped, $($script:known) known).") -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host ("RESULT: all exercised features PASS ($($script:pass) passed, $($script:skip) skipped, $($script:known) known limitations).") -ForegroundColor Green
exit 0
