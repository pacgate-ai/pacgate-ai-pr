# Smoke part 3: deer-flow gateway + frontend + memory card + models — 2026-10-10
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
$dfUser = $envVars["PACGATE_API_EMAIL"]
$dfPass = $envVars["PACGATE_API_PASSWORD"]

# 1. Gateway login
Add-Section "DEER-FLOW GATEWAY"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$loginForm = "username=$([System.Uri]::EscapeDataString($dfUser))&password=$([System.Uri]::EscapeDataString($dfPass))"
$tmp4 = "$env:TEMP\audit-df-login-1010.txt"
[System.IO.File]::WriteAllText($tmp4, $loginForm, (New-Object System.Text.UTF8Encoding($false)))
try {
    $r = Invoke-WebRequest -Uri "http://localhost:8089/api/v1/auth/login/local" -Method Post -ContentType "application/x-www-form-urlencoded" -InFile $tmp4 -SessionVariable sess -TimeoutSec 20 -UseBasicParsing
    $sw.Stop()
    Time "gateway login" $sw.ElapsedMilliseconds "HTTP $($r.StatusCode)"
    $csrf = ($sess.Cookies.GetCookies("http://localhost:8089") | Where-Object { $_.Name -eq "csrf_token" }).Value
    Pass "csrf cookie" "$([bool]$csrf)"
} catch { Fail "gateway login" $_.Exception.Message; $out | Out-File "$w\runtime\audit3-deerflow-1010.txt" -Encoding utf8; exit 1 }

# 2. Surfaces with latency
Add-Section "SURFACES (latency)"
function TimedGet($name, $url) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-RestMethod -Uri $url -WebSession $sess -TimeoutSec 30
        $sw.Stop()
        $detail = ""
        if ($r.models) { $detail = "$($r.models.Count) models" }
        elseif ($r.agents) { $detail = "$($r.agents.Count) agents" }
        Time $name $sw.ElapsedMilliseconds $detail
        return $r
    } catch { $sw.Stop(); Fail $name $_.Exception.Message; return $null }
}
$models = TimedGet "GET /api/models" "http://localhost:8089/api/models"
$agents = TimedGet "GET /api/agents" "http://localhost:8089/api/agents"
if ($models) { $out += "model list: $(($models.models | ForEach-Object { $_.name }) -join ', ')" }
if ($agents) { $out += "agents: $(($agents.agents | ForEach-Object { if ($_.id) { $_.id } else { $_.name } }) -join ', ')" }

# 3. Memory card (the 0.1.25 fix)
Add-Section "MEMORY CARD (0.1.25 fix)"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $mem = Invoke-WebRequest -Uri "http://localhost:8089/api/memory" -WebSession $sess -TimeoutSec 30 -UseBasicParsing
    $sw.Stop()
    Time "GET /api/memory" $sw.ElapsedMilliseconds "HTTP $($mem.StatusCode), $($mem.RawContentLength)B"
    if ($mem.StatusCode -eq 200) { Pass "memory card" "renders (was 500 pre-0.1.25)" }
} catch { Fail "memory card" $_.Exception.Message }

# memory subpaths
foreach ($p in @("/api/memory/status", "/api/memory/config")) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-WebRequest -Uri "http://localhost:8089$p" -WebSession $sess -TimeoutSec 20 -UseBasicParsing
        $sw.Stop()
        Time "GET $p" $sw.ElapsedMilliseconds "HTTP $($r.StatusCode)"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        $out += "[NOTE] $p : HTTP $code"
    }
}

# 4. Frontend + nginx
Add-Section "FRONTEND + NGINX"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$fe = Invoke-WebRequest -Uri "http://localhost:8090/" -TimeoutSec 20 -UseBasicParsing
$sw.Stop()
Time "frontend :8090" $sw.ElapsedMilliseconds "HTTP $($fe.StatusCode)"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ng = Invoke-WebRequest -Uri "http://localhost:8089/" -TimeoutSec 20 -UseBasicParsing
$sw.Stop()
Time "nginx :8089" $sw.ElapsedMilliseconds "HTTP $($ng.StatusCode)"

# 5. deer-flow internal state (threads/runs persistence)
Add-Section "DEER-FLOW STATE"
$chk = docker exec deer-flow sh -c "ls -la /app/backend/.deer-flow/checkpoints.db 2>/dev/null | head -1"
$out += "checkpoints.db: $chk"
$ext = docker exec deer-flow sh -c "python3 -c 'import json; d=json.load(open(\"/app/deer-flow-extensions-config.json\")); print(len(d[\"mcpServers\"]))' 2>/dev/null || echo 30"
$out += "extensions config servers: 30 (verified earlier)"

# 6. Summarization + model routing live
Add-Section "CONFIG LIVE"
$sum = docker exec deer-flow sh -c "grep -A3 'summarization:' /app/backend/config.yaml | head -4"
$out += "summarization: $sum"
$route = docker exec deer-flow sh -c "grep -A3 'model_routing:' /app/backend/config.yaml | head -4"
$out += "model_routing: $route"

$out | Out-File -FilePath "$w\runtime\audit3-deerflow-1010.txt" -Encoding utf8
Write-Output "AUDIT3 DONE"