$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\BUNDLE-TRUTH.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUNDLE TRUTH - resolve the contradiction'
A ('=' * 78)
A ''
A 'My check said the OLD (--all) bundle DID contain refs/remotes/fork/main,'
A 'yet a clone from it was missing a commit. Both cannot be true. Determine'
A 'the actual content of each bundle.'

# Reproduce BOTH bundles cleanly and compare ref-for-ref.
$tmp = 'C:\temp\bundle-truth'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$bAll  = Join-Path $tmp 'all.bundle'
$bFull = Join-Path $tmp 'full.bundle'

& git -C $old bundle create $bAll  --all                     2>&1 | Out-Null
& git -C $old bundle create $bFull --branches --tags --remotes 2>&1 | Out-Null

A "`n=== 1. Ref lists side by side ==="
$rAll  = @(& git bundle list-heads $bAll  2>$null | ForEach-Object { ($_ -split '\s+')[1] } | Sort-Object)
$rFull = @(& git bundle list-heads $bFull 2>$null | ForEach-Object { ($_ -split '\s+')[1] } | Sort-Object)
A ("  --all     refs: {0}" -f $rAll.Count)
A ("  full      refs: {0}" -f $rFull.Count)

A "`n  --- refs in --all but NOT in full ---"
$d1 = @(Compare-Object $rAll $rFull | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })
if (-not $d1.Count) { A '    (none)' } else { foreach ($x in $d1) { A ("    " + $x) } }

A "`n  --- refs in full but NOT in --all ---"
$d2 = @(Compare-Object $rAll $rFull | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
if (-not $d2.Count) { A '    (none)' } else { foreach ($x in $d2) { A ("    " + $x) } }

A "`n  --- does each bundle carry refs/remotes/fork/main ? ---"
foreach ($p in @(@{n='--all'; b=$bAll}, @{n='full '; b=$bFull})) {
    $heads = @(& git bundle list-heads $p.b 2>$null)
    $has = @($heads | Where-Object { $_ -match 'refs/remotes/fork/main' }).Count
    A ("    {0} : {1}" -f $p.n, $(if ($has) { 'YES' } else { 'NO' }))
}

# ---- THE ACTUAL QUESTION: are all source commits present in each bundle? ---
A "`n=== 2. Commit-set completeness per bundle (the test that matters) ==="
$srcAll = @(& git -C $old rev-list --all 2>$null)

foreach ($p in @(@{n='--all'; b=$bAll}, @{n='full '; b=$bFull})) {
    $t = Join-Path $tmp "clone_$($p.n.Trim())"
    if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
    & git clone -q $p.b $t 2>&1 | Out-Null

    # compare against ALL commits reachable in the clone from ANY ref
    $cln = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($r in @(& git -C $t for-each-ref --format='%(refname)' 2>$null)) {
        foreach ($c in @(& git -C $t rev-list $r 2>$null)) { [void]$cln.Add($c) }
    }
    $srcSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($c in $srcAll) { [void]$srcSet.Add($c) }

    $missing = @($srcAll | Where-Object { -not $cln.Contains($_) })
    A ("`n  --- bundle {0} ---" -f $p.n)
    A ("    source commits : {0}" -f $srcAll.Count)
    A ("    clone  commits : {0}" -f $cln.Count)
    A ("    MISSING        : {0}" -f $missing.Count)
    foreach ($m in ($missing | Select-Object -First 5)) {
        $s = (& git -C $old log -1 --format='%h %s' $m 2>$null) -join ''
        $inRefs = @(& git -C $old for-each-ref --contains $m --format='%(refname)' 2>$null)
        A ("      ! {0}" -f $s)
        A ("        contained in: {0}" -f $(if ($inRefs) { ($inRefs -join ', ') } else { 'NO REF (dangling)' }))
    }
}

A "`n=== 3. What the shipped archive actually contains ==="
$shipped = 'C:\archive-pacgate-ai-pr\pacgate-ai-pr-history.bundle'
if (Test-Path $shipped) {
    $h = @(& git bundle list-heads $shipped 2>$null)
    A ("  shipped bundle refs: {0}" -f $h.Count)
    $has = @($h | Where-Object { $_ -match 'refs/remotes/' }).Count
    A ("  remote-tracking refs inside: {0}" -f $has)
    A ("  size: {0} MB" -f [math]::Round((Get-Item $shipped).Length/1MB,1))
    $mtime = (Get-Item $shipped).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    A ("  last written: {0}   (should be the --branches --tags --remotes run)" -f $mtime)
}

A "`n=== VERDICT ==="
A '  Both bundles were regenerated here so the comparison is apples-to-apples.'
A '  The decisive number is 2: MISSING per bundle.'
A '  If --all shows MISSING=1 and full shows MISSING=0, the fix is proven.'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"