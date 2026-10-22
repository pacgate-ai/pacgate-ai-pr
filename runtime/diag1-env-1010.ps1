# AIPC1 differential diagnosis - Phase 1: environment + stack state
# Output: runtime/diag1-env-1010.txt
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag1-env-1010.txt"
"=== AIPC1 DIAG 1 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') ===" | Set-Content -Path $out -Encoding UTF8

function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. HOST IDENTITY"
$cs = Get-CimInstance Win32_ComputerSystem
"Host: $($cs.Name)  Model: $($cs.Model)  RAM: {0:N1} GB" -f ($cs.TotalPhysicalMemory/1GB) | Add-Content $out -Encoding UTF8
$os = Get-CimInstance Win32_OperatingSystem
"OS: $($os.Caption) build $($os.BuildNumber)  FreeRAM: {0:N1} GB" -f ($os.FreePhysicalMemory*1KB/1GB) | Add-Content $out -Encoding UTF8
"Uptime since: $($os.LastBootUpTime)" | Add-Content $out -Encoding UTF8

Add-Sec "2. GPU"
Get-CimInstance Win32_VideoController | ForEach-Object {
  "GPU: $($_.Name)  Driver: $($_.DriverVersion) ($($_.DriverDate))  AdapterRAM(reg): $([math]::Round($_.AdapterRAM/1GB,1)) GB  Status: $($_.Status)"
} | Add-Content $out -Encoding UTF8

Add-Sec "3. CLOCK SKEW (local vs HTTP Date header)"
$clockLines = @()
try {
  $req = [System.Net.HttpWebRequest]::Create("https://www.baidu.com")
  $req.Method = "HEAD"; $req.Timeout = 8000
  $resp = $req.GetResponse()
  $serverTime = $resp.Headers["Date"]
  $resp.Close()
  $serverDt = [DateTime]::Parse($serverTime).ToUniversalTime()
  $localDt = (Get-Date).ToUniversalTime()
  $skew = ($localDt - $serverDt).TotalSeconds
  $clockLines += "server=$serverTime  localUTC=$($localDt.ToString('o'))  SKEW_SECONDS=$skew"
} catch { $clockLines += "clock probe failed: $($_.Exception.Message)" }
$clockLines | Add-Content $out -Encoding UTF8
"w32tm /query /status:" | Add-Content $out -Encoding UTF8
w32tm /query /status 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "4. DOCKER CONTAINERS (name/status/restarts)"
docker ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}" | Sort-Object | Add-Content $out -Encoding UTF8

Add-Sec "5. PACGAGE 5 IMAGE PINS + RESTART COUNTS"
$pinLines = @()
foreach ($c in @("pacgate-api","pacgate-mcp","deer-flow","deer-flow-frontend","ocr-service")) {
  $j = docker inspect $c 2>$null | ConvertFrom-Json
  if ($j) {
    $st = $j[0].State
    $pinLines += "$c : image=$($j[0].Config.Image) status=$($st.Status) restarts=$($st.RestartCount) started=$($st.StartedAt) oom=$($st.OOMKilled) exit=$($st.ExitCode)"
  } else { $pinLines += "$c : NOT FOUND" }
}
$pinLines | Add-Content $out -Encoding UTF8

Add-Sec "6. OLLAMA PROCESS + ENV"
Get-Process | Where-Object { $_.Name -like "*ollama*" } | ForEach-Object {
  "$($_.Name) pid=$($_.Id) start=$($_.StartTime) CPUmin=$([math]::Round($_.TotalProcessorTime.TotalMinutes,1)) WS=$([math]::Round($_.WorkingSet64/1GB,2))GB"
} | Add-Content $out -Encoding UTF8
$ollamaEnv = Get-ItemProperty "HKCU:\Environment" -ErrorAction SilentlyContinue
"User-scope OLLAMA_* env:" | Add-Content $out -Encoding UTF8
$ollamaEnv.PSObject.Properties | Where-Object { $_.Name -like "OLLAMA*" } | ForEach-Object { "  $($_.Name)=$($_.Value)" } | Add-Content $out -Encoding UTF8

Add-Sec "7. OLLAMA API - tags + ps (loaded models)"
try {
  $tags = curl.exe --noproxy "*" -s --max-time 10 http://localhost:11434/api/tags | ConvertFrom-Json
  "models installed: $($tags.models.Count)"
  $tags.models | ForEach-Object { "  $($_.name)  size=$([math]::Round($_.size/1GB,1))GB" } | Add-Content $out -Encoding UTF8
} catch { "tags failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }
try {
  $ps = curl.exe --noproxy "*" -s --max-time 10 http://localhost:11434/api/ps | ConvertFrom-Json
  "models LOADED now: $($ps.models.Count)"
  $ps.models | ForEach-Object { "  $($_.name) size_vram=$([math]::Round($_.size_vram/1GB,2))GB size=$([math]::Round($_.size/1GB,2))GB until=$($_.expires_at)" } | Add-Content $out -Encoding UTF8
} catch { "ps failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }

Add-Sec "8. NETWORK - VPN adapters + key endpoints"
Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
  "adapter: $($_.Name) if=$($_.InterfaceDescription) speed=$([math]::Round($_.Speed/1e6,0))Mbps"
} | Add-Content $out -Encoding UTF8
$netLines = @()
foreach ($h in @("ollama.com","registry.ollama.ai","api.github.com","github.com","docker.io")) {
  $r = Test-NetConnection -ComputerName $h -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet
  $netLines += "$h :443 reachable=$r"
}
$netLines | Add-Content $out -Encoding UTF8
"proxy env: HTTP_PROXY=$env:HTTP_PROXY HTTPS_PROXY=$env:HTTPS_PROXY NO_PROXY=$env:NO_PROXY" | Add-Content $out -Encoding UTF8

Add-Sec "9. GPU ENGINE UTILIZATION (perf counters, 3s sample)"
try {
  $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -MaxSamples 1 -ErrorAction Stop
  $top = $c.CounterSamples | Where-Object { $_.CookedValue -gt 1 } | Sort-Object CookedValue -Descending | Select-Object -First 8
  if ($top) { $top | ForEach-Object { "  $($_.InstanceName) = $([math]::Round($_.CookedValue,1))%" } | Add-Content $out -Encoding UTF8 }
  else { "  no GPU engine activity >1%" | Add-Content $out -Encoding UTF8 }
} catch { "  GPU counter failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }
try {
  $m = Get-Counter '\GPU Process Memory(*)\Local Usage' -MaxSamples 1 -ErrorAction Stop
  $topm = $m.CounterSamples | Where-Object { $_.CookedValue -gt 100MB } | Sort-Object CookedValue -Descending | Select-Object -First 8
  if ($topm) { $topm | ForEach-Object { "  MEM $($_.InstanceName) = $([math]::Round($_.CookedValue/1GB,2))GB" } | Add-Content $out -Encoding UTF8 }
  else { "  no process >100MB GPU mem" | Add-Content $out -Encoding UTF8 }
} catch { "  GPU mem counter failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }

Add-Sec "10. TOP CPU + RAM PROCESSES"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 8 | ForEach-Object {
  "  CPU $($_.Name) pid=$($_.Id) cpuMin=$([math]::Round($_.TotalProcessorTime.TotalMinutes,1)) wsGB=$([math]::Round($_.WorkingSet64/1GB,2))"
} | Add-Content $out -Encoding UTF8
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 | ForEach-Object {
  "  RAM $($_.Name) pid=$($_.Id) wsGB=$([math]::Round($_.WorkingSet64/1GB,2))"
} | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
