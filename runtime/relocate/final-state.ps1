$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\FINAL-STATE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'FINAL STATE AFTER CUTOVER'
A ('=' * 70)

A "`n=== 1. The new path ==="
A "  $repo\pacgate-ai\"
A ''
A "  runtime / compose root:"
A "  $repo\pacgate-ai\deploy\client-bundle\"

A "`n=== 2. Containers ==="
A ("  running: {0}" -f @(docker ps -q).Count)
$byProj = @{}
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $prj = (docker inspect $n --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>$null)
    if (-not $prj) { $prj = '(unmanaged)' }
    if (-not $byProj.ContainsKey($prj)) { $byProj[$prj] = 0 }
    $byProj[$prj]++
}
foreach ($k in ($byProj.Keys | Sort-Object)) { A ("    {0,-22} {1}" -f $k, $byProj[$k]) }

A "`n=== 3. Where each compose project now lives ==="
$files = @{}
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $prj = (docker inspect $n --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>$null)
    $cf  = (docker inspect $n --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>$null)
    if ($prj -and -not $files.ContainsKey($prj)) { $files[$prj] = $cf }
}
foreach ($k in ($files.Keys | Sort-Object)) {
    $path = $files[$k]
    $tag = if ($path -like '*pacgate-law*') { 'NEW' } elseif ($path -like '*pacgate-ai-pr*') { 'OLD' } else { 'ext' }
    A ("    {0,-5} {1,-20} {2}" -f $tag, $k, $path)
}

A "`n=== 4. Dependencies on the OLD location ==="
$oldRefs = New-Object System.Collections.Generic.List[string]
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) { if ($x.Source -like '*pacgate-ai-pr*') { $oldRefs.Add("$n : $($x.Source)") } }
}
A ("  container mounts under C:\pacgate-ai-pr : {0}   (0 = safe to retire)" -f $oldRefs.Count)
foreach ($r in $oldRefs) { A ("    " + $r) }

$newRefs = 0
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) { if ($x.Source -like '*pacgate-law*') { $newRefs++ } }
}
A ("  container mounts under pacgate-law        : {0}" -f $newRefs)

A "`n=== 5. Data integrity ==="
foreach ($x in @(@{l='tenants';q='select count(*) from tenants;'},
                 @{l='users';q='select count(*) from users;'},
                 @{l='db size';q='select pg_size_pretty(pg_database_size(''pacgate''));'})) {
    $r = (& docker exec pacgate-db psql -U pacgate -d pacgate -tAc $x.q 2>&1) -join ''
    A ("  {0,-10} {1}" -f $x.l, $r.Trim())
}
$db = Join-Path $repo 'pacgate-ai\deploy\client-bundle\data\deer-flow\checkpoints.db'
if (Test-Path $db) { A ("  checkpoints.db  {0} MB  (at the NEW path)" -f [math]::Round((Get-Item $db).Length/1MB,1)) }

A "`n=== 6. Old location still intact (rollback) ==="
A ("  exists : {0}" -f (Test-Path 'C:\pacgate-ai-pr'))
A ("  HEAD   : {0}" -f ((& git -C 'C:\pacgate-ai-pr' rev-parse --short HEAD 2>$null) -join ''))
A ("  tracked: {0}" -f (@(& git -C 'C:\pacgate-ai-pr' ls-files).Count))

A "`n=== 7. Monorepo ==="
& git -C $repo log --oneline | Select-Object -First 6 | ForEach-Object { A ("  " + $_) }
A ("  tracked files: {0}" -f (@(& git -C $repo ls-files).Count))

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"