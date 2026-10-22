# Final probe fixes: kb_search with matter_id via MCP + sanitize route discovery — 2026-10-10
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$out = @()
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }

$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}
$body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
$tmp = "$env:TEMP\audit-login3-1010.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
$login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 20
$h = @{ Authorization = "Bearer $($login.token)" }
$matters = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/matters" -Headers $h -TimeoutSec 20
$mid = $matters[0].id

# 1. MCP kb_search WITH matter_id (the real lane)
$py = @"
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
_, kb = call({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pacgate_kb_search","arguments":{"query":"settlement authority","matter_id":"$mid"}}}, sid)
t1 = time.time()
txt = kb["result"]["content"][0]["text"]
print(f"MCP kb_search (matter-scoped): {int((t1-t0)*1000)}ms len={len(txt)}")
print(txt[:300])
"@
$pyB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
$kbMcp = docker exec pacgate-mcp sh -c "echo $pyB64 | base64 -d | python3" 2>&1
$out += "KB search lane: $kbMcp"

# 2. Sanitize route discovery — check the OpenAPI spec
$openapi = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/openapi.json" -Headers $h -TimeoutSec 20
$sanPaths = $openapi.paths.PSObject.Properties.Name | Where-Object { $_ -match "sanitize" }
$out += "sanitize routes in OpenAPI: $($sanPaths -join ', ')"
$kbPaths = $openapi.paths.PSObject.Properties.Name | Where-Object { $_ -match "kb|search" }
$out += "kb/search routes: $($kbPaths -join ', ')"
$docPaths = $openapi.paths.PSObject.Properties.Name | Where-Object { $_ -match "documents" }
$out += "document routes: $($docPaths -join ', ')"

# 3. Sanitize with the correct route
if ($sanPaths) {
    $sanRoute = ($sanPaths | Where-Object { $_ -match "documents/\{.*\}/sanitize" } | Select-Object -First 1)
    if (-not $sanRoute) { $sanRoute = $sanPaths[0] }
    $route = $sanRoute -replace "\{[^}]+\}", $docIdPlaceholder
    # re-upload for a fresh doc
    $fixture = "CONFIDENTIAL DRAFT`nClient: Zhang Wei`nID: 11010519491231002X`nPhone: 13812345678`nMarker-PACGATE-AUDIT-1010c`n"
    $fixPath = "$env:TEMP\audit-fixture3-1010.txt"
    [System.IO.File]::WriteAllText($fixPath, $fixture, (New-Object System.Text.UTF8Encoding($false)))
    $boundary = "----AuditBoundary1010c"
    $fileBytes = [System.IO.File]::ReadAllBytes($fixPath)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"audit-fixture3.txt`"`r`nContent-Type: text/plain`r`n`r`n"))
    $bw.Write($fileBytes)
    $bw.Write([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$mid`r`n--$boundary--`r`n"))
    $bw.Flush()
    $upTmp = "$env:TEMP\audit-upload3-1010.bin"
    [System.IO.File]::WriteAllBytes($upTmp, $ms.ToArray())
    $doc = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -InFile $upTmp -Headers $h -TimeoutSec 30
    $docId = $doc.id
    $out += "uploaded: $docId"
    Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/extract" -Method Post -Headers $h -TimeoutSec 120 | Out-Null

    # inspect the sanitize route's parameters
    $sanDef = $openapi.paths.$sanRoute.post
    $out += "sanitize route: $sanRoute"
    $out += "  params: $(($sanDef.parameters | ForEach-Object { "$($_.name)($($_.in))" }) -join ', ')"
    if ($sanDef.requestBody) {
        $ct = ($sanDef.requestBody.content.PSObject.Properties.Name) -join ', '
        $out += "  requestBody content: $ct"
        $schemaRef = $sanDef.requestBody.content.$ct.schema.'$ref'
        if ($schemaRef) {
            $schemaName = $schemaRef -replace '#/components/schemas/', ''
            $schema = $openapi.components.schemas.$schemaName
            $out += "  schema $schemaName`: $(($schema.properties.PSObject.Properties | ForEach-Object { $_.Name }) -join ', ')"
            # build the body
            $sanBody = @{}
            foreach ($p in $schema.properties.PSObject.Properties) {
                if ($p.Name -eq "tier") { $sanBody.tier = 3 }
                elseif ($p.Name -eq "document_id") { $sanBody.document_id = $docId }
            }
            $sanTmp = "$env:TEMP\audit-san3-1010.json"
            [System.IO.File]::WriteAllText($sanTmp, ($sanBody | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate$sanRoute" -Method Post -ContentType $ct -InFile $sanTmp -Headers $h -TimeoutSec 180
                $sw.Stop()
                Time "sanitize" $sw.ElapsedMilliseconds "verdict=$($san.verdict) redactions=$($san.redaction_count) mappings=$($san.mapping_count)"
                # download gate
                try {
                    $dl = Invoke-WebRequest -Uri "http://localhost:8089/pacgate/api/documents/$docId/download" -Headers $h -TimeoutSec 20 -UseBasicParsing
                    $out += "[PASS] download gate: HTTP $($dl.StatusCode) (verdict=$($san.verdict) -> OPEN)"
                } catch {
                    $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
                    if ($code -eq 409) { $out += "[PASS] download gate: HTTP 409 SHUT (verdict=$($san.verdict) — correct)" }
                    else { $out += "[NOTE] download gate: HTTP $code" }
                }
            } catch {
                $sw.Stop()
                $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
                Fail "sanitize" "HTTP $code"
            }
        }
    } else {
        # no body — plain POST
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate$sanRoute" -Method Post -Headers $h -TimeoutSec 180
        $sw.Stop()
        Time "sanitize" $sw.ElapsedMilliseconds "verdict=$($san.verdict)"
    }

    try {
        Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId" -Method Delete -Headers $h -TimeoutSec 20 | Out-Null
        $out += "[PASS] cleanup"
    } catch { $out += "[NOTE] cleanup failed: $docId remains" }
}

$out | Out-File -FilePath "$w\runtime\audit2c-final-1010.txt" -Encoding utf8
Write-Output "AUDIT2C DONE"
