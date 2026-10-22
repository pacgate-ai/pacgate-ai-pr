# AIPC1 diag3: isolate 401, RAM consumers, deer-flow restart, perf repro
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag3-401-perf-1010.txt"
"=== AIPC1 DIAG 3 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. 401 ISOLATION - fresh login, then /matters with FULL body"
$envFile = "c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\.env"
$envLines = [System.IO.File]::ReadAllLines($envFile)
$email = ($envLines | Where-Object { $_ -like "PACGATE_API_EMAIL=*" }) -replace "PACGATE_API_EMAIL=",""
$pass = ($envLines | Where-Object { $_ -like "PACGATE_API_PASSWORD=*" }) -replace "PACGATE_API_PASSWORD=",""
$tmp = "$env:TEMP\pacgate-login.json"
[System.IO.File]::WriteAllText($tmp, "{`"email`":`"$email`",`"password`":`"$pass`"}")
$loginResp = curl.exe --noproxy "*" -s -X POST http://localhost:8089/pacgate/api/auth/login -H "Content-Type: application/json" --data-binary "@$tmp"
$j = $loginResp | ConvertFrom-Json
$tok = $j.token
"token length: $($tok.Length)  first8: $($tok.Substring(0,8))  last8: $($tok.Substring($tok.Length-8))" | Add-Content $out -Encoding UTF8
# Test A: via nginx with Bearer
$rA = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code}" http://localhost:8089/pacgate/api/matters -H "Authorization: Bearer $tok"
"VIA-NGINX  Bearer   -> $($rA -replace '(.{120}).*','$1...')" | Add-Content $out -Encoding UTF8
# Test B: direct to container IP (bypass nginx)
$apiIP = docker inspect pacgate-api --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"
$rB = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code}" "http://${apiIP}:8080/api/matters" -H "Authorization: Bearer $tok"
"DIRECT     Bearer   -> $($rB -replace '(.{120}).*','$1...')" | Add-Content $out -Encoding UTF8
# Test C: no auth header at all (baseline)
$rC = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code}" http://localhost:8089/pacgate/api/matters
"NO-AUTH    baseline -> $($rC -replace '(.{120}).*','$1...')" | Add-Content $out -Encoding UTF8
# Test D: X-Authorization variant (in case middleware expects different header)
$rD = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code}" http://localhost:8089/pacgate/api/matters -H "authorization: Bearer $tok"
"LOWER-CASE header   -> $($rD -replace '(.{120}).*','$1...')" | Add-Content $out -Encoding UTF8

Add-Sec "2. FULL PROCESS LIST by WorkingSet (top 18)"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 18 | ForEach-Object {
  "  {0,-28} pid={1,-7} ws={2,8:N2}GB  cpuMin={3,8:N1}" -f $_.Name,$_.Id,($_.WorkingSet64/1GB),$_.TotalProcessorTime.TotalMinutes
} | Add-Content $out -Encoding UTF8
$sum = (Get-Process | Measure-Object WorkingSet64 -Sum).Sum
"Sum of all process WS: {0:N1} GB" -f ($sum/1GB) | Add-Content $out -Encoding UTF8

Add-Sec "3. DEER-FLOW restart forensics"
$df = docker inspect deer-flow | ConvertFrom-Json
"RestartCount=$($df[0].RestartCount) OOMKilled=$($df[0].State.OOMKilled) ExitCode=$($df[0].State.ExitCode) StartedAt=$($df[0].State.StartedAt) FinishedAt=$($df[0].State.FinishedAt)" | Add-Content $out -Encoding UTF8

Add-Sec "4. PERF REPRO: nemotron warm generation (200 tokens, timed)"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$genBody = '{"model":"nemotron-3.5-lightning:30b-a3b","prompt":"Say exactly: PACGATE-PERF-OK","stream":false,"options":{"num_predict":24}}'
$tmpG = "$env:TEMP\ollama-gen.json"
[System.IO.File]::WriteAllText($tmpG, $genBody)
$gen = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code} T:%{time_total}" --max-time 120 -X POST http://localhost:11434/api/generate --data-binary "@$tmpG"
$sw.Stop()
$genLine = ($gen -split "`n" | Select-Object -Last 1)
$genJson = ($gen -split "\|HTTP")[0] | ConvertFrom-Json
"wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s  http_line=$genLine" | Add-Content $out -Encoding UTF8
if ($genJson) {
  "prompt_eval_count=$($genJson.prompt_eval_count) prompt_eval_duration=$($genJson.prompt_eval_duration) eval_count=$($genJson.eval_count) eval_duration=$($genJson.eval_duration)" | Add-Content $out -Encoding UTF8
  if ($genJson.eval_count -and $genJson.eval_duration) {
    "GEN SPEED = {0:N1} tokens/sec  (benchmark reference: 17.5 t/s on this box, 30.7 t/s earlier)" -f ($genJson.eval_count / ($genJson.eval_duration/1e9)) | Add-Content $out -Encoding UTF8
  }
  "response: $($genJson.response)" | Add-Content $out -Encoding UTF8
}

Add-Sec "5. CLOUD MODEL REPRO: deepseek-v4.1-flash:cloud direct ping"
$cloudBody = '{"model":"deepseek-v4.1-flash:cloud","prompt":"Say exactly: CLOUD-OK","stream":false,"options":{"num_predict":16}}'
$tmpC = "$env:TEMP\ollama-cloud.json"
[System.IO.File]::WriteAllText($tmpC, $cloudBody)
$swC = [System.Diagnostics.Stopwatch]::StartNew()
$cloud = curl.exe --noproxy "*" -s -w "|HTTP:%{http_code} T:%{time_total}" --max-time 90 -X POST http://localhost:11434/api/generate --data-binary "@$tmpC"
$swC.Stop()
"wall=$([math]::Round($swC.Elapsed.TotalSeconds,1))s  resp=$(($cloud -split "`n" | Select-Object -Last 1))" | Add-Content $out -Encoding UTF8
$cloudJson = ($cloud -split "\|HTTP")[0] | ConvertFrom-Json
if ($cloudJson.error) { "CLOUD ERROR: $($cloudJson.error)" | Add-Content $out -Encoding UTF8 }
elseif ($cloudJson.response) { "CLOUD OK: $($cloudJson.response)" | Add-Content $out -Encoding UTF8 }

Add-Sec "6. WSL + pagefile config"
if (Test-Path "$env:USERPROFILE\.wslconfig") { Get-Content "$env:USERPROFILE\.wslconfig" | Add-Content $out -Encoding UTF8 } else { ".wslconfig: ABSENT (no WSL memory cap)" | Add-Content $out -Encoding UTF8 }
$cs = Get-CimInstance Win32_ComputerSystem
"AutomaticManagedPagefile=$($cs.AutomaticManagedPagefile)" | Add-Content $out -Encoding UTF8

Add-Sec "7. GPU VRAM detail via ollama ps (post-test)"
$ps = curl.exe --noproxy "*" -s http://localhost:11434/api/ps | ConvertFrom-Json
$ps.models | ForEach-Object { "  $($_.name) vram=$([math]::Round($_.size_vram/1GB,2))GB total=$([math]::Round($_.size/1GB,2))GB" } | Add-Content $out -Encoding UTF8
$os2 = Get-CimInstance Win32_OperatingSystem
"FreeRAM now: {0:N2} GB" -f ($os2.FreePhysicalMemory/1MB) | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
