$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\MOUNT-AUDIT.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'MOUNT AUDIT -- exact bind mounts, and whether the new copy has the source'
A ('=' * 78)
A ''
A 'Previous count was wrong: `$j | ConvertFrom-Json` returns the array as a'
A 'SINGLE object in PowerShell 5.1 (not enumerated), so Where-Object treated'
A 'all 13 deer-flow mounts as one item. Enumerate properly below.'

$oldRoot = 'C:\pacgate-ai-pr'
$newRoot = Join-Path $repo 'pacgate-ai'

# Map an old absolute path to where it should live in the new copy.
function MapToNew([string]$p) {
    if ($p -like "$oldRoot\*") { return ($newRoot + $p.Substring($oldRoot.Length)) }
    return $null
}

$all = New-Object System.Collections.Generic.List[object]
foreach ($n in @(docker ps -a --format '{{.Names}}' | Sort-Object)) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) {
        if ($x.Type -ne 'bind') { continue }
        $all.Add([pscustomobject]@{
            Container = $n
            Source    = $x.Source
            Dest      = $x.Destination
            Mode      = $x.Mode
            UnderOld  = ($x.Source -like "$oldRoot*")
        })
    }
}

A ("`n=== Bind mounts found: {0} ===" -f $all.Count)
$underOld = @($all | Where-Object { $_.UnderOld })
A ("    referencing the OLD path: {0}" -f $underOld.Count)
A ("    other locations:          {0}" -f ($all.Count - $underOld.Count))

A "`n=== The OLD-path mounts, with new-copy status ==="
$missing = New-Object System.Collections.Generic.List[string]
foreach ($x in $underOld) {
    $np = MapToNew $x.Source
    $exists = if ($np) { Test-Path -LiteralPath $np } else { $false }
    if (-not $exists) { $missing.Add($x.Source) }
    A ("`n  [{0}]" -f $x.Container)
    A ("    old : {0}" -f $x.Source)
    A ("    new : {0}" -f $np)
    A ("    dest: {0}  ({1})" -f $x.Dest, $x.Mode)
    A ("    new copy present: {0}" -f $(if ($exists) { 'YES' } else { '*** MISSING ***' }))
}

A "`n=== Mounts pointing somewhere other than C:\pacgate-ai-pr ==="
foreach ($x in ($all | Where-Object { -not $_.UnderOld })) {
    A ("  [{0}] {1} -> {2}" -f $x.Container, $x.Source, $x.Dest)
}

A "`n=== GAP SUMMARY ==="
if ($missing.Count -eq 0) { A '  All bind-mount sources exist in the new copy.' }
else {
    A ("  {0} mount source(s) MISSING from the new copy:" -f $missing.Count)
    foreach ($m in $missing) { A ("    " + $m) }
    A ''
    A '  These must be copied during the cutover or the container will start'
    A '  with an empty/absent directory at the mount point.'
}

# Which of these live under qm-pacgate specifically?
A "`n=== qm-pacgate specifics ==="
$qm = @($all | Where-Object { $_.Source -like '*qm-pacgate*' })
A ("  qm-pacgate bind mounts: {0}" -f $qm.Count)
foreach ($x in $qm) { A ("    {0} -> {1}" -f $x.Source, $x.Dest) }

$qmo = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$qmn = Join-Path $newRoot 'deploy\qm-pacgate'
foreach ($sub in @('sandbox', 'patch', 'tasks', 'node_modules', '.env', 'qm.config.jsonc')) {
    $o = Join-Path $qmo $sub; $n = Join-Path $qmn $sub
    $so = if (Test-Path $o) { @(Get-ChildItem $o -Recurse -File -Force -ErrorAction SilentlyContinue).Count } else { 'absent' }
    $sn = if (Test-Path $n) { @(Get-ChildItem $n -Recurse -File -Force -ErrorAction SilentlyContinue).Count } else { 'ABSENT' }
    A ("  {0,-20} old={1,-8} new={2}" -f $sub, $so, $sn)
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"