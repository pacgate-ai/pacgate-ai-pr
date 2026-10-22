# Memory lanes: OpenViking MCP remember/find + vector DB state — 2026-10-10
# Uses the upstream ov-mcp-call.ps1 pattern (X-API-Key + SSE + isError surfacing)
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }

# 1. OpenViking MCP health
Add-Section "OPENVIKING MCP"
$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}
$ovKey = $envVars["OPENVIKING_ROOT_API_KEY"]
if (-not $ovKey) { Fail "openviking key" "OPENVIKING_ROOT_API_KEY not in .env"; $out | Out-File "$w\runtime\audit4-memory-ov-1010.txt" -Encoding utf8; exit 1 }
Pass "API key" "present ($($ovKey.Length) chars)"

function Invoke-OvMcp($payload) {
    $json = $payload | ConvertTo-Json -Depth 12 -Compress
    $tmp = "$env:TEMP\ov-call-1010.json"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-WebRequest -Uri "http://localhost:1933/mcp" -Method Post -Headers @{ "X-API-Key" = $ovKey; Accept = "application/json, text/event-stream" } -ContentType "application/json" -InFile $tmp -TimeoutSec 120 -UseBasicParsing
    $dataLine = ($r.Content -split "`n" | Where-Object { $_ -match "^data:" } | Select-Object -First 1)
    if (-not $dataLine) { throw "no SSE data line: $($r.Content.Substring(0,[Math]::Min(200,$r.Content.Length)))" }
    return ($dataLine.Substring(5).Trim() | ConvertFrom-Json)
}

# health tool
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $h = Invoke-OvMcp @{ jsonrpc = "2.0"; id = 1; method = "tools/call"; params = @{ name = "health"; arguments = @{} } }
    $sw.Stop()
    Time "health" $sw.ElapsedMilliseconds ($h.result.content[0].text.Substring(0, [Math]::Min(120, $h.result.content[0].text.Length)))
    Pass "openviking MCP" "responds"
} catch { $sw.Stop(); Fail "openviking health" $_.Exception.Message }

# 2. remember + find (the async extraction lane) — unique marker this run
Add-Section "REMEMBER + FIND (async extraction)"
$marker = "AUDIT-OV-1010-$((Get-Date).ToString('HHmmss'))"
$fact = "Benchmark audit fact: the QM portal front door is gated by OIDC and the liveness surface is healthz. Token $marker"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $wResp = Invoke-OvMcp @{ jsonrpc = "2.0"; id = 2; method = "tools/call"; params = @{ name = "remember"; arguments = @{ messages = @(@{ role = "user"; content = $fact }) } } }
    $sw.Stop()
    if ($wResp.result.isError) { Fail "remember" $wResp.result.content[0].text }
    else { Time "remember (write accepted)" $sw.ElapsedMilliseconds "extraction is async — polling find()" }
} catch { $sw.Stop(); Fail "remember" $_.Exception.Message }

# poll find() — budget 420s (upstream-tuned)
$deadline = (Get-Date).AddSeconds(420)
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$found = $false
$polls = 0
while ((Get-Date) -lt $deadline -and -not $found) {
    Start-Sleep -Seconds 15
    $polls++
    try {
        $f = Invoke-OvMcp @{ jsonrpc = "2.0"; id = 3; method = "tools/call"; params = @{ name = "find"; arguments = @{ query = $marker } } }
        $txt = $f.result.content[0].text
        if ($txt -match [regex]::Escape($marker)) { $found = $true }
    } catch { $out += "[NOTE] find poll $polls error: $($_.Exception.Message)" }
}
$sw2.Stop()
if ($found) { Pass "find (recall)" "marker surfaced after $([int]$sw2.ElapsedMilliseconds)ms ($polls polls)" }
else { Fail "find (recall)" "marker NOT surfaced within 420s ($polls polls) — extraction lane incomplete" }

# 3. Vector DB state (pgvector in pacgate-db)
Add-Section "PGVECTOR STATE"
$emb = docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(*) from kb_chunks where embedding is not null;" 2>&1
$out += "kb_chunks with embeddings: $emb"
$idx = docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select indexname from pg_indexes where tablename='kb_chunks';" 2>&1
$out += "kb_chunks indexes: $idx"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$vec = docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(*) from kb_chunks where embedding is not null and matter_id='769225d9-804c-4a3f-8775-8dcc4c676d0e';" 2>&1
$sw.Stop()
Time "vector count query" $sw.ElapsedMilliseconds "matter-scoped: $vec"

# 4. Embedding lane
Add-Section "EMBEDDING LANE"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$embReq = @{ model = "nomic-embed-text"; prompt = "benchmark audit probe" } | ConvertTo-Json -Compress
$embTmp = "$env:TEMP\audit-emb-1010.json"
[System.IO.File]::WriteAllText($embTmp, $embReq, (New-Object System.Text.UTF8Encoding($false)))
$embResp = Invoke-RestMethod -Uri "http://localhost:11434/api/embeddings" -Method Post -ContentType "application/json" -InFile $embTmp -TimeoutSec 30
$sw.Stop()
Time "nomic-embed-text" $sw.ElapsedMilliseconds "dims=$($embResp.embedding.Count)"

# 5. OpenViking storage state
Add-Section "OPENVIKING STORAGE"
$ovData = docker exec openviking sh -c "du -sh /app/.openviking 2>/dev/null || du -sh /data 2>/dev/null || echo n/a" 2>&1
$out += "openviking data: $ovData"
$ovMounts = docker inspect openviking | ConvertFrom-Json | ForEach-Object { $_.Mounts | ForEach-Object { "$($_.Source) -> $($_.Destination)" } }
$out += "openviking mounts:"; $out += $ovMounts

$out | Out-File -FilePath "$w\runtime\audit4-memory-ov-1010.txt" -Encoding utf8
Write-Output "AUDIT4 DONE"