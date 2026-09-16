$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\BUILD-PATH-FIX-VERIFY.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUILD PATH FIX VERIFICATION'
A ('=' * 74)
A ''
A 'The flatten moved Dockerfile/Cargo.toml up one level. Two build entry points'
A 'still referenced the old nested layout. Verify the fixes resolve.'

# ---- 1. build-images.ps1 ---------------------------------------------------
A "`n=== 1. deploy/build-images.ps1 ==="
$bi = Join-Path $pa 'deploy\build-images.ps1'
$txt = [System.IO.File]::ReadAllText($bi)
$root = $pa   # $Root = parent of deploy = the platform root

# extract the docker build lines and resolve their paths
$lines = @($txt -split "`r?`n" | Where-Object { $_ -match 'docker build' })
foreach ($ln in $lines) {
    A ("  " + $ln.Trim())
    # pull out Join-Path $Root "..." occurrences
    foreach ($m in [regex]::Matches($ln, 'Join-Path \$Root "([^"]+)"')) {
        $rel = $m.Groups[1].Value
        $full = Join-Path $root ($rel -replace '/', '\')
        A ("      -> {0,-46} {1}" -f $rel, $(if (Test-Path $full) { 'EXISTS' } else { '*** MISSING ***' }))
    }
}

# ---- 2. CI workflow --------------------------------------------------------
A "`n=== 2. .github/workflows/build-ghcr.yml ==="
$wf = Join-Path $pa '.github\workflows\build-ghcr.yml'
$wtxt = [System.IO.File]::ReadAllText($wf)
$ctx = @([regex]::Matches($wtxt, '(?m)^\s*context:\s*(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
$fil = @([regex]::Matches($wtxt, '(?m)^\s*file:\s*(.+)$')    | ForEach-Object { $_.Groups[1].Value.Trim() })
for ($i = 0; $i -lt $ctx.Count; $i++) {
    $c = $ctx[$i]
    $f = if ($i -lt $fil.Count) { $fil[$i] } else { '(none)' }
    $cFull = if ($c -eq '.') { $pa } else { Join-Path $pa ($c -replace '/', '\') }
    $fFull = Join-Path $pa ($f -replace '/', '\')
    A ("  context: {0,-34} {1}" -f $c, $(if (Test-Path $cFull) { 'EXISTS' } else { '*** MISSING ***' }))
    A ("  file   : {0,-34} {1}" -f $f, $(if (Test-Path $fFull) { 'EXISTS' } else { '*** MISSING ***' }))
}

# ---- 3. Dockerfile COPY paths vs context -----------------------------------
A "`n=== 3. Dockerfile COPY paths (relative to context '.') ==="
$df = Join-Path $pa 'Dockerfile'
foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($df), '(?m)^COPY\s+(.+)$')) {
    $src = ($m.Groups[1].Value -split '\s+')[0]
    if ($src -eq '.') { A ("  COPY . .            -> whole context (always valid)"); continue }
    $full = Join-Path $pa ($src -replace '/', '\')
    A ("  COPY {0,-16} {1}" -f $src, $(if (Test-Path $full) { 'EXISTS' } else { '*** MISSING ***' }))
}

# ---- 4. remaining functional references ------------------------------------
A "`n=== 4. Remaining functional references to the old nested layout ==="
$func = @(Get-ChildItem $pa -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\|\\dist\\' -and
                         $_.Extension -match '^\.(ps1|psm1|py|sh|ya?ml|json|toml|cmd|bat)$' } |
          Select-String -Pattern 'pacgate-ai/Dockerfile|pacgate-ai/Cargo|pacgate-ai/crates|pacgate-ai/wasm-crates|pacgate-ai/migrations|pacgate-ai/workflows' -ErrorAction SilentlyContinue)
# exclude the explanatory comments we just added
$real = @($func | Where-Object { $_.Line -notmatch '^\s*#' -and $_.Line -notmatch 'FLATTENED|old standalone repo|nested' })
A ("  total matches: {0}   excluding our own comments: {1}" -f $func.Count, $real.Count)
foreach ($r in $real) { A ("    " + $r.Path.Substring($pa.Length) + " L" + $r.LineNumber + " : " + $r.Line.Trim()) }

A "`n=== VERDICT ==="
if ($real.Count -eq 0) { A '  All functional build paths resolve. Build entry points are correct.' }
else { A ("  {0} functional reference(s) still need review." -f $real.Count) }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"