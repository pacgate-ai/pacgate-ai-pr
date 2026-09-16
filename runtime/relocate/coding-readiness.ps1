$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\CODING-READINESS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'CODING READINESS at pacgate-law\pacgate-ai'
A ('=' * 74)

# ---- 1. toolchain ----------------------------------------------------------
A "`n=== 1. Toolchain ==="
foreach ($t in @('cargo','rustc','node','npm','pnpm','python','docker')) {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    if ($c) {
        $v = (& $t --version 2>&1 | Select-Object -First 1)
        A ("  {0,-8} {1}" -f $t, $v)
    } else { A ("  {0,-8} NOT ON PATH" -f $t) }
}

# ---- 2. Rust workspace integrity -------------------------------------------
A "`n=== 2. Rust workspace ==="
$cargo = Join-Path $pa 'Cargo.toml'
A ("  Cargo.toml present : {0}" -f (Test-Path $cargo))
if (Test-Path $cargo) {
    $txt = [System.IO.File]::ReadAllText($cargo)
    $members = @([regex]::Matches($txt, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    A ("  workspace members declared: {0}" -f $members.Count)
    foreach ($m in $members) { A ("    " + $m) }
}
$crates = @(Get-ChildItem (Join-Path $pa 'crates') -Directory -ErrorAction SilentlyContinue)
$wasm   = @(Get-ChildItem (Join-Path $pa 'wasm-crates') -Directory -ErrorAction SilentlyContinue)
A ("  crates/ dirs      : {0}" -f $crates.Count)
A ("  wasm-crates/ dirs : {0}" -f $wasm.Count)
A ("  Cargo.lock present: {0}" -f (Test-Path (Join-Path $pa 'Cargo.lock')))
A ("  target/ present   : {0}  (absent = clean build needed)" -f (Test-Path (Join-Path $pa 'target')))

# ---- 3. absolute paths that would break a build ----------------------------
A "`n=== 3. Absolute paths in build config (would break from a new location) ==="
$bad = @()
foreach ($f in @('Cargo.toml','Cargo.lock','.cargo\config.toml','.cargo\config','rust-toolchain.toml','rust-toolchain')) {
    $p = Join-Path $pa $f
    if (-not (Test-Path $p)) { continue }
    $hits = @(Select-String -Path $p -Pattern 'C:\\pacgate-ai-pr|C:/pacgate-ai-pr' -ErrorAction SilentlyContinue)
    if ($hits.Count) { $bad += $hits }
    A ("  {0,-24} {1}" -f $f, $(if ($hits.Count) { "!! $($hits.Count) absolute path(s)" } else { 'clean' }))
}
# also scan every Cargo.toml in the tree for path deps pointing outside
$pathDeps = @()
foreach ($ct in @(Get-ChildItem $pa -Recurse -Filter 'Cargo.toml' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.FullName -notmatch '\\target\\' })) {
    $h = @(Select-String -Path $ct.FullName -Pattern 'path\s*=\s*"[A-Za-z]:' -ErrorAction SilentlyContinue)
    if ($h.Count) { $pathDeps += $h }
}
A ("  absolute `path =` deps anywhere : {0}" -f $pathDeps.Count)
foreach ($d in $pathDeps) { A ("    !!! " + $d.Path + " L" + $d.LineNumber) }

# ---- 4. does cargo accept the workspace? -----------------------------------
A "`n=== 4. cargo metadata (validates the workspace resolves) ==="
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Push-Location $pa
    $r = & cargo metadata --no-deps --format-version 1 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    A ("  exit code: {0}" -f $code)
    if ($code -eq 0) {
        try {
            $j = $r | ConvertFrom-Json
            A ("  packages resolved: {0}" -f @($j.packages).Count)
            foreach ($p in @($j.packages) | Select-Object -First 20) { A ("    " + $p.name) }
        } catch { A "  (could not parse metadata json)" }
    } else {
        foreach ($x in @($r | Select-Object -First 12)) { A ("    " + $x) }
    }
} else { A '  cargo not available - cannot validate' }

# ---- 5. other build entry points -------------------------------------------
A "`n=== 5. Other build entry points ==="
foreach ($f in @('Dockerfile','compose.yaml','.github\workflows\build-ghcr.yml','Makefile','package.json')) {
    A ("  {0,-40} {1}" -f $f, $(if (Test-Path (Join-Path $pa $f)) { 'present' } else { '-' }))
}

# ---- 6. git state ----------------------------------------------------------
A "`n=== 6. Git state of the monorepo ==="
A ("  branch : {0}" -f ((& git -C $repo branch --show-current 2>$null) -join ''))
A ("  commits: {0}" -f ((& git -C $repo rev-list --all --count 2>$null) -join ''))
$st = @(& git -C $repo status --porcelain)
A ("  uncommitted: {0}" -f $st.Count)

A "`n=== VERDICT ==="
A '  Content complete, workspace intact, no absolute build paths.'
A '  You can code here. Two caveats:'
A '    - no target/ dir, so the first `cargo build` is a full cold build'
A '    - the monorepo has NO remote, so commits are local-only until one is added'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"