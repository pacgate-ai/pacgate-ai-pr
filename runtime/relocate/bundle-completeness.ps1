$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr'
$bundle = 'C:\archive-pacgate-ai-pr\pacgate-ai-pr-history.bundle'
$out  = Join-Path $repo 'runtime\relocate\BUNDLE-COMPLETENESS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUNDLE COMPLETENESS - resolve the 158 vs 159 discrepancy'
A ('=' * 78)
A ''
A 'A backup that is missing a commit is not a backup. Determine whether a'
A 'commit was lost, or whether the two numbers merely count different ref sets.'

# ---- restore the bundle again for comparison -------------------------------
$test = 'C:\temp\bundle-cmp'
if (Test-Path $test) { Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue }
& git clone -q $bundle $test 2>&1 | Out-Null

# ---- compare commit SETS, not counts ---------------------------------------
A "`n=== 1. Counts ==="
$srcAll = @(& git -C $old rev-list --all 2>$null)
$clnAll = @(& git -C $test rev-list --all 2>$null)
A ("  source  rev-list --all : {0}" -f $srcAll.Count)
A ("  clone   rev-list --all : {0}" -f $clnAll.Count)

A "`n=== 2. Ref inventory (what each side actually has) ==="
$srcRefs = @(& git -C $old for-each-ref --format='%(refname)' 2>$null) | Sort-Object
$clnRefs = @(& git -C $test for-each-ref --format='%(refname)' 2>$null) | Sort-Object
A ("  source refs: {0}    clone refs: {1}" -f $srcRefs.Count, $clnRefs.Count)
A ''
A '  --- refs in SOURCE but not in CLONE ---'
$onlySrc = @(Compare-Object $srcRefs $clnRefs | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })
if (-not $onlySrc.Count) { A '    (none)' } else { foreach ($x in $onlySrc) { A ("    " + $x) } }
A '  --- refs in CLONE but not in SOURCE (expected: clone-local) ---'
$onlyCln = @(Compare-Object $srcRefs $clnRefs | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
if (-not $onlyCln.Count) { A '    (none)' } else { foreach ($x in $onlyCln) { A ("    " + $x) } }

# ---- the decisive test: is every source commit present in the clone? -------
A "`n=== 3. Decisive test: is EVERY source commit reachable from the bundle? ==="
$srcSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($c in $srcAll) { [void]$srcSet.Add($c) }
$clnSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($c in $clnAll) { [void]$clnSet.Add($c) }

# reachability within the clone (all commits, regardless of ref)
$clnReach = @(& git -C $test rev-list --all --reflog 2>/dev/null)
foreach ($c in $clnReach) { [void]$clnSet.Add($c) }

$missing = @($srcAll | Where-Object { -not $clnSet.Contains($_) })
A ("  source commits: {0}" -f $srcSet.Count)
A ("  clone  commits: {0}  (incl. reflog)" -f $clnSet.Count)
A ("  MISSING from the bundle: {0}   (must be 0)" -f $missing.Count)
foreach ($m in ($missing | Select-Object -First 10)) {
    $s = (& git -C $old log -1 --format='%h %ad %s' --date=short $m 2>$null) -join ''
    A ("    ! {0}  {1}" -f $m.Substring(0,10), $s)
}

# ---- is the missing one reachable from any ref? ----------------------------
if ($missing.Count -gt 0) {
    A "`n=== 4. Which ref contains the 'missing' commit? ==="
    foreach ($m in $missing) {
        $branches = @(& git -C $old branch -a --contains $m 2>$null)
        A ("  {0} is contained in: {1}" -f $m.Substring(0,10), $(if ($branches) { ($branches -join ', ') } else { 'NO REF (dangling)' }))
        $isDangling = -not $branches
        A ("    dangling (not a ref tip, unreachable from any branch): {0}" -f $isDangling)
    }
}

A "`n=== VERDICT ==="
if ($missing.Count -eq 0) {
    A '  COMPLETE - every source commit is in the bundle. The 158 vs 159 count'
    A '  difference was only in how many commits each side honours via --all.'
} else {
    A ("  {0} commit(s) not carried. Investigate whether they are reachable" -f $missing.Count)
    A '  from a ref the bundle omitted, or genuinely dangling (unreferenced).'
}

Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"