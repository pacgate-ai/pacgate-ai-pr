# Smoke part 2: pacgate-api full lane + MCP + workflows + document pipeline — 2026-10-10
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

# Login + token
Add-Section "AUTH"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
$tmp = "$env:TEMP\audit-login-1010.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
try {
    $login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 20
    $sw.Stop()
    Time "login" $sw.ElapsedMilliseconds "token issued"
    $h = @{ Authorization = "Bearer $($login.token)" }
} catch { Fail "login" $_.Exception.Message; $out | Out-File "$w\runtime\audit2-smoke-api-1010.txt" -Encoding utf8; exit 1 }

# Core surfaces with latency
Add-Section "CORE SURFACES (latency)"
function TimedGet($name, $url, $headers) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
        $sw.Stop()
        $detail = ""
        if ($r -is [System.Array]) { $detail = "$($r.Count) items" }
        elseif ($r.workflows) { $detail = "$($r.workflows.Count) workflows" }
        elseif ($r.matters) { $detail = "$($r.matters.Count) matters" }
        Time $name $sw.ElapsedMilliseconds $detail
        return $r
    } catch { $sw.Stop(); Fail $name "$($_.Exception.Message)"; return $null }
}
$matters = TimedGet "GET /matters" "http://localhost:8089/pacgate/api/matters" $h
$wfs = TimedGet "GET /workflows" "http://localhost:8089/pacgate/api/workflows" $h
$conn = TimedGet "GET /search/health" "http://localhost:8089/pacgate/api/search/health" $h
if ($conn) {
    $avail = ($conn | Where-Object { $_.available }).Count
    Pass "connectors available" "$avail / $($conn.Count)"
    $out += (($conn | ForEach-Object { "  $($_.name): available=$($_.available)" }) -join "`n")
}

# Matter memory lane
Add-Section "MATTER MEMORY LANE"
if ($matters -and $matters.Count -gt 0) {
    $mid = $matters[0].id
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $mem = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/matters/$mid/memory" -Headers $h -TimeoutSec 20
        $sw.Stop()
        Time "GET matter memory" $sw.ElapsedMilliseconds "version=$($mem.version) facts=$($mem.facts.Count)"
    } catch { Fail "matter memory" $_.Exception.Message }
}

# KB search (pgvector lane)
Add-Section "KB SEARCH (pgvector)"
try {
    $kbBody = @{ query = "settlement authority"; matter_id = $matters[0].id } | ConvertTo-Json -Compress
    $kbTmp = "$env:TEMP\audit-kb-1010.json"
    [System.IO.File]::WriteAllText($kbTmp, $kbBody, (New-Object System.Text.UTF8Encoding($false)))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $kbRaw = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/kb/search?q=settlement%20authority&matter_id=$($matters[0].id)&limit=5" -Headers $h -TimeoutSec 30
    $kb = @{ chunks = @($kbRaw) }
    $sw.Stop()
    Time "POST /kb/search" $sw.ElapsedMilliseconds "chunks=$($kb.chunks.Count)"
} catch { Fail "kb search" $_.Exception.Message }

# MCP lane (container-internal python)
Add-Section "MCP LANE"
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
t0 = time.time()
sid, init = call({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"audit","version":"1.0"}}})
t1 = time.time()
_, tools = call({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}, sid)
t2 = time.time()
_, lm = call({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pacgate_list_matters","arguments":{}}}, sid)
t3 = time.time()
print(f"initialize: {int((t1-t0)*1000)}ms | tools/list: {int((t2-t1)*1000)}ms ({len(tools['result']['tools'])} tools) | list_matters: {int((t3-t2)*1000)}ms (len={len(lm['result']['content'][0]['text'])})")
'@
$pyB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
$mcpResult = docker exec pacgate-mcp sh -c "echo $pyB64 | base64 -d | python3" 2>&1
$out += "MCP: $mcpResult"

# Document pipeline (upload -> extract -> sanitize -> download gate)
Add-Section "DOCUMENT PIPELINE"
try {
    # build a small text fixture with PII
    $fixture = "CONFIDENTIAL DRAFT`nClient: Zhang Wei`nID: 11010519491231002X`nPhone: 13812345678`nMarker-PACGATE-AUDIT-1010`n"
    $fixPath = "$env:TEMP\audit-fixture-1010.txt"
    [System.IO.File]::WriteAllText($fixPath, $fixture, (New-Object System.Text.UTF8Encoding($false)))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $boundary = "----AuditBoundary1010"
    $fileBytes = [System.IO.File]::ReadAllBytes($fixPath)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"audit-fixture.txt`"`r`nContent-Type: text/plain`r`n`r`n"))
    $bw.Write($fileBytes)
    $bw.Write([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$($matters[0].id)`r`n--$boundary--`r`n"))
    $bw.Flush()
    $uploadBytes = $ms.ToArray()
    $upTmp = "$env:TEMP\audit-upload-1010.bin"
    [System.IO.File]::WriteAllBytes($upTmp, $uploadBytes)
    $doc = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -InFile $upTmp -Headers $h -TimeoutSec 30
    $sw.Stop()
    Time "upload" $sw.ElapsedMilliseconds "doc id=$($doc.id)"
    $docId = $doc.id

    # extract
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ext = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/extract" -Method Post -Headers $h -TimeoutSec 120
    $sw.Stop()
    Time "extract" $sw.ElapsedMilliseconds "incomplete=$($ext.incomplete) len=$($ext.text.Length)"

    # sanitize T3
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sanBody = '{"data_level":"T3"}'
    $sanTmp = "$env:TEMP\audit-san-1010.json"
    [System.IO.File]::WriteAllText($sanTmp, $sanBody, (New-Object System.Text.UTF8Encoding($false)))
    $san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/sanitize" -Method Post -ContentType "application/json" -InFile $sanTmp -Headers $h -TimeoutSec 300
    $sw.Stop()
    Time "sanitize T3" $sw.ElapsedMilliseconds "verdict=$($san.verdict) redactions=$($san.redaction_count) mappings=$($san.mapping_count)"

    # download gate
    try {
        $dl = Invoke-WebRequest -Uri "http://localhost:8089/pacgate/api/documents/$docId/download" -Headers $h -TimeoutSec 20 -UseBasicParsing
        $out += "[PASS] download gate: HTTP $($dl.StatusCode) (verdict=$($san.verdict) -> gate $(if ($san.verdict -eq 'pass') {'OPEN'} else {'SHUT'}))"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code -eq 409 -and $san.verdict -eq "block") { $out += "[PASS] download gate: HTTP 409 SHUT (verdict=block — correct compliance behavior)" }
        else { $out += "[FAIL] download gate: HTTP $code verdict=$($san.verdict)" }
    }

    # cleanup: delete the test doc
    try {
        Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId" -Method Delete -Headers $h -TimeoutSec 20 | Out-Null
        $out += "[PASS] cleanup: test doc deleted"
    } catch { $out += "[NOTE] cleanup: delete failed ($($_.Exception.Message)) — doc $docId remains" }
} catch { Fail "document pipeline" $_.Exception.Message }

$out | Out-File -FilePath "$w\runtime\audit2-smoke-api-1010.txt" -Encoding utf8
Write-Output "AUDIT2 DONE"
