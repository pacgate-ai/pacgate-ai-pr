# Targeted re-checks for the 3 real questions from the E2E run — 2026-10-09
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }

$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}

# 1. /version WITH auth token
Add-Section "1. /version WITH AUTH"
try {
    $body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
    $tmp = "$env:TEMP\login2-1009b.json"
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 15
    $h = @{ Authorization = "Bearer $($login.token)" }
    $v = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/version" -Headers $h -TimeoutSec 15
    $out += "AUTH /version: version=$($v.version) rev=$($v.revision.Substring(0,[Math]::Min(8,$v.revision.Length)))"
} catch { $out += "AUTH /version FAIL: $($_.Exception.Message)" }

# 2. MCP endpoint — find the right nginx route
Add-Section "2. MCP ROUTE DISCOVERY"
$ng = Get-Content "$cb\nginx\default.conf" -Raw -Encoding UTF8
$mcpLines = ($ng -split "`n" | Select-String -Pattern "mcp" | ForEach-Object { $_.Line.Trim() })
$out += "nginx mcp lines:"
$out += ($mcpLines -join "`n")
# try the routes found
foreach ($path in @("/pacgate-mcp/mcp", "/mcp", "/pacgate/mcp")) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8089$path" -Method Post -ContentType "application/json" -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"e2e","version":"1.0"}}}' -Headers @{ Accept = "application/json, text/event-stream" } -TimeoutSec 15 -UseBasicParsing
        $out += "POST $path -> HTTP $($r.StatusCode), session-id=$([bool]$r.Headers['mcp-session-id'])"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        $out += "POST $path -> HTTP $code"
    }
}
# container-internal direct
try {
    docker exec deer-flow sh -c "wget -q -O- --header='Content-Type: application/json' --header='Accept: application/json, text/event-stream' --post-data='{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"x\",\"version\":\"1\"}}}' http://pacgate-mcp:8000/mcp 2>&1 | head -c 300"
    $out += "container-internal pacgate-mcp:8000/mcp reachable from deer-flow"
} catch { $out += "container-internal FAIL: $($_.Exception.Message)" }

# 3. Connectors detail
Add-Section "3. CONNECTORS DETAIL"
try {
    $body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
    $tmp = "$env:TEMP\login3-1009b.json"
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 15
    $h = @{ Authorization = "Bearer $($login.token)" }
    $conn = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/search/health" -Headers $h -TimeoutSec 15
    foreach ($c in $conn.connectors) {
        $out += "$($c.name): available=$($c.available) reason=$($c.reason)"
    }
} catch { $out += "connectors FAIL: $($_.Exception.Message)" }

# 4. Workflows categories shape
Add-Section "4. WORKFLOWS SHAPE"
try {
    $body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
    $tmp = "$env:TEMP\login4-1009b.json"
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 15
    $h = @{ Authorization = "Bearer $($login.token)" }
    $wfs = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/workflows" -Headers $h -TimeoutSec 15
    $out += "workflows count: $($wfs.workflows.Count)"
    $out += "categories type: $($wfs.categories.GetType().Name)"
    if ($wfs.categories -is [System.Array]) { $out += "categories count: $($wfs.categories.Count)" }
    else { $out += "categories keys: $(($wfs.categories.PSObject.Properties | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', ')" }
} catch { $out += "workflows FAIL: $($_.Exception.Message)" }

# 5. Extensions config count (fixed quoting via base64)
Add-Section "5. EXTENSIONS CONFIG COUNT"
$py = "import json`nd=json.load(open('/app/deer-flow-extensions-config.json'))`nprint(len(d['mcpServers']))"
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
$cnt = docker exec deer-flow sh -c "echo $b64 | base64 -d | python3" 2>&1
$out += "MCP servers in container: $cnt"

$out | Out-File -FilePath "$w\runtime\e2e-recheck-1009b.txt" -Encoding utf8
Write-Output "DONE"
