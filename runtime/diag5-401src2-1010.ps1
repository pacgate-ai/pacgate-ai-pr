# AIPC1 diag5: 401 source hunt (adapter env, frontend session), runs history, eviction census
$ErrorActionPreference = "Continue"
$out = "c:\Users\pacga\github-pr\pacgate-law\runtime\diag5-401src2-1010.txt"
"=== AIPC1 DIAG 5 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

Add-Sec "1. DEER-FLOW container env (PACGATE/ADAPTER vars)"
docker exec deer-flow sh -c "env | grep -iE 'pacgate|adapter|api_url|api_email' | sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=.{0,6}.*/\1=***REDACTED***/I'" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "2. Find deerflow.db + runs table"
docker exec deer-flow sh -c "find /app/backend -name 'deerflow.db' -o -name '*.db' 2>/dev/null | head -5" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "3. Runs history (correct path)"
$py = @'
import sqlite3, os, glob
cands = glob.glob("/app/backend/**/*.db", recursive=True)
print("dbs:", cands)
for db_path in cands:
    if "checkpoint" in db_path: continue
    try:
        db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        print(f"--- {db_path}: tables={tables[:12]}")
        if "runs" in tables:
            cols = [r[1] for r in db.execute("PRAGMA table_info(runs)").fetchall()]
            print("    runs cols:", cols)
            rows = db.execute("SELECT * FROM runs ORDER BY rowid DESC LIMIT 12").fetchall()
            for r in rows:
                d = dict(zip(cols, r))
                err = str(d.get("error") or "")[:100]
                print(f'    {d.get("created_at","?")} | {str(d.get("status")):8} | {str(d.get("model_name")):30} | {err}')
        db.close()
    except Exception as e:
        print(f"    {db_path}: ERR {e}")
'@
$tmpPy = "$env:TEMP\qruns2.py"
[System.IO.File]::WriteAllText($tmpPy, $py)
docker cp $tmpPy deer-flow:/tmp/qruns2.py 2>$null
docker exec deer-flow python3 /tmp/qruns2.py 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "4. Adapter auth: how does deer-flow call pacgate-api? (source grep)"
docker exec deer-flow sh -c "grep -rn 'Authorization\|Bearer\|login' /app/backend/packages/pacgate_deerflow_adapter/*.py 2>/dev/null | grep -iv 'def test' | head -20" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "5. Adapter 401 handling (re-login logic present?)"
docker exec deer-flow sh -c "grep -rn '401\|reauth\|re-login\|_login\|token_cache' /app/backend/packages/pacgate_deerflow_adapter/*.py 2>/dev/null | head -25" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "6. Frontend better-auth session expiry config"
docker exec deer-flow-frontend sh -c "env | grep -iE 'better|auth|session|maxAge' | sed -E 's/(SECRET|KEY|PASSWORD)=.{0,6}.*/\1=***REDACTED***/I'" 2>&1 | Add-Content $out -Encoding UTF8

Add-Sec "7. pacgate-api JWT secret rotation check (would invalidate all tokens)"
docker exec pacgate-api sh -c "env | grep -iE 'jwt|secret|token' | sed -E 's/=(.{0,6}).*/=\1***/'" 2>&1 | Add-Content $out -Encoding UTF8
$envLines = [System.IO.File]::ReadAllLines("c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\.env")
$jwt = $envLines | Where-Object { $_ -like "JWT_SECRET=*" -or $_ -like "*JWT*" }
"host .env JWT lines (names only): $(($jwt | ForEach-Object { ($_ -split '=')[0] }) -join ', ')" | Add-Content $out -Encoding UTF8

Add-Sec "8. Ollama eviction/error census - FULL DAY (server-1.log + rotated)"
$logs = Get-ChildItem "$env:LOCALAPPDATA\Ollama" -Filter "server*.log" | Sort-Object LastWriteTime
foreach ($l in $logs) {
  $fs = [System.IO.FileStream]::new($l.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  $sr = [System.IO.StreamReader]::new($fs); $all = @()
  while ($null -ne ($line = $sr.ReadLine())) { $all += $line }
  $sr.Close(); $fs.Close()
  $ev = ($all | Select-String "evicting").Count
  $er = ($all | Select-String "llm server error").Count
  $ld = ($all | Select-String "llama-server started in").Count
  "$($l.Name): lines=$($all.Count) evictions=$ev server_errors=$er llama_starts=$ld lastWrite=$($l.LastWriteTime)" | Add-Content $out -Encoding UTF8
}

Add-Sec "9. Today's GIN latency histogram (slow calls >30s) from live log"
$fs = [System.IO.FileStream]::new("$env:LOCALAPPDATA\Ollama\server.log", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = [System.IO.StreamReader]::new($fs); $all = @()
while ($null -ne ($line = $sr.ReadLine())) { $all += $line }
$sr.Close(); $fs.Close()
$slow = $all | Select-String -Pattern '\| 200 \|.+m\d+s.+\| POST' 
"slow POST calls (>1m): $($slow.Count)" | Add-Content $out -Encoding UTF8
$slow | Select-Object -Last 12 | ForEach-Object { "  $_" } | Add-Content $out -Encoding UTF8

Add-Sec "10. FreeRAM + pagefile delta"
$os2 = Get-CimInstance Win32_OperatingSystem
"FreeRAM now: {0:N2} GB" -f ($os2.FreePhysicalMemory/1MB) | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
