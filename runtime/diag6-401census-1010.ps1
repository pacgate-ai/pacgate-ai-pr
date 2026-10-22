# AIPC1 diag6: 401 census by path, MCP auth, runs table, adapter patch liveness
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag6-401census-1010.txt"
"=== AIPC1 DIAG 6 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. NGINX 401 census by path (since container start)"
$ngxAll = docker logs pacgate-nginx 2>&1 | Select-String -Pattern '" (\d{3}) ' 
$all401 = $ngxAll | Where-Object { $_.Matches[0].Groups[1].Value -eq "401" }
"total requests parsed: $($ngxAll.Count)  total 401s: $($all401.Count)" | Add-Content $out -Encoding UTF8
$all401 | ForEach-Object {
  if ($_.Line -match '"(\w+) ([^ ]+) HTTP') { "$($Matches[1]) $($Matches[2])" }
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
  "  $($_.Count)x  $($_.Name)"
} | Add-Content $out -Encoding UTF8
"last 10 raw 401 lines:" | Add-Content $out -Encoding UTF8
$all401 | Select-Object -Last 10 | ForEach-Object { "  $($_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)))" } | Add-Content $out -Encoding UTF8

Add-Sec "2. PACGATE-MCP auth errors (since start)"
$mcpErr = docker logs pacgate-mcp 2>&1 | Select-String -Pattern "401|Unauthorized|auth|token" | Select-Object -Last 20
"matches: $($mcpErr.Count)" | Add-Content $out -Encoding UTF8
$mcpErr | ForEach-Object { "  MCP: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "3. Adapter patch liveness in container"
docker exec deer-flow sh -c "grep -c '_relogin_if_401' /app/adapters/pacgate_deerflow_adapter/client.py 2>/dev/null; ls /app/adapters/pacgate_deerflow_adapter/ 2>/dev/null" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "4. Runs table (correct path: /app/backend/.deer-flow/data/deerflow.db)"
$py = @'
import sqlite3
db = sqlite3.connect("file:/app/backend/.deer-flow/data/deerflow.db?mode=ro", uri=True)
tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
print("tables:", tables)
if "runs" in tables:
    cols = [r[1] for r in db.execute("PRAGMA table_info(runs)").fetchall()]
    rows = db.execute("SELECT * FROM runs ORDER BY rowid DESC LIMIT 14").fetchall()
    for r in rows:
        d = dict(zip(cols, r))
        err = str(d.get("error") or "")[:110].replace("\n"," ")
        print(f'{d.get("created_at","?")} | {str(d.get("status")):8} | {str(d.get("model_name")):30} | {err}')
'@
$tmpPy = "$env:TEMP\qruns3.py"
[System.IO.File]::WriteAllText($tmpPy, $py)
docker cp $tmpPy deer-flow:/tmp/qruns3.py 2>$null
docker exec deer-flow python3 /tmp/qruns3.py 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "5. Frontend better-auth session config (source tree)"
$feEnv = Get-Content "c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\.env" | Select-String -Pattern "BETTER|AUTH|SESSION"
"client-bundle .env auth lines: $($feEnv.Count)"; $feEnv | ForEach-Object { "  $($_.Line -replace '=(.{0,6}).*','=***')" } | Add-Content $out -Encoding UTF8
$authFile = Get-ChildItem "c:\Users\pacga\github-pr\pacgate-law\deer-flow\frontend\src\lib" -Filter "auth*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 5
$authFile | ForEach-Object { "  file: $($_.FullName)" } | Add-Content $out -Encoding UTF8

Add-Sec "6. Today's Ollama census (server.log + server-1.log)"
foreach ($name in @("server.log","server-1.log")) {
  $p = "$env:LOCALAPPDATA\Ollama\$name"
  if (Test-Path $p) {
    $fs = [System.IO.FileStream]::new($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs); $all = @()
    while ($null -ne ($line = $sr.ReadLine())) { $all += $line }
    $sr.Close(); $fs.Close()
    $ev = ($all | Select-String "evicting").Count
    $er = ($all | Select-String "llm server error").Count
    $ld = ($all | Select-String "llama-server started in").Count
    $slow = ($all | Select-String '\| 200 \|.+m\d+s.+\| POST').Count
    "$name : lines=$($all.Count) evictions=$ev server_errors=$er llama_starts=$ld slowPOSTs=$slow lastWrite=$((Get-Item $p).LastWriteTime)" | Add-Content $out -Encoding UTF8
  }
}

Add-Sec "7. FreeRAM"
$os2 = Get-CimInstance Win32_OperatingSystem
"FreeRAM now: {0:N2} GB" -f ($os2.FreePhysicalMemory/1MB) | Add-Content $out -Encoding UTF8
"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
