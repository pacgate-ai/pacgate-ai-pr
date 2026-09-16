$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$mirror = 'C:\backup-pacgate-law-mirror.git'
$out  = Join-Path $repo 'runtime\relocate\LOCAL-MIRROR.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'LOCAL BARE MIRROR (immediate insurance while no remote exists)'
A ('=' * 78)
A ''
A 'The monorepo has no remote and a squashed history, so it is the only copy.'
A 'A bare mirror protects against accidental deletion or a bad git operation.'
A 'It does NOT protect against disk failure - that needs a real remote.'

# ---- 1. create the mirror --------------------------------------------------
A "`n=== 1. Create the bare mirror ==="
if (Test-Path $mirror) {
    A ("  {0} already exists - refreshing instead" -f $mirror)
    & git -C $mirror fetch --all --prune 2>&1 | ForEach-Object { A ("    " + $_) }
} else {
    $r = & git clone --bare $repo $mirror 2>&1
    foreach ($x in $r) { A ("    " + $x) }
}
A ("  exit: {0}" -f $LASTEXITCODE)

# ---- 2. verify it is a real, complete copy ---------------------------------
A "`n=== 2. Verify the mirror is complete ==="
$srcCount = (& git -C $repo rev-list --all --count 2>$null) -join ''
$mirCount = (& git -C $mirror rev-list --all --count 2>$null) -join ''
A ("  source commits : {0}" -f $srcCount)
A ("  mirror commits : {0}" -f $mirCount)
A ("  match          : {0}" -f ($srcCount -eq $mirCount))

$srcHead = (& git -C $repo rev-parse HEAD 2>$null) -join ''
$mirHead = (& git -C $mirror rev-parse HEAD 2>$null) -join ''
A ("  source HEAD    : {0}" -f $srcHead)
A ("  mirror HEAD    : {0}" -f $mirHead)
A ("  match          : {0}" -f ($srcHead -eq $mirHead))

# ---- 3. can it actually restore? -------------------------------------------
A "`n=== 3. Restore test (clone the mirror to a temp dir) ==="
$test = 'C:\temp\mirror-restore-test'
if (Test-Path $test) { Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue }
$r = & git clone $mirror $test 2>&1
foreach ($x in @($r | Select-Object -Last 3)) { A ("    " + $x) }
if (Test-Path $test) {
    $n = @(Get-ChildItem $test -Recurse -File -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.git\\' }).Count
    A ("  restored files (excl .git): {0}" -f $n)
    A ("  Cargo.toml present        : {0}" -f (Test-Path (Join-Path $test 'pacgate-ai\Cargo.toml')))
    A ("  compose.bundle.yaml       : {0}" -f (Test-Path (Join-Path $test 'pacgate-ai\deploy\client-bundle\compose.bundle.yaml')))
    Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
    A '  (test clone removed)'
}

# ---- 4. size ---------------------------------------------------------------
A "`n=== 4. Mirror size ==="
$mb = [math]::Round((Get-ChildItem $mirror -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object Length -Sum).Sum / 1MB, 1)
A ("  {0}  =  {1} MB" -f $mirror, $mb)

# ---- 5. how to refresh -----------------------------------------------------
A "`n=== 5. Refreshing the mirror after new commits ==="
A '  git -C C:\backup-pacgate-law-mirror.git fetch --all --prune'
A '  (or re-run this script)'

# ---- 6. what this does NOT cover -------------------------------------------
A "`n=== 6. What this does NOT protect against ==="
A '  - disk failure (same physical disk)'
A '  - theft / fire / ransomware'
A '  A real remote is still required. github.com IS reachable from here, but'
A '  gh CLI is not logged in and no token is stored, so a push needs auth.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"