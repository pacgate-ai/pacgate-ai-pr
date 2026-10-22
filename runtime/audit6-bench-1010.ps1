# Performance benchmark: LLM lanes + HTTP latencies (3 samples each) — 2026-10-10
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }

# 1. HTTP latencies (3 samples)
Add-Section "HTTP LATENCY (3 samples)"
function Lat3($name, $url) {
    $times = @()
    for ($i = 0; $i -lt 3; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { Invoke-WebRequest -Uri $url -TimeoutSec 20 -UseBasicParsing | Out-Null } catch {}
        $sw.Stop()
        $times += $sw.ElapsedMilliseconds
    }
    Time $name ($times -join " / ") "ms (3 samples)"
}
Lat3 "nginx :8089 /" "http://localhost:8089/"
Lat3 "frontend :8090 /" "http://localhost:8090/"
Lat3 "frontend /api/memory (authed path)" "http://localhost:8089/api/memory/status"

# 2. LLM lanes
Add-Section "LLM LANES (Ollama)"
function LlmGen($name, $model, $prompt) {
    $body = @{ model = $model; prompt = $prompt; stream = $false } | ConvertTo-Json -Compress
    $tmp = "$env:TEMP\bench-llm-1010.json"
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 300
        $sw.Stop()
        $tps = if ($r.eval_count -and $r.eval_duration) { [Math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1) } else { "n/a" }
        $tpsLoad = if ($r.prompt_eval_count -and $r.prompt_eval_duration) { [Math]::Round($r.prompt_eval_count / ($r.prompt_eval_duration / 1e9), 1) } else { "n/a" }
        Time $name $sw.ElapsedMilliseconds "total | gen $tps t/s | prefill $tpsLoad t/s | tokens=$($r.eval_count)"
    } catch { $sw.Stop(); Time $name $sw.ElapsedMilliseconds "FAILED: $($_.Exception.Message)" }
}
LlmGen "nemotron-30b (default, warm)" "nemotron-3.5-lightning:30b-a3b" "Reply with exactly: BENCH-OK"
LlmGen "gemma4-12b (qat)" "gemma4:12b-it-qat" "Reply with exactly: BENCH-OK"
LlmGen "ornith-1.5-9b" "ornith-1.5:9b" "Reply with exactly: BENCH-OK"

# 3. GPU placement
Add-Section "GPU PLACEMENT"
$ps = ollama ps 2>&1 | Out-String
$out += $ps

# 4. Embedding (3 samples)
Add-Section "EMBEDDING (3 samples)"
$embTimes = @()
for ($i = 0; $i -lt 3; $i++) {
    $body = @{ model = "nomic-embed-text"; prompt = "benchmark sample $i" } | ConvertTo-Json -Compress
    $tmp = "$env:TEMP\bench-emb-1010.json"
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod -Uri "http://localhost:11434/api/embeddings" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 30 | Out-Null
    $sw.Stop()
    $embTimes += $sw.ElapsedMilliseconds
}
Time "nomic-embed-text" ($embTimes -join " / ") "ms (3 samples)"

# 5. Authenticated API latency (3 samples)
Add-Section "AUTHED API (3 samples)"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}
$body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
$tmp = "$env:TEMP\bench-login-1010.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
$login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 20
$h = @{ Authorization = "Bearer $($login.token)" }
$times = @()
for ($i = 0; $i -lt 3; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/workflows" -Headers $h -TimeoutSec 30 | Out-Null
    $sw.Stop()
    $times += $sw.ElapsedMilliseconds
}
Time "GET /workflows (222 items)" ($times -join " / ") "ms (3 samples)"
$times = @()
for ($i = 0; $i -lt 3; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/kb/search?q=contract&matter_id=769225d9-804c-4a3f-8775-8dcc4c676d0e&top_k=5" -Headers $h -TimeoutSec 30 | Out-Null
    $sw.Stop()
    $times += $sw.ElapsedMilliseconds
}
Time "GET /kb/search (pgvector, 1828 chunks)" ($times -join " / ") "ms (3 samples)"

# 6. MCP latency (3 samples)
Add-Section "MCP (3 samples)"
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
sid, _ = call({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bench","version":"1.0"}}})
times = []
for i in range(3):
    t0 = time.time()
    _, lm = call({"jsonrpc":"2.0","id":10+i,"method":"tools/call","params":{"name":"pacgate_list_matters","arguments":{}}}, sid)
    times.append(int((time.time()-t0)*1000))
print("list_matters x3:", " / ".join(map(str, times)), "ms")
'@
$pyB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
$mcpBench = docker exec pacgate-mcp sh -c "echo $pyB64 | base64 -d | python3" 2>&1
$out += "MCP $mcpBench"

$out | Out-File -FilePath "$w\runtime\audit6-bench-1010.txt" -Encoding utf8
Write-Output "AUDIT6 DONE"