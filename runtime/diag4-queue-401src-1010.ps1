# AIPC1 diag4: live Ollama log (shared read), NUM_PARALLEL, adapter 401s, cloud body
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag4-queue-401src-1010.txt"
"=== AIPC1 DIAG 4 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. LIVE OLLAMA server.log (FileShare read) - last 120 lines"
$logPath = "$env:LOCALAPPDATA\Ollama\server.log"
try {
  $fs = [System.IO.FileStream]::new($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  $sr = [System.IO.StreamReader]::new($fs)
  $all = @()
  while ($null -ne ($line = $sr.ReadLine())) { $all += $line }
  $sr.Close(); $fs.Close()
  "total lines: $($all.Count)" | Add-Content $out -Encoding UTF8
  $all | Select-Object -Last 120 | Add-Content $out -Encoding UTF8
} catch { "read failed: $($_.Exception.Message)" | Add-Content $out -Encoding UTF8 }

Add-Sec "2. OLLAMA ENV - Machine scope + process-level"
$machineEnv = [System.Environment]::GetEnvironmentVariables("Machine")
$machineEnv.Keys | Where-Object { $_ -like "OLLAMA*" } | ForEach-Object { "MACHINE $_ = $($machineEnv[$_])" } | Add-Content $out -Encoding UTF8
$proc = Get-Process ollama -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
  "ollama pid=$($proc.Id) start=$($proc.StartTime)" | Add-Content $out -Encoding UTF8
}

Add-Sec "3. DEER-FLOW adapter + gateway 401s today"
$df401 = docker logs deer-flow --since 10h 2>&1 | Select-String -Pattern "401|Unauthorized|unauthorized|reauth|re-login|token" | Select-Object -Last 25
"matches: $($df401.Count)" | Add-Content $out -Encoding UTF8
$df401 | ForEach-Object { "  DF: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "4. DEER-FLOW cloud-model errors today (429/timeout/flash)"
$dfCloud = docker logs deer-flow --since 10h 2>&1 | Select-String -Pattern "429|rate.limit|cloud|deepseek|glm" | Select-Object -Last 25
"matches: $($dfCloud.Count)" | Add-Content $out -Encoding UTF8
$dfCloud | ForEach-Object { "  DF: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "5. DEER-FLOW runs today - status/model/error from deerflow.db"
$py = @'
import sqlite3, json
db = sqlite3.connect("/app/backend/.deer-flow/deerflow.db")
db.row_factory = sqlite3.Row
rows = db.execute("SELECT id, status, model_name, error, created_at FROM runs ORDER BY created_at DESC LIMIT 15").fetchall()
for r in rows:
    err = (r["error"] or "")[:120]
    print(f'{r["created_at"]} | {r["status"]:8} | {r["model_name"]:32} | {err}')
'@
$tmpPy = "$env:TEMP\qruns.py"
[System.IO.File]::WriteAllText($tmpPy, $py)
docker cp $tmpPy deer-flow:/tmp/qruns.py 2>$null
docker exec deer-flow python3 /tmp/qruns.py 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "6. CLOUD RETEST with full body capture"
$cloudBody = '{"model":"deepseek-v4.1-flash:cloud","prompt":"Reply with exactly: CLOUD-OK-1010","stream":false,"options":{"num_predict":16}}'
$tmpC = "$env:TEMP\ollama-cloud2.json"
[System.IO.File]::WriteAllText($tmpC, $cloudBody)
$swC = [System.Diagnostics.Stopwatch]::StartNew()
$cloud = curl.exe --noproxy "*" -s --max-time 90 -X POST http://localhost:11434/api/generate --data-binary "@$tmpC"
$swC.Stop()
"wall=$([math]::Round($swC.Elapsed.TotalSeconds,1))s" | Add-Content $out -Encoding UTF8
$cloud | Add-Content $out -Encoding UTF8

Add-Sec "7. WHO ELSE CALLS OLLAMA - open-webui/hermes config check"
docker inspect open-webui --format "{{.Config.Image}} env={{range .Config.Env}}{{.}} {{end}}" 2>$null | Add-Content $out -Encoding UTF8
$hg = docker exec hermes-gateway sh -c "grep -i ollama /opt/hermes/config.yaml 2>/dev/null | head -5" 2>$null
if ($hg) { "hermes-gateway ollama refs: $hg" | Add-Content $out -Encoding UTF8 }

Add-Sec "8. FreeRAM snapshot"
$os2 = Get-CimInstance Win32_OperatingSystem
"FreeRAM now: {0:N2} GB" -f ($os2.FreePhysicalMemory/1MB) | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
