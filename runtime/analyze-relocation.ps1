$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocation-analysis.txt'

$lines = New-Object System.Collections.Generic.List[string]
$SRC = 'C:\pacgate-ai-pr'
$DST = 'c:\Users\pacga\github-pr\pacgate-law\pacgate-ai'

$lines.Add('RELOCATION ANALYSIS: C:\pacgate-ai-pr  ->  pacgate-law\pacgate-ai')
$lines.Add('=' * 70)
$lines.Add('')

# ---------- 1. Same volume? (determines whether this is a fast move or a copy) ----------
$lines.Add('=== 1. Same volume? (fast rename vs full copy) ===')
$srcRoot = [System.IO.Path]::GetPathRoot($SRC)
$dstRoot = [System.IO.Path]::GetPathRoot($DST)
$lines.Add("  source root: $srcRoot")
$lines.Add("  target root: $dstRoot")
$lines.Add("  same volume: $($srcRoot -eq $dstRoot)")
$lines.Add('')

# ---------- 2. Top-level collisions ----------
$lines.Add('=== 2. Top-level name collisions (SOURCE vs TARGET) ===')
$srcItems = @(Get-ChildItem -LiteralPath $SRC -Force | Where-Object { $_.Name -ne '.git' } | Select-Object -ExpandProperty Name)
$dstItems = @(Get-ChildItem -LiteralPath $DST -Force | Where-Object { $_.Name -ne '.git' } | Select-Object -ExpandProperty Name)
$lines.Add("  source top-level ($($srcItems.Count)):")
foreach ($s in $srcItems) { $lines.Add("      $s") }
$lines.Add("  target top-level ($($dstItems.Count)):")
foreach ($d in $dstItems) { $lines.Add("      $d") }
$collide = @($srcItems | Where-Object { $dstItems -contains $_ })
$lines.Add('')
$lines.Add("  COLLIDING names: $($collide.Count)")
foreach ($c in $collide) {
    $sp = Join-Path $SRC $c
    $dp = Join-Path $DST $c
    $sf = @(Get-ChildItem -LiteralPath $sp -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $df = @(Get-ChildItem -LiteralPath $dp -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $lines.Add("      $c")
    $lines.Add("          source: $sf file(s)")
    $lines.Add("          target: $df file(s)")
}
$lines.Add('')

# ---------- 3. The nesting question ----------
$lines.Add('=== 3. Nesting: does SOURCE contain its own "pacgate-ai" dir? ===')
$srcInner = Join-Path $SRC 'pacgate-ai'
$lines.Add("  $SRC\pacgate-ai exists: $(Test-Path -LiteralPath $srcInner)")
if (Test-Path -LiteralPath $srcInner) {
    $inner = @(Get-ChildItem -LiteralPath $srcInner -Force | Select-Object -ExpandProperty Name)
    foreach ($i in $inner) { $lines.Add("      $i") }
}
$lines.Add('')
$lines.Add('  => Resulting path if contents are merged into the target:')
$lines.Add('       pacgate-ai\pacgate-ai\...        (Rust workspace)')
$lines.Add('  => The target tree is ALSO the old submodule, so:')
$lines.Add('       pacgate-ai\assets\...            (submodule assets)')
$lines.Add('')

# ---------- 4. Asset duplication ----------
$lines.Add('=== 4. Are the assets duplicated between source and target? ===')
$vendored = Join-Path $SRC 'pacgate-ai\pacgate-ai-assets\pacgate-ai'
$subAssets = Join-Path $DST 'assets'
foreach ($pair in @(@{N='vendored (source)'; P=$vendored}, @{N='submodule assets (target)'; P=$subAssets})) {
    if (Test-Path -LiteralPath $pair.P) {
        $f = @(Get-ChildItem -LiteralPath $pair.P -Recurse -File -Force -ErrorAction SilentlyContinue)
        $mb = [math]::Round((($f | Measure-Object Length -Sum).Sum)/1MB,1)
        $lines.Add(('  {0,-28} {1,5} files  {2,8} MB' -f $pair.N, $f.Count, $mb))
    } else { $lines.Add(('  {0,-28} ABSENT' -f $pair.N)) }
}
$lines.Add('')
foreach ($probe in @('SOUL_Sylvie_v1.0.md','OPERATOR.md','render.py')) {
    $a = @(Get-ChildItem -LiteralPath $vendored -Recurse -File -Force -Filter $probe -ErrorAction SilentlyContinue).Count
    $b = @(Get-ChildItem -LiteralPath $subAssets -Recurse -File -Force -Filter $probe -ErrorAction SilentlyContinue).Count
    $lines.Add(('  {0,-26} vendored={1}  submodule={2}' -f $probe, $a, $b))
}
$lines.Add('')

# ---------- 5. Size to move ----------
$lines.Add('=== 5. Size to move ===')
$all = @(Get-ChildItem -LiteralPath $SRC -Recurse -File -Force -ErrorAction SilentlyContinue)
$totalMb = [math]::Round((($all | Measure-Object Length -Sum).Sum)/1MB,1)
$lines.Add("  total: $($all.Count) files, $totalMb MB")
$lines.Add('')

# ---------- 6. Submodule state ----------
$lines.Add('=== 6. Submodule state (must be resolved before merging) ===')
$gitmodules = 'c:\Users\pacga\github-pr\pacgate-law\.gitmodules'
if (Test-Path -LiteralPath $gitmodules) {
    foreach ($l in [System.IO.File]::ReadAllLines($gitmodules)) { $lines.Add("  .gitmodules: $l") }
}
$lines.Add('')
$lines.Add('  target is a gitlink (mode 160000) -> it is a SUBMODULE, not plain files.')
$lines.Add('  Merging real files into it requires removing the gitlink first.')

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
