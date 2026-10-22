# AIPC1 diag2: RAM pressure, Ollama log scan, deer-flow restart, 401 trace
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag2-ram-401-1010.txt"
"=== AIPC1 DIAG 2 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. MEMORY PRESSURE DETAIL"
$os = Get-CimInstance Win32_OperatingSystem
"TotalVisible={0:N1}GB FreePhysical={1:N2}GB UsedPhysical={2:N1}GB" -f ($os.TotalVisibleMemorySize/1MB),($os.FreePhysicalMemory/1MB),(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB) | Add-Content $out -Encoding UTF8
$pf = Get-CimInstance Win32_PageFileUsage
$pf | ForEach-Object { "Pagefile $($_.Name): AllocatedBase=$($_.AllocatedBaseSize)MB CurrentUsage=$($_.CurrentUsage)MB PeakUsage=$($_.PeakUsage)MB" } | Add-Content $out -Encoding UTF8
$perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
"Committed={0:N1}GB CommitLimit={1:N1}GB PercentCommitted={2}%% AvailableMB={3}" -f ($perf.CommittedBytes/1GB),($perf.CommitLimit/1GB),$perf.PercentCommittedBytesInUse,$perf.AvailableMBytes | Add-Content $out -Encoding UTF8
"PagesOutput/sec (hard page faults to disk): $($perf.PagesOutputPerSec)" | Add-Content $out -Encoding UTF8
"PageReads/sec: $($perf.PageReadsPerSec)" | Add-Content $out -Encoding UTF8
# 5-second sample of paging
$s1 = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
Start-Sleep -Seconds 5
$s2 = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
"PagesOutput over 5s: $($s2.PagesOutput - $s1.PagesOutput)  PageReads over 5s: $($s2.PageReadsPerSec - $s1.PageReadsPerSec)" | Add-Content $out -Encoding UTF8

Add-Sec "2. OLLAMA SERVER LOG - evictions/reloads/errors since 18:34"
$logDir = "$env:LOCALAPPDATA\Ollama"
$logs = Get-ChildItem $logDir -Filter "server*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2
foreach ($l in $logs) {
  "LOG: $($l.FullName) size=$([math]::Round($l.Length/1MB,1))MB lastWrite=$($l.LastWriteTime)" | Add-Content $out -Encoding UTF8
  $content = [System.IO.File]::ReadAllLines($l.FullName) | Select-Object -Last 4000
  $evict = $content | Select-String -Pattern "evict" | Select-Object -Last 10
  "evict lines (last 10): $($evict.Count)" | Add-Content $out -Encoding UTF8
  $evict | ForEach-Object { "  EVICT: $_" } | Add-Content $out -Encoding UTF8
  $loads = $content | Select-String -Pattern "llama-server started in|loading model" | Select-Object -Last 15
  $loads | ForEach-Object { "  LOAD: $_" } | Add-Content $out -Encoding UTF8
  $errs = $content | Select-String -Pattern "error|ERROR|failed" | Select-Object -Last 15
  "error lines (last 15 of scan): $($errs.Count)" | Add-Content $out -Encoding UTF8
  $errs | ForEach-Object { "  ERR: $_" } | Add-Content $out -Encoding UTF8
  $srv = $content | Select-String -Pattern "server config" | Select-Object -Last 1
  $srv | ForEach-Object { "  CONFIG: $_" } | Add-Content $out -Encoding UTF8
}

Add-Sec "3. DEER-FLOW: why restarted 1h ago + recent errors"
docker logs deer-flow --since 2h 2>&1 | Select-Object -First 5 | Add-Content $out -Encoding UTF8
"...(tail)" | Add-Content $out -Encoding UTF8
$dfErr = docker logs deer-flow --since 2h 2>&1 | Select-String -Pattern "error|Error|ERROR|401|403|429|timeout|Timeout" | Select-Object -Last 30
$dfErr | ForEach-Object { "  DF: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "4. PACGATE-API: 401 frequency in last 2h"
$api401 = docker logs pacgate-api --since 2h 2>&1 | Select-String -Pattern "401" | Select-Object -Last 40
"401 lines: $($api401.Count)" | Add-Content $out -Encoding UTF8
$api401 | ForEach-Object { "  API: $_" } | Add-Content $out -Encoding UTF8
$apiErr = docker logs pacgate-api --since 2h 2>&1 | Select-String -Pattern "ERROR|WARN|expired|invalid" | Select-Object -Last 20
$apiErr | ForEach-Object { "  APIERR: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "5. NGINX: 401/499/502 in access log last 2h"
$ngx = docker logs pacgate-nginx --since 2h 2>&1 | Select-String -Pattern " 401 | 499 | 502 | 504 " | Select-Object -Last 30
"matches: $($ngx.Count)" | Add-Content $out -Encoding UTF8
$ngx | ForEach-Object { "  NGX: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "6. HERMES-WEB crash loop confirmation"
$h = docker inspect hermes-web | ConvertFrom-Json
"RestartCount=$($h[0].RestartCount) Status=$($h[0].State.Status) ExitCode=$($h[0].State.ExitCode) StartedAt=$($h[0].State.StartedAt)" | Add-Content $out -Encoding UTF8
docker logs hermes-web --tail 5 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "7. LIVE LOGIN TESTS (fresh tokens)"
# pacgate-api login
$envFile = "c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\.env"
$envLines = [System.IO.File]::ReadAllLines($envFile)
$email = ($envLines | Where-Object { $_ -like "PACGATE_API_EMAIL=*" }) -replace "PACGATE_API_EMAIL=",""
$pass = ($envLines | Where-Object { $_ -like "PACGATE_API_PASSWORD=*" }) -replace "PACGATE_API_PASSWORD=",""
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$loginBody = "{`"email`":`"$email`",`"password`":`"$pass`"}"
$tmp = "$env:TEMP\pacgate-login.json"
[System.IO.File]::WriteAllText($tmp, $loginBody)
$apiResp = curl.exe --noproxy "*" -s -w "`nHTTP:%{http_code} T:%{time_total}" -X POST http://localhost:8089/pacgate/api/auth/login -H "Content-Type: application/json" --data-binary "@$tmp"
$sw.Stop()
"pacgate-api login: $apiResp  (wall $($sw.ElapsedMilliseconds)ms)" | Add-Content $out -Encoding UTF8
if ($apiResp -match '"token":"([^"]+)"') {
  $tok = $Matches[1]
  $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
  $matters = curl.exe --noproxy "*" -s -w "`nHTTP:%{http_code} T:%{time_total}" http://localhost:8089/pacgate/api/matters -H "Authorization: Bearer $tok"
  $sw2.Stop()
  "pacgate-api /matters with fresh token: HTTP line = $($matters -split "`n" | Select-Object -Last 1)  (wall $($sw2.ElapsedMilliseconds)ms)" | Add-Content $out -Encoding UTF8
  # decode JWT exp if it's a JWT
  if ($tok -like "*.*.*") {
    try {
      $parts = $tok.Split(".")
      $payload = $parts[1].Replace("-","+").Replace("_","/")
      switch ($payload.Length % 4) { 2 { $payload += "==" } 3 { $payload += "=" } }
      $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
      "JWT payload: iat=$($json.iat) exp=$($json.exp) now=$((Get-Date).ToUniversalTime().Subtract('1970-01-01').TotalSeconds -as [int])" | Add-Content $out -Encoding UTF8
      if ($json.exp) { "JWT TTL minutes: $([math]::Round(($json.exp - $json.iat)/60,1))" | Add-Content $out -Encoding UTF8 }
    } catch { "JWT decode failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }
  }
}

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
