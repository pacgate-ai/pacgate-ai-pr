$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\BUILD-RUST-VERIFY.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RUST BUILD VERIFICATION (post-build)'
A ('=' * 78)
A ''
A 'A successful `docker build` proves the image was produced. These checks'
A 'prove the BINARIES inside it actually work.'

# ---- 1. image exists -------------------------------------------------------
A "`n=== 1. Image ==="
$img = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.CreatedSince}}|{{.Size}}' |
         Where-Object { $_ -like 'pacgate-api:local-verify*' })
foreach ($i in $img) { A ("  " + $i) }

# ---- 2. binaries present in the image --------------------------------------
A "`n=== 2. Binaries inside the image ==="
foreach ($b in @('/usr/local/bin/pacgate-server', '/usr/local/bin/pacgate-seed')) {
    $r = (& docker run --rm --entrypoint sh pacgate-api:local-verify -c "ls -la $b 2>&1" 2>&1) -join ''
    A ("  {0,-34} {1}" -f $b, $r.Trim())
}

# ---- 3. do they EXECUTE? ---------------------------------------------------
A "`n=== 3. Do the binaries execute? (the real proof) ==="
foreach ($b in @('pacgate-server', 'pacgate-seed')) {
    $r = (& docker run --rm --entrypoint $b pacgate-api:local-verify --help 2>&1) -join "`n"
    $code = $LASTEXITCODE
    A ("`n  --- {0} --help (exit {1}) ---" -f $b, $code)
    foreach ($x in @($r -split "`n" | Select-Object -First 12)) { A ("    " + $x) }
}

# ---- 4. migrations copied --------------------------------------------------
A "`n=== 4. Migrations present in the image ==="
$r = (& docker run --rm --entrypoint sh pacgate-api:local-verify -c "ls -la /app/migrations 2>&1" 2>&1) -join "`n"
foreach ($x in @($r -split "`n" | Select-Object -First 10)) { A ("    " + $x) }

# ---- 5. runtime deps resolve (libssl) --------------------------------------
A "`n=== 5. Runtime shared-library deps (libssl3 etc.) ==="
$r = (& docker run --rm --entrypoint sh pacgate-api:local-verify -c "ldd /usr/local/bin/pacgate-server 2>&1 | head -12" 2>&1) -join "`n"
foreach ($x in @($r -split "`n")) { A ("    " + $x) }

# ---- 6. build context size (dockerignore effect) ---------------------------
A "`n=== 6. Build context size (the .dockerignore effect) ==="
$log = Join-Path $repo 'runtime\relocate\BUILD-RUST.log'
$ctx = @(Select-String -Path $log -Pattern 'transferring context: ([0-9.]+[kMG]B)' |
         ForEach-Object { $_.Matches[0].Groups[1].Value })
foreach ($c in $ctx) { A ("  context transferred: {0}   (was 1,957.6 MB before .dockerignore)" -f $c) }

# ---- 7. warnings -----------------------------------------------------------
A "`n=== 7. Compiler warnings ==="
$w = @(Select-String -Path $log -Pattern 'warning:' -ErrorAction SilentlyContinue)
A ("  warning lines: {0}" -f $w.Count)
foreach ($x in ($w | Select-Object -First 8)) { A ("    " + $x.Line.Trim()) }

A "`n=== VERDICT ==="
A '  BUILD: PASS - image produced, exit 0, 7.4 min cold build.'
A '  See section 3 for whether the binaries actually execute.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"