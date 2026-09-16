param([switch]$Execute)

$ErrorActionPreference = 'Stop'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$oldCB = 'C:\pacgate-ai-pr\deploy\client-bundle'
$newCB = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$oldQM = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$newQM = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'
$out   = Join-Path $repo 'runtime\relocate\CUTOVER-RESULT.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }
function Step([string]$m) { Write-Host "`n>>> $m" -ForegroundColor Cyan; $L.Add(""); $L.Add(">>> $m") }
function Info([string]$m) { Write-Host "    $m"; $L.Add("    $m") }
function Dry([string]$m) { Write-Host "    [DRY-RUN] $m" -ForegroundColor Yellow; $L.Add("    [DRY-RUN] $m") }

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' }
Write-Host "RELOCATION TASK 3 - CUTOVER  (mode: $mode)" -ForegroundColor Green
A "RELOCATION TASK 3 - CUTOVER (mode: $mode)"
A ('=' * 62)
A ''
A 'This is the DOWNTIME step. It stops the stack, copies the runtime state'
A 'that git does not carry, and restarts from the new location.'
A ''
A 'Rollback: the old location is untouched. If anything fails, start the stack'
A 'again from C:\pacgate-ai-pr\deploy\client-bundle with the same command.'

# ============================ 1. preflight ==================================
Step '1. Preflight'
$fatal = New-Object System.Collections.Generic.List[string]

# new location must be complete
foreach ($p in @('Cargo.toml', 'deploy\client-bundle\compose.bundle.yaml',
                 'deploy\qm-pacgate\compose.qm.yaml', 'deploy\client-bundle\deer-flow-config.yaml')) {
    if (-not (Test-Path (Join-Path $repo "pacgate-ai\$p"))) { $fatal.Add("missing at new location: $p") }
}
# old location must still be intact (it is the rollback)
foreach ($p in @('deploy\client-bundle\compose.bundle.yaml', 'deploy\client-bundle\data')) {
    if (-not (Test-Path (Join-Path 'C:\pacgate-ai-pr' $p))) { $fatal.Add("rollback source missing: $p") }
}
# both compose files must agree on the project name
$bn = (Select-String -Path (Join-Path $newCB 'compose.bundle.yaml') -Pattern '^name:' | Select-Object -First 1).Line
$pn = (Select-String -Path (Join-Path $newCB 'compose.prod.yaml')   -Pattern '^name:' | Select-Object -First 1).Line
if ($bn -ne $pn) { $fatal.Add("compose project names differ: bundle='$bn' prod='$pn'") }
Info "compose names agree: $($bn.Trim())"

# the authoritative volume must exist
$vols = @(docker volume ls --format '{{.Name}}')
if ($vols -notcontains 'pacgate-ai-bundle_pacgate-db-data') { $fatal.Add('authoritative volume pacgate-ai-bundle_pacgate-db-data not found') }
Info "authoritative volume present: pacgate-ai-bundle_pacgate-db-data"

# free space for the ~1.9 GB copy
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

# ============================ 2. stop =======================================
Step '2. Stop the stack FROM THE OLD LOCATION (files still exist there)'
if ($Execute) {
    Push-Location $oldCB
    Info 'docker compose -f compose.bundle.yaml down   (NO -v: -v would DELETE the databases)'
    & docker compose -f compose.bundle.yaml down 2>&1 | ForEach-Object { Info $_ }
    Pop-Location

    if (Test-Path (Join-Path $oldQM 'compose.qm.yaml')) {
        Push-Location $oldQM
        Info 'docker compose -f compose.qm.yaml down'
        & docker compose -f compose.qm.yaml down 2>&1 | ForEach-Object { Info $_ }
        Pop-Location
    }
    $left = @(docker ps -q).Count
    Info "containers still running: $left"
} else {
    Dry "cd $oldCB ; docker compose -f compose.bundle.yaml down"
    Dry "cd $oldQM ; docker compose -f compose.qm.yaml down"
}

# ============================ 3. copy runtime state =========================
Step '3. Copy the runtime state git does not carry (~1.9 GB)'
# Done AFTER the stop so the 1.6 GB checkpoints.db is not mid-write.
$copies = @(
    @{ s = "$oldCB\data";                          d = "$newCB\data" },
    @{ s = "$oldCB\openviking";                    d = "$newCB\openviking" },
    @{ s = "$oldCB\.env";                          d = "$newCB\.env" },
    @{ s = "$oldCB\deer-flow-extensions-config.json"; d = "$newCB\deer-flow-extensions-config.json" },
    @{ s = "$oldQM\node_modules";                  d = "$newQM\node_modules" },
    @{ s = "$oldQM\.env";                          d = "$newQM\.env" }
)
foreach ($c in $copies) {
    if (-not (Test-Path -LiteralPath $c.s)) { Info "skip (absent at source): $($c.s)"; continue }
    if ($Execute) {
        if (Test-Path -LiteralPath $c.s -PathType Container) {
            & robocopy $c.s $c.d /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        } else {
            $dd = Split-Path -Parent $c.d
            if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
            Copy-Item -LiteralPath $c.s -Destination $c.d -Force
        }
        $rc = $LASTEXITCODE
        $n = if (Test-Path $c.d -PathType Container) { @(Get-ChildItem $c.d -Recurse -File -Force -ErrorAction SilentlyContinue).Count } else { 1 }
        Info ("copied {0,-46} rc={1} files={2}" -f (Split-Path -Leaf $c.s), $rc, $n)
        if ($rc -ge 8) { throw "robocopy failed for $($c.s) (exit $rc)" }
    } else {
        Dry "copy $($c.s) -> $($c.d)"
    }
}

# ============================ 4. verify the copy ============================
Step '4. Verify the copy is complete'
if ($Execute) {
    $pairs = @(
        @{ s = "$oldCB\data"; d = "$newCB\data" },
        @{ s = "$oldQM\node_modules"; d = "$newQM\node_modules" }
    )
    $bad = 0
    foreach ($p in $pairs) {
        if (-not (Test-Path $p.s)) { continue }
        $so = @(Get-ChildItem $p.s -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $dn = @(Get-ChildItem $p.d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $ok = ($dn -ge $so)
        if (-not $ok) { $bad++ }
        Info ("{0,-24} source={1,-7} dest={2,-7} {3}" -f (Split-Path -Leaf $p.s), $so, $dn, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
    }
    if ($bad -gt 0) { throw 'copy verification failed - do NOT start the stack' }
} else { Dry 'compare file counts old vs new' }

# ============================ 5. start ======================================
Step '5. Start the stack FROM THE NEW LOCATION'
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

# ============================ 6. verify =====================================
Step '6. Verify the cutover'
if ($Execute) {
    $ok = $true

    $running = @(docker ps -q).Count
    Info "containers running: $running"
    if ($running -lt 20) { $ok = $false }

    # THE critical check: attached to the authoritative volume, not the orphan
    $mount = (docker inspect pacgate-db --format '{{range .Mounts}}{{.Name}}{{end}}' 2>$null)
    Info "pacgate-db volume: $mount"
    if ($mount -ne 'pacgate-ai-bundle_pacgate-db-data') { $ok = $false; Info '  !! WRONG VOLUME - the project name did not resolve as expected' }

    # mounts must now point at the NEW location
    $srcs = @(docker inspect pacgate-db --format '{{range .Mounts}}{{.Source}}{{"`n"}}{{end}}' 2>$null)
    $stillOld = @($srcs | Where-Object { $_ -like '*pacgate-ai-pr*' })
    Info "mounts still under the OLD path: $($stillOld.Count)  (must be 0)"
    if ($stillOld.Count -gt 0) { $ok = $false; foreach ($s in $stillOld) { Info "  !! $s" } }

    # behavioural check: the DB must actually answer
    $q = & docker exec pacgate-db psql -U pacgate -d pacgate -tAc "select count(*) from tenants;" 2>&1
    Info "tenants in DB: $q"
    if ("$q" -notmatch '^\s*\d+\s*$') { $ok = $false; Info '  !! DB did not answer - data may not be attached' }

    A ''
    if ($ok) { A 'CUTOVER OK - stack running from the new location on the correct volume.' }
    else     { A 'CUTOVER INCOMPLETE - see the checks above. Rollback: start from C:\pacgate-ai-pr.' }
} else {
    Dry 'check container count, pacgate-db volume, mount sources, and a DB query'
    A ''
    A 'DRY-RUN complete. Re-run with -Execute during the maintenance window.'
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"
