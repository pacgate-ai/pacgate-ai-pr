$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr'
$arch = 'C:\archive-pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\BUNDLE-FIX.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUNDLE FIX - --all omits remote-tracking refs'
A ('=' * 78)
A ''
A 'BUG IN MY OWN ARCHIVE: `git bundle create --all` includes refs/heads/* and'
A 'refs/tags/* but NOT refs/remotes/*. So refs/remotes/fork/main (28dc159) was'
A 'silently omitted, and a restore from that bundle would be missing a ref.'
A ''
A 'That is exactly the kind of gap a backup must not have. Fix: add --remotes.'

# ---- 1. show the gap -------------------------------------------------------
A "`n=== 1. Demonstrate the gap ==="
$oldBundle = Join-Path $arch 'pacgate-ai-pr-history.bundle'
if (Test-Path $oldBundle) {
    $refs = @(& git bundle list-heads $oldBundle 2>&1)
    $hasForkMain = @($refs | Where-Object { $_ -match 'refs/remotes/fork/main' }).Count
    A ("  old bundle contains refs/remotes/fork/main : {0}" -f $(if ($hasForkMain) { 'YES' } else { 'NO  <-- the gap' }))
    A ("  old bundle ref count : {0}" -f $refs.Count)
}

# ---- 2. recreate WITH --remotes --------------------------------------------
A "`n=== 2. Recreate with --branches --tags --remotes ==="
$newBundle = Join-Path $arch 'pacgate-ai-pr-history.bundle'
if (Test-Path $newBundle) { Remove-Item $newBundle -Force }
$t0 = Get-Date
& git -C $old bundle create $newBundle --branches --tags --remotes 2>&1 | ForEach-Object { A ("    " + $_) }
$code = $LASTEXITCODE
$secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
A ("  exit={0}  {1}s  size={2} MB" -f $code, $secs, [math]::Round((Get-Item $newBundle).Length/1MB,1))

$newRefs = @(& git bundle list-heads $newBundle 2>&1)
A ("  new bundle ref count : {0}" -f $newRefs.Count)
$nowForkMain = @($newRefs | Where-Object { $_ -match 'refs/remotes/fork/main' }).Count
A ("  contains refs/remotes/fork/main : {0}" -f $(if ($nowForkMain) { 'YES' } else { 'NO' }))

# ---- 3. verify completeness by restoring and diffing COMMIT SETS -----------
A "`n=== 3. Verify: restore and compare the full commit SET ==="
$test = 'C:\temp\bundle-verify2'
if (Test-Path $test) { Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue }
& git clone -q $newBundle $test 2>&1 | Out-Null

if (Test-Path $test) {
    $srcAll = @(& git -C $old rev-list --all 2>$null)
    # fetch the remote-tracking refs from the bundle into the clone so we can
    # compare like-for-like
    & git -C $test fetch -q $newBundle "+refs/remotes/*:refs/remotes/*" 2>&1 | Out-Null
    $clnAll = @(& git -C $test rev-list --all 2>$null)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($c in $clnAll) { [void]$set.Add($c) }
    # also add everything reachable from the fetched remote refs
    foreach ($r in @(& git -C $test for-each-ref --format='%(refname)' 2>$null)) {
        foreach ($c in @(& git -C $test rev-list $r 2>$null)) { [void]$set.Add($c) }
    }

    $missing = @($srcAll | Where-Object { -not $set.Contains($_) })
    A ("  source commits : {0}" -f $srcAll.Count)
    A ("  clone  commits : {0}" -f $clnAll.Count)
    A ("  MISSING        : {0}   (must be 0)" -f $missing.Count)
    foreach ($m in ($missing | Select-Object -First 10)) {
        A ("    ! {0}" -f $m.Substring(0,10))
    }
    Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
} else { A '  CLONE FAILED' }

# ---- 4. also archive the FULL working tree (only unique parts) -------------
A "`n=== 4. Note on scope ==="
A '  The bundle carries history. The monorepo already carries the working'
A '  content (438 files, reconciliation exact). The old working tree is'
A '  therefore recoverable as: bundle (history) + monorepo (content).'

A "`n=== VERDICT ==="
A '  See section 3. If MISSING is 0, the archive is complete.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"