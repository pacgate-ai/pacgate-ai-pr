$repo  = 'c:\Users\pacga\github-pr\pacgate-law'
$oldCB = 'C:\pacgate-ai-pr\deploy\client-bundle'
$newCB = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$oldQM = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$newQM = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'
$out   = Join-Path $repo 'runtime\relocate\CUTOVER-RESUME.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }
function Step([string]$m) { Write-Host "`n>>> $m" -ForegroundColor Cyan; $L.Add(""); $L.Add(">>> $m") }
function Info([string]$m) { Write-Host "    $m"; $L.Add("    $m") }

# ROOT CAUSE of the interruption: $ErrorActionPreference='Stop' plus a native
# command (docker) writing progress to STDERR makes PowerShell raise
# NativeCommandError and abort. Docker writes normal progress text to stderr, so
# this is NOT a real failure. Use 'Continue' + check $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

A 'CUTOVER RESUME (after the NativeCommandError interruption)'
A ('=' * 70)
A ''
A 'State at resume: pacgate-ai-bundle stack DOWN, pre-copy complete,'
A 'qm stack still up. This continues from step 4 of task3-cutover.ps1.'

$items = @(
    @{ s = "$oldCB\data";                             d = "$newCB\data";                             kind = 'dir' },
    @{ s = "$oldCB\openviking";                       d = "$newCB\openviking";                       kind = 'dir' },
    @{ s = "$oldCB\.env";                             d = "$newCB\.env";                             kind = 'file' },
    @{ s = "$oldCB\deer-flow-extensions-config.json"; d = "$newCB\deer-flow-extensions-config.json"; kind = 'file' },
    @{ s = "$oldQM\node_modules";                     d = "$newQM\node_modules";                     kind = 'dir' },
    @{ s = "$oldQM\.env";                             d = "$newQM\.env";                             kind = 'file' }
)

# ---- 3b. stop qm too (it also binds old paths) -----------------------------
Step '3b. Stop the qm stack (it also binds paths under the old location)'
if (Test-Path (Join-Path $oldQM 'compose.qm.yaml')) {
    Push-Location $oldQM
    $r = & docker compose -f compose.qm.yaml down 2>&1
    Info "exit=$LASTEXITCODE"
    foreach ($x in @($r | Select-Object -Last 6)) { Info ("  " + "$x") }
    Pop-Location
}
Info "containers running now: $(@(docker ps -q).Count)"

# ---- 4. incremental re-copy ------------------------------------------------
Step '4. Incremental re-copy (makes the copy consistent - writers are stopped)'
foreach ($i in $items) {
    if (-not (Test-Path -LiteralPath $i.s)) { Info "skip (absent): $($i.s)"; continue }
    $t0 = Get-Date
    if ($i.kind -eq 'dir') {
        & robocopy $i.s $i.d /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    } else {
        $dd = Split-Path -Parent $i.d
        if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
        Copy-Item -LiteralPath $i.s -Destination $i.d -Force
        $LASTEXITCODE = 0
    }
    $rc = $LASTEXITCODE
    Info ("{0,-34} rc={1,-3} {2:N1}s" -f (Split-Path -Leaf $i.s), $rc, ((Get-Date)-$t0).TotalSeconds)
    if ($i.kind -eq 'dir' -and $rc -ge 8) { A "  FAILED robocopy $($i.s)"; }
}

# ---- 5. verify -------------------------------------------------------------
Step '5. Verify the copy before starting anything'
$abort = $false
foreach ($p in @(@{s="$oldCB\data";d="$newCB\data"}, @{s="$oldQM\node_modules";d="$newQM\node_modules"})) {
    if (-not (Test-Path $p.s)) { continue }
    $so = @(Get-ChildItem $p.s -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $dn = @(Get-ChildItem $p.d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $ok = ($dn -ge $so)
    if (-not $ok) { $abort = $true }
    Info ("{0,-20} source={1,-7} dest={2,-7} {3}" -f (Split-Path -Leaf $p.s), $so, $dn, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
}

$mountSources = @("$newCB\data", "$newCB\deer-flow-extensions-config.json", "$newCB\nginx\default.conf",
                  "$newCB\workflows", "$newCB\patches", "$newCB\openviking", "$newCB\.env",
                  "$newCB\deer-flow-config.yaml", "$newQM\sandbox\skills", "$newQM\patch\pi-models.ts")
foreach ($m in $mountSources) {
    $e = Test-Path -LiteralPath $m
    if (-not $e) { $abort = $true }
    Info ("mount source {0,-34} {1}" -f (Split-Path -Leaf $m), $(if ($e) { 'present' } else { '*** MISSING ***' }))
}

# the big DB file must be present and non-trivial
$db = "$newCB\data\deer-flow\checkpoints.db"
if (Test-Path $db) {
    $mb = [math]::Round((Get-Item $db).Length/1MB, 1)
    Info "checkpoints.db: $mb MB"
    if ($mb -lt 100) { $abort = $true; Info '  !! suspiciously small for the 1.6 GB DB' }
} else { Info "checkpoints.db: NOT FOUND at $db" }

if ($abort) {
    A ''
    A 'ABORTING before start - copy is not complete. Stack stays DOWN.'
    A 'Rollback: start again from C:\pacgate-ai-pr\deploy\client-bundle.'
    [System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
    exit 1
}
Info 'copy verified'

# ---- 6. start from the NEW location ----------------------------------------
Step '6. Start the stack from the NEW location'
Push-Location $newCB
$r = & docker compose -f compose.bundle.yaml up -d 2>&1
Info "bundle up exit=$LASTEXITCODE"
foreach ($x in @($r | Select-Object -Last 12)) { Info ("  " + "$x") }
Pop-Location

Push-Location $newQM
$r = & docker compose -f compose.qm.yaml up -d 2>&1
Info "qm up exit=$LASTEXITCODE"
foreach ($x in @($r | Select-Object -Last 12)) { Info ("  " + "$x") }
Pop-Location

# ---- 7. verify -------------------------------------------------------------
Step '7. Verify the cutover'
Start-Sleep -Seconds 30
$ok = $true

$running = @(docker ps -q).Count
Info "containers running: $running  (expect 25)"
if ($running -lt 20) { $ok = $false; Info '  !! fewer than expected' }

# 7a. correct volume
$mnt = docker inspect pacgate-db --format '{{json .Mounts}}' 2>$null | ConvertFrom-Json
$vol = @($mnt | Where-Object { $_.Destination -eq '/var/lib/postgresql/data' } | Select-Object -First 1).Name
Info "pacgate-db volume: $vol"
if ($vol -ne 'pacgate-ai-bundle_pacgate-db-data') { $ok = $false; Info '  !! WRONG VOLUME' }

# 7b. no mount may still point at the old path
$oldRefs = New-Object System.Collections.Generic.List[string]
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) { if ($x.Source -like '*pacgate-ai-pr*') { $oldRefs.Add("$n : $($x.Source)") } }
}
Info "mounts still under the OLD path: $($oldRefs.Count)  (must be 0)"
if ($oldRefs.Count -gt 0) { $ok = $false; foreach ($x in $oldRefs) { Info "  !! $x" } }

# 7c. all mounts now resolve under the NEW path
$newRefs = New-Object System.Collections.Generic.List[string]
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) { if ($x.Source -like '*pacgate-law*') { $newRefs.Add("$n : $($x.Source)") } }
}
Info "mounts now under the NEW path: $($newRefs.Count)"

# 7d. DB answers and the row count is unchanged (baseline was 1)
$post = & docker exec pacgate-db psql -U pacgate -d pacgate -tAc "select count(*) from tenants;" 2>&1
Info "tenants AFTER cutover: $post  (was 1)"
if ("$post" -notmatch '^\s*1\s*$') { $ok = $false; Info '  !! expected 1 - data may not be the same database' }

# 7e. container health / restart loops
foreach ($c in @('pacgate-db','pacgate-api','deer-flow','deer-flow-frontend','pacgate-nginx','pacgate-mcp','openviking')) {
    $st = docker inspect $c --format '{{.State.Status}} restarts={{.RestartCount}}' 2>$null
    Info ("{0,-20} {1}" -f $c, $st)
    if ("$st" -match 'restarting|exited') { $ok = $false }
}

# 7f. http health
try {
    $h = Invoke-RestMethod -Uri 'http://localhost:8089/health' -TimeoutSec 20
    Info "pacgate-api /health: $h"
} catch { Info "pacgate-api /health: not reachable - $($_.Exception.Message)" }

A ''
if ($ok) { A 'CUTOVER OK - stack runs from pacgate-law\pacgate-ai, correct volume, data intact.' }
else     { A 'CUTOVER INCOMPLETE - see checks above. Rollback: start again from C:\pacgate-ai-pr.' }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"