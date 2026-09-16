$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\STAGE-PREVIEW.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'STAGE PREVIEW -- what would `git add -A` actually stage?'
A ('=' * 62)
A ''
A 'Concern: deer-flow/ is an EMBEDDED repo (122,116 files, 1,728 MB).'
A '         If git tried to stage its contents the repo would blow up.'
A '         Git normally records an embedded repo as a single gitlink.'

# Ask git what it WOULD add, without adding.
$dry = @(& git -C $repo add -A --dry-run 2>&1)

A "`n=== Total stageable paths: $($dry.Count) ==="

# Bucket by top-level directory
$buckets = @{}
foreach ($line in $dry) {
    $p = ($line -replace '^add\s+', '').Trim("'", '"')
    $top = ($p -split '/')[0]
    if (-not $top) { $top = '(root)' }
    if (-not $buckets.ContainsKey($top)) { $buckets[$top] = 0 }
    $buckets[$top]++
}
A "`n=== By top-level entry ==="
foreach ($k in ($buckets.Keys | Sort-Object)) {
    A ("  {0,-24} {1,8}" -f $k, $buckets[$k])
}

A "`n=== Any deer-flow CONTENT staged? (must be none) ==="
$df = @($dry | Where-Object { $_ -match 'deer-flow/' })
A ("  matches: {0}" -f $df.Count)
foreach ($d in ($df | Select-Object -First 10)) { A ("    " + $d) }

A "`n=== Embedded-repo gitlinks git would create ==="
$gl = @($dry | Where-Object { $_ -match "^\s*warning:|embedded" })
if ($gl.Count -eq 0) { A '  (none reported)' } else { foreach ($g in $gl) { A ("    " + $g) } }

A "`n=== Sanity: would anything huge be staged? ==="
# Real directory sizes for the top-level entries that appear stageable
foreach ($k in ($buckets.Keys | Sort-Object)) {
    $full = Join-Path $repo $k
    if ((Test-Path $full) -and (Test-Path $full -PathType Container)) {
        $f = @(Get-ChildItem $full -Recurse -File -Force -ErrorAction SilentlyContinue)
        $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
        A ("  {0,-24} {1,8} files  {2,10} MB" -f $k, $f.Count, $mb)
    }
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
