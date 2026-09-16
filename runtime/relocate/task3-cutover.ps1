param([switch]$Execute)

$ErrorActionPreference = 'Stop'
$repo  = 'c:\Users\pacga\github-pr\pacgate-law'
$oldCB = 'C:\pacgate-ai-pr\deploy\client-bundle'
$newCB = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$oldQM = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$newQM = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'
$srcRoot = 'C:\pacgate-ai-pr'
$newRoot = Join-Path $repo 'pacgate-ai'
$out   = Join-Path $repo 'runtime\relocate\CUTOVER-RESULT.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }
function Step([string]$m) { Write-Host "`n>>> $m" -ForegroundColor Cyan; $L.Add(""); $L.Add(">>> $m") }
function Info([string]$m) { Write-Host "    $m"; $L.Add("    $m") }
function Dry([string]$m) { Write-Host "    [DRY-RUN] $m" -ForegroundColor Yellow; $L.Add("    [DRY-RUN] $m") }

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' }
Write-Host "RELOCATION TASK 3 - CUTOVER  (mode: $mode)" -ForegroundColor Green
A "RELOCATION TASK 3 - CUTOVER (mode: $mode)"
A ('=' * 70)
A ''
A 'Minimal-downtime strategy:'
A '  2. PRE-COPY the 1.9 GB of runtime state while the stack still runs'
A '     (robocopy is incremental, so this needs no window)'
A '  3. STOP the stack'
A '  4. re-run robocopy -> only files changed since step 2 transfer. This is'
A '     what makes the copy CONSISTENT: the 1.6 GB checkpoints.db is re-copied'
A '     after its writer stopped, so it cannot be a torn read.'
A '  5. verify  6. START from the new location  7. verify live'
A ''
A 'Downtime is therefore seconds (the incremental pass), not 1.9 GB.'
A ''
A 'Rollback: the old location is untouched. To revert, start the stack again'
A 'from C:\pacgate-ai-pr\deploy\client-bundle with the same command.'

# ============================== 0. inventory ================================
Step '0. Runtime state to transfer (gitignored; exists only at the old path)'
$items = @(
    @{ s = "$oldCB\data";                             d = "$newCB\data";                             kind = 'dir' },
    @{ s = "$oldCB\openviking";                       d = "$newCB\openviking";                       kind = 'dir' },
    @{ s = "$oldCB\.env";                             d = "$newCB\.env";                             kind = 'file' },
    @{ s = "$oldCB\deer-flow-extensions-config.json"; d = "$newCB\deer-flow-extensions-config.json"; kind = 'file' },
    @{ s = "$oldQM\node_modules";                     d = "$newQM\node_modules";                     kind = 'dir' },
    @{ s = "$oldQM\.env";                             d = "$newQM\.env";                             kind = 'file' }
)
foreach ($i in $items) {
    $ex = Test-Path -LiteralPath $i.s
    A ("  {0,-42} {1}" -f (Split-Path -Leaf $i.s), $(if ($ex) { 'present' } else { 'ABSENT (skip)' }))
}

# ============================== 1. preflight ================================
Step '1. Preflight'
$fatal = New-Object System.Collections.Generic.List[string]
foreach ($p in @('Cargo.toml', 'deploy\client-bundle\compose.bundle.yaml', 'deploy\qm-pacgate\compose.qm.yaml')) {
    if (-not (Test-Path (Join-Path $newRoot $p))) { $fatal.Add("missing at new location: $p") }
}
foreach ($p in @('deploy\client-bundle\compose.bundle.yaml', 'deploy\client-bundle\data')) {
    if (-not (Test-Path (Join-Path $srcRoot $p))) { $fatal.Add("rollback source missing: $p") }
}
$bn = (Select-String -Path (Join-Path $newCB 'compose.bundle.yaml') -Pattern '^name:' | Select-Object -First 1).Line
$pn = (Select-String -Path (Join-Path $newCB 'compose.prod.yaml')   -Pattern '^name:' | Select-Object -First 1).Line
if ($bn -ne $pn) { $fatal.Add("compose project names differ: '$bn' vs '$pn'") }
Info "compose names agree: $($bn.Trim())"

$vols = @(docker volume ls --format '{{.Name}}')
if ($vols -notcontains 'pacgate-ai-bundle_pacgate-db-data') { $fatal.Add('authoritative volume missing') }
else { Info 'authoritative volume present: pacgate-ai-bundle_pacgate-db-data' }

if (-not (Test-Path (Join-Path $newCB 'nginx\default.conf'))) { $fatal.Add('nginx/default.conf missing at new location') }
else { Info 'nginx/default.conf present (nginx would fail to start without it)' }

$pre = & docker exec pacgate-db psql -U pacgate -d pacgate -tAc "select count(*) from tenants;" 2>&1
Info "tenants BEFORE cutover: $pre"

$free = [math]::Round((Get-PSDrive C).Free/1GB, 1)
Info "free space: $free GB"
if ($free -lt 5) { $fatal.Add("insufficient free space: $free GB") }

if ($fatal.Count) {
    Write-Host "`nABORTED:" -ForegroundColor Red
    foreach ($f in $fatal) { Write-Host "  ! $f" -ForegroundColor Red; A "  ! $f" }
    [System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
    exit 1
}
Info 'preflight OK'

# ============================== 2. PRE-COPY (no downtime) ===================
Step '2. PRE-COPY while the stack still runs (bulk transfer, no downtime)'
foreach ($i in $items) {
    if (-not (Test-Path -LiteralPath $i.s)) { continue }
    if ($Execute) {
        $t0 = Get-Date
        if ($i.kind -eq 'dir') {
            & robocopy $i.s $i.d /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        } else {
            $dd = Split-Path -Parent $i.d
            if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
            Copy-Item -LiteralPath $i.s -Destination $i.d -Force
        }
        $rc = $LASTEXITCODE
        $n  = if (Test-Path $i.d -PathType Container) { @(Get-ChildItem $i.d -Recurse -File -Force -ErrorAction SilentlyContinue).Count } else { 1 }
        Info ("{0,-34} rc={1,-3} files={2,-6} {3:N0}s" -f (Split-Path -Leaf $i.s), $rc, $n, ((Get-Date)-$t0).TotalSeconds)
        if ($i.kind -eq 'dir' -and $rc -ge 8) { throw "robocopy failed for $($i.s) (exit $rc)" }
    } else {
        Dry "pre-copy $($i.s) -> $($i.d)"
    }
}

# ============================== 3. stop =====================================
Step '3. STOP the stack (from the OLD location - files still exist there)'
if ($Execute) {
    Push-Location $oldCB
    Info 'docker compose -f compose.bundle.yaml down   (NO -v: -v would DELETE the volumes)'
    & docker compose -f compose.bundle.yaml down 2>&1 | ForEach-Object { Info $_ }
    Pop-Location
    if (Test-Path (Join-Path $oldQM 'compose.qm.yaml')) {
        Push-Location $oldQM
        Info 'docker compose -f compose.qm.yaml down'
        & docker compose -f compose.qm.yaml down 2>&1 | ForEach-Object { Info $_ }
        Pop-Location
    }
    Info "containers still running: $(@(docker ps -q).Count)"
} else {
    Dry "cd $oldCB ; docker compose -f compose.bundle.yaml down"
    Dry "cd $oldQM ; docker compose -f compose.qm.yaml down"
}

# ============================== 4. incremental re-copy ======================
Step '4. Re-copy incrementally (this is what makes the copy CONSISTENT)'
foreach ($i in $items) {
    if (-not (Test-Path -LiteralPath $i.s)) { continue }
    if ($Execute) {
        $t0 = Get-Date
        if ($i.kind -eq 'dir') {
            & robocopy $i.s $i.d /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        } else {
            Copy-Item -LiteralPath $i.s -Destination $i.d -Force
        }
        $rc = $LASTEXITCODE
        Info ("{0,-34} rc={1,-3} {2:N1}s" -f (Split-Path -Leaf $i.s), $rc, ((Get-Date)-$t0).TotalSeconds)
        if ($i.kind -eq 'dir' -and $rc -ge 8) { throw "robocopy failed for $($i.s) (exit $rc)" }
    } else { Dry "incremental re-copy $($i.s)" }
}

# ============================== 5. verify the copy ==========================
Step '5. Verify the copy is complete before starting anything'
if ($Execute) {
    $bad = 0
    foreach ($p in @(@{s="$oldCB\data";d="$newCB\data"}, @{s="$oldQM\node_modules";d="$newQM\node_modules"})) {
        if (-not (Test-Path $p.s)) { continue }
        $so = @(Get-ChildItem $p.s -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $dn = @(Get-ChildItem $p.d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $ok = ($dn -ge $so)
        if (-not $ok) { $bad++ }
        Info ("{0,-20} source={1,-7} dest={2,-7} {3}" -f (Split-Path -Leaf $p.s), $so, $dn, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
    }
    # every known bind-mount source must exist at the new location
    foreach ($m in @("$newCB\data", "$newCB\deer-flow-extensions-config.json", "$newCB\nginx\default.conf",
                     "$newCB\workflows", "$newCB\patches", "$newCB\openviking", "$newCB\.env",
                     "$newCB\deer-flow-config.yaml")) {
        $e = Test-Path -LiteralPath $m
        if (-not $e) { $bad++ }
        Info ("mount source {0,-34} {1}" -f (Split-Path -Leaf $m), $(if ($e) { 'present' } else { '*** MISSING ***' }))
    }
    if ($bad -gt 0) { throw 'copy verification failed - do NOT start the stack' }
    Info 'copy verified'
} else { Dry 'compare counts + confirm every bind-mount source exists' }

# ============================== 6. start ====================================
Step '6. START the stack from the NEW location'
if ($Execute) {
    Push-Location $newCB
    Info 'docker compose -f compose.bundle.yaml up -d'
    & docker compose -f compose.bundle.yaml up -d 2>&1 | ForEach-Object { Info $_ }
    Pop-Location
    if (Test-Path (Join-Path $newQM 'compose.qm.yaml')) {
        Push-Location $newQM
        Info 'docker compose -f compose.qm.yaml up -d'
        & docker compose -f compose.qm.yaml up -d 2>&1 | ForEach-Object { Info $_ }
        Pop-Location
    }
} else {
    Dry "cd $newCB ; docker compose -f compose.bundle.yaml up -d"
    Dry "cd $newQM ; docker compose -f compose.qm.yaml up -d"
}

# ============================== 7. verify ===================================
Step '7. Verify the cutover'
if ($Execute) {
    Start-Sleep -Seconds 25
    $ok = $true

    $running = @(docker ps -q).Count
    Info "containers running: $running"
    if ($running -lt 20) { $ok = $false; Info '  !! fewer containers than expected' }

    # 7a. the correct volume
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
        foreach ($x in $m) { if ($x.Source -like '*pacgate-ai-pr*') { $oldRefs.Add("$n : $($x.Source) -> $($x.Destination)") } }
    }
    Info "mounts still under the OLD path: $($oldRefs.Count)  (must be 0)"
    if ($oldRefs.Count -gt 0) { $ok = $false; foreach ($r in $oldRefs) { Info "  !! $r" } }

    # 7c. the DB must answer AND the row count must be unchanged
    $post = & docker exec pacgate-db psql -U pacgate -d pacgate -tAc "select count(*) from tenants;" 2>&1
    Info "tenants AFTER cutover: $post  (was: $pre)"
    if ("$post" -notmatch '^\s*\d+\s*$') { $ok = $false; Info '  !! DB did not answer' }
    elseif ("$pre" -match '^\s*\d+\s*$' -and "$post".Trim() -ne "$pre".Trim()) {
        $ok = $false; Info '  !! row count CHANGED - this may not be the same database'
    }

    # 7d. a couple of containers must not be restart-looping
    foreach ($c in @('pacgate-db','pacgate-api','deer-flow','pacgate-nginx')) {
        $st = docker inspect $c --format '{{.State.Status}} restarts={{.RestartCount}}' 2>$null
        Info ("{0,-16} {1}" -f $c, $st)
        if ($st -match 'restarting') { $ok = $false }
    }

    # 7e. http health
    try {
        $h = Invoke-RestMethod -Uri 'http://localhost:8089/health' -TimeoutSec 15
        Info "pacgate-api /health: $h"
    } catch { Info "pacgate-api /health: not reachable yet - $($_.Exception.Message)" }

    A ''
    if ($ok) { A 'CUTOVER OK - stack runs from the new location, correct volume, data intact.' }
    else     { A 'CUTOVER INCOMPLETE - see checks above. Rollback: start again from C:\pacgate-ai-pr.' }
} else {
    Dry 'check container count, volume name, old-path mounts, DB row count, health'
    A ''
    A 'DRY-RUN complete. Re-run with -Execute to perform the cutover.'
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"