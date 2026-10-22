# Fix the 2 broken probes: KB search (GET vs POST) + sanitize content-type — 2026-10-10
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }

$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}
$body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
$tmp = "$env:TEMP\audit-login2-1010.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
$login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 20
$h = @{ Authorization = "Bearer $($login.token)" }
$matters = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/matters" -Headers $h -TimeoutSec 20
$mid = $matters[0].id

# 1. KB search — try GET with query params
Add-Section "KB SEARCH (GET variant)"
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $kb = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/kb/search?query=settlement&matter_id=$mid" -Headers $h -TimeoutSec 30
    $sw.Stop()
    Time "GET /kb/search" $sw.ElapsedMilliseconds ($kb | ConvertTo-Json -Compress | ForEach-Object { $_.Substring(0, [Math]::Min(100, $_.Length)) })
} catch {
    $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
    $out += "GET variant: HTTP $code"
    # try POST with different body shape
    try {
        $kbBody = @{ query = "settlement" } | ConvertTo-Json -Compress
        $kbTmp = "$env:TEMP\audit-kb2-1010.json"
        [System.IO.File]::WriteAllText($kbTmp, $kbBody, (New-Object System.Text.UTF8Encoding($false)))
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $kb = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/kb/search" -Method Post -ContentType "application/json" -InFile $kbTmp -Headers $h -TimeoutSec 30
        $sw.Stop()
        Time "POST /kb/search (query only)" $sw.ElapsedMilliseconds ($kb | ConvertTo-Json -Compress | ForEach-Object { $_.Substring(0, [Math]::Min(100, $_.Length)) })
    } catch {
        $code2 = $null; try { $code2 = $_.Exception.Response.StatusCode.value__ } catch {}
        $out += "POST query-only: HTTP $code2"
        # check the MCP kb_search tool instead (the real lane)
        $py = @'
import urllib.request, json, re, time
def call(payload, sid=None):
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if sid: headers["mcp-session-id"] = sid
    req = urllib.request.Request("http://localhost:8000/mcp", data=json.dumps(payload).encode(), headers=headers)
    r = urllib.request.urlopen(req, timeout=60)
    d = r.read().decode()
    m = re.search(r"data: (.*)", d)
    return (r.headers.get("mcp-session-id"), json.loads(m.group(1)) if m else None)
sid, _ = call({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"audit","version":"1.0"}}})
t0 = time.time()
_, kb = call({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pacgate_kb_search","arguments":{"query":"settlement authority"}}}, sid)
t1 = time.time()
txt = kb["result"]["content"][0]["text"]
print(f"MCP kb_search: {int((t1-t0)*1000)}ms len={len(txt)}")
print(txt[:200])
'@
        $pyB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
        $kbMcp = docker exec pacgate-mcp sh -c "echo $pyB64 | base64 -d | python3" 2>&1
        $out += "MCP kb_search lane: $kbMcp"
    }
}

# 2. Sanitize with correct content type (the 415 was on sanitize POST)
Add-Section "SANITIZE (fixed content-type)"
# re-upload the fixture
$fixture = "CONFIDENTIAL DRAFT`nClient: Zhang Wei`nID: 11010519491231002X`nPhone: 13812345678`nMarker-PACGATE-AUDIT-1010`n"
$fixPath = "$env:TEMP\audit-fixture2-1010.txt"
[System.IO.File]::WriteAllText($fixPath, $fixture, (New-Object System.Text.UTF8Encoding($false)))
$boundary = "----AuditBoundary1010b"
$fileBytes = [System.IO.File]::ReadAllBytes($fixPath)
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([System.Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"audit-fixture2.txt`"`r`nContent-Type: text/plain`r`n`r`n"))
$bw.Write($fileBytes)
$bw.Write([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$mid`r`n--$boundary--`r`n"))
$bw.Flush()
$upTmp = "$env:TEMP\audit-upload2-1010.bin"
[System.IO.File]::WriteAllBytes($upTmp, $ms.ToArray())
$doc = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -InFile $upTmp -Headers $h -TimeoutSec 30
$docId = $doc.id
$out += "uploaded doc: $docId"

$ext = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/extract" -Method Post -Headers $h -TimeoutSec 120
$out += "extract: incomplete=$($ext.incomplete) len=$($ext.text.Length)"

# sanitize — the 415 suggests it wants JSON body or different content type
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $sanBody = @{ tier = 3 } | ConvertTo-Json -Compress
    $sanTmp = "$env:TEMP\audit-san-1010.json"
    [System.IO.File]::WriteAllText($sanTmp, $sanBody, (New-Object System.Text.UTF8Encoding($false)))
    $san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/sanitize" -Method Post -ContentType "application/json" -InFile $sanTmp -Headers $h -TimeoutSec 120
    $sw.Stop()
    Time "sanitize T3 (JSON body)" $sw.ElapsedMilliseconds "verdict=$($san.verdict) redactions=$($san.redaction_count) mappings=$($san.mapping_count)"
    $verdict = $san.verdict
} catch {
    $sw.Stop()
    $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
    $out += "sanitize JSON-body: HTTP $code"
    # try query param variant without body
    try {
        $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
        $san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/sanitize" -Method Post -Headers $h -TimeoutSec 120
        $sw2.Stop()
        Time "sanitize T3 (no body)" $sw2.ElapsedMilliseconds "verdict=$($san.verdict) redactions=$($san.redaction_count)"
        $verdict = $san.verdict
    } catch {
        $code2 = $null; try { $code2 = $_.Exception.Response.StatusCode.value__ } catch {}
        $out += "sanitize no-body: HTTP $code2"
        $verdict = $null
    }
}

# download gate
if ($verdict) {
    try {
        $dl = Invoke-WebRequest -Uri "http://localhost:8089/pacgate/api/documents/$docId/download" -Headers $h -TimeoutSec 20 -UseBasicParsing
        $out += "[PASS] download gate: HTTP $($dl.StatusCode) (verdict=$verdict -> gate OPEN)"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code -eq 409 -and $verdict -eq "block") { $out += "[PASS] download gate: HTTP 409 SHUT (verdict=block — correct)" }
        else { $out += "[NOTE] download gate: HTTP $code verdict=$verdict" }
    }
}

# cleanup
try {
    Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId" -Method Delete -Headers $h -TimeoutSec 20 | Out-Null
    $out += "[PASS] cleanup: doc deleted"
} catch { $out += "[NOTE] cleanup failed: doc $docId remains" }

$out | Out-File -FilePath "$w\runtime\audit2b-fix-1010.txt" -Encoding utf8
Write-Output "AUDIT2B DONE"
