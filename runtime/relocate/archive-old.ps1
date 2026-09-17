$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr'
$arch = 'C:\archive-pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\ARCHIVE-OLD-LOCATION.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'ARCHIVE C:\pacgate-ai-pr (Task 5)'
A ('=' * 78)
A ''
A 'Strategy: capture everything UNIQUE and IRREPLACEABLE first, verify it, and'
A 'only then mark the original retired. The directory is NOT deleted.'
A ''
A 'What is unique here:'
A '  - the 159-commit git history (the monorepo import was a SQUASH)'
A '  - 13 untracked scratch files'
A '  - rendered .env files (per-machine config with keys)'
A 'What is NOT archived (regenerable / live elsewhere):'
A '  - target/          4.5 GB Rust build output (regenerable)'
A '  - client-bundle/data 1.9 GB (LIVE in the monorepo, being written to)'

if (-not (Test-Path $arch)) { New-Item -ItemType Directory -Path $arch -Force | Out-Null }

# ============ 1. full git bundle (the irreplaceable part) ===================
A "`n=== 1. Full git bundle of the 159-commit history ==="
$bundle = Join-Path $arch 'pacgate-ai-pr-history.bundle'
$t0 = Get-Date
& git -C $old bundle create $bundle --all 2>&1 | ForEach-Object { A ("    " + $_) }
$code = $LASTEXITCODE
$secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
A ("  exit={0}  {1}s" -f $code, $secs)
if (Test-Path $bundle) {
    A ("  bundle size: {0} MB" -f [math]::Round((Get-Item $bundle).Length/1MB,1))
    # verify it is a valid, complete bundle
    $v = & git bundle verify $bundle 2>&1
    foreach ($x in @($v | Select-Object -First 12)) { A ("    " + $x) }
} else { A '  BUNDLE NOT CREATED' }

# ============ 2. untracked scratch + rendered config ========================
A "`n=== 2. Untracked scratch files + rendered config ==="
$tb = Join-Path $arch 'scratch.tar.gz'
Push-Location $old
# include untracked files and the rendered .env / extensions config
& tar -czf $tb --exclude='./.git' --exclude='./pacgate-ai/target' --exclude='*/target' `
      --exclude='./deploy/client-bundle/data' --exclude='*/node_modules' `
      ./probe_ckpt.py ./probe_ckpt2.py ./probe_repro.py ./probe_timing.py `
      ./.vscode ./tmp-api-err.ps1 ./tmp-drift-check.ps1 ./tmp-exec.json `
      ./tmp-ghcr-check.ps1 ./tmp-login.json ./tmp-logs.ps1 ./tmp-tenant.ps1 ./tmp-wf-repro.ps1 `
      ./deploy/client-bundle/.env ./deploy/qm-pacgate/.env 2>&1 |
    ForEach-Object { A ("    " + $_) }
Pop-Location
if (Test-Path $tb) { A ("  scratch archive: {0} MB" -f [math]::Round((Get-Item $tb).Length/1MB,2)) }
else { A '  (some scratch files may be absent; tar still produced output above)' }

# ============ 3. verify the archive can be restored =========================
A "`n=== 3. Restore test (clone from the bundle) ==="
$test = 'C:\temp\bundle-restore-test'
if (Test-Path $test) { Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $bundle) {
    & git clone -q $bundle $test 2>&1 | ForEach-Object { A ("    " + $_) }
    if (Test-Path $test) {
        $c = (& git -C $test rev-list --all --count 2>$null) -join ''
        A ("  commits restored from bundle: {0}  (expect 159)" -f $c)
        $f = @(Get-ChildItem $test -Recurse -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\\.git\\' }).Count
        A ("  files restored: {0}" -f $f)
        A ("  Cargo.toml present: {0}" -f (Test-Path (Join-Path $test 'pacgate-ai\Cargo.toml')))
        Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
    } else { A '  CLONE FAILED - the bundle is not restorable!' }
}

# ============ 4. final dependency check before retiring =====================
A "`n=== 4. Final check: does ANYTHING still depend on the old path? ==="
$deps = New-Object System.Collections.Generic.List[string]
foreach ($n in @(docker ps -a --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if ($j) { try { foreach ($x in ($j | ConvertFrom-Json)) { if ($x.Source -like '*pacgate-ai-pr*') { $deps.Add("$n mount: $($x.Source)") } } } catch {} }
    $cf = docker inspect $n --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>$null
    if ("$cf" -like '*pacgate-ai-pr*') { $deps.Add("$n compose: $cf") }
}
A ("  container dependencies on the old path: {0}   (0 = safe)" -f $deps.Count)
foreach ($d in $deps) { A ("    " + $d) }

# ============ 5. what we did NOT do =========================================
A "`n=== 5. Deliberately NOT done ==="
A '  - NOT deleted. The original remains at C:\pacgate-ai-pr.'
A '  - NOT renamed. Renaming would break any reference we did not find, and'
A '    buys nothing: the archive already captures the unique content.'
A '    (To retire it later: rename to C:\pacgate-ai-pr-RETIRED once you are'
A '     confident, then delete once you are certain.)'

A "`n=== 6. Archive contents ==="
Get-ChildItem $arch -Force | ForEach-Object {
    A ("  {0,-40} {1,10:N1} MB" -f $_.Name, ($_.Length/1MB))
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"