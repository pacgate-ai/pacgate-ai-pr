# AIPC1 post-fallback smoke: config live, model run, RAM, VRAM, no-swap check
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag7-smoke-1010.txt"
"=== AIPC1 DIAG 7 SMOKE - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. deer-flow healthy + config live"
Start-Sleep -Seconds 8
$h = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code}" http://localhost:8089/api/health
"health: $($h -replace '(.{100}).*','$1...')" | Add-Content $out -Encoding UTF8
docker exec deer-flow /app/backend/.venv/bin/python -c "import yaml; d=yaml.safe_load(open('/app/backend/config.yaml',encoding='utf-8')); print('default:', d['models'][0]['name'], '| tag:', d['models'][0]['model'], '| mem:', d['memory']['model_name'], '| summ:', d['summarization']['model_name'])" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "2. gemma4-12b q8_0 warm generation (timed)"
$genBody = '{"model":"gemma4:12b-it-q8_0","prompt":"Say exactly: PACGATE-FALLBACK-OK","stream":false,"options":{"num_predict":24}}'
$tmpG = "$env:TEMP\ollama-gen2.json"
[System.IO.File]::WriteAllText($tmpG, $genBody)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$gen = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code} T:%{time_total}" --max-time 180 -X POST http://localhost:11434/api/generate --data-binary "@$tmpG"
$sw.Stop()
$genJson = ($gen -split "\|HTTP")[0] | ConvertFrom-Json
"wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s  http=$(($gen -split '`n')[-1])" | Add-Content $out -Encoding UTF8
if ($genJson) {
  "load_duration=$($genJson.load_duration) prompt_eval=$($genJson.prompt_eval_count)@$(($genJson.prompt_eval_duration/1e9).ToString('0.0'))s eval=$($genJson.eval_count)@$(($genJson.eval_duration/1e9).ToString('0.0'))s" | Add-Content $out -Encoding UTF8
  if ($genJson.eval_count -and $genJson.eval_duration) { "GEN SPEED = {0:N1} t/s" -f ($genJson.eval_count/($genJson.eval_duration/1e9)) | Add-Content $out -Encoding UTF8 }
  "response: $($genJson.response)" | Add-Content $out -Encoding UTF8
}

Add-Sec "3. VRAM + RAM after fallback"
$ps = curl.exe --noproxy "*" -s http://localhost:11434/api/ps | ConvertFrom-Json
$ps.models | ForEach-Object { "  loaded: $($_.name) vram=$([math]::Round($_.size_vram/1GB,2))GB total=$([math]::Round($_.size/1GB,2))GB" } | Add-Content $out -Encoding UTF8
$os2 = Get-CimInstance Win32_OperatingSystem
"FreeRAM: {0:N2} GB (was 0.45GB under nemotron)" -f ($os2.FreePhysicalMemory/1MB) | Add-Content $out -Encoding UTF8
$llama = Get-Process llama-server -ErrorAction SilentlyContinue | Select-Object -First 1
if ($llama) { "llama-server WS: {0:N2} GB (was 18.3GB)" -f ($llama.WorkingSet64/1GB) | Add-Content $out -Encoding UTF8 }

Add-Sec "4. GPU engine utilization (gemma4 fully in VRAM?)"
try {
  $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -MaxSamples 1 -ErrorAction Stop
  $top = $c.CounterSamples | Where-Object { $_.CookedValue -gt 1 } | Sort-Object CookedValue -Descending | Select-Object -First 4
  $top | ForEach-Object { "  $($_.InstanceName) = $([math]::Round($_.CookedValue,1))%" } | Add-Content $out -Encoding UTF8
  $m = Get-Counter '\GPU Process Memory(*)\Local Usage' -MaxSamples 1 -ErrorAction Stop
  $topm = $m.CounterSamples | Where-Object { $_.CookedValue -gt 100MB } | Sort-Object CookedValue -Descending | Select-Object -First 4
  $topm | ForEach-Object { "  MEM $($_.InstanceName) = $([math]::Round($_.CookedValue/1GB,2))GB" } | Add-Content $out -Encoding UTF8
} catch { "  GPU counters failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }

Add-Sec "5. Ollama log since restart - evictions?"
$fs = [System.IO.FileStream]::new("$env:LOCALAPPDATA\Ollama\server.log", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = [System.IO.StreamReader]::new($fs); $all = @()
while ($null -ne ($line = $sr.ReadLine())) { $all += $line }
$sr.Close(); $fs.Close()
$recent = $all | Select-Object -Last 60
$ev = ($recent | Select-String "evicting").Count
"evictions in last 60 lines: $ev" | Add-Content $out -Encoding UTF8
$recent | Select-String "llama-server started in|evicting|error" | Select-Object -Last 5 | ForEach-Object { "  $_" } | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
