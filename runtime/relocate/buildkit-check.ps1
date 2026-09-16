$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\BUILDKIT-CHECK.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUILDKIT VALIDATION (docker build --check)'
A ('=' * 78)
A ''
A '`--check` validates the build graph WITHOUT executing it: it resolves the'
A 'base images, verifies COPY sources exist in the context, and reports lint'
A 'findings. Fast (seconds), no 30-minute Rust compile.'
A ''
A 'NOTE: --check still needs to resolve FROM images, so it requires network'
A '      access to the registries. A failure to pull is NOT a build defect.'

$builds = @(
    @{ n = 'pacgate-api (Rust)';        cwd = $pa;                          f = 'Dockerfile';                              ctx = '.' },
    @{ n = 'pacgate-mcp (Python)';      cwd = (Join-Path $pa 'deploy\pacgate-mcp'); f = 'Dockerfile';                       ctx = '.' },
    @{ n = 'deer-flow-pacgate';         cwd = $pa;                          f = 'deploy/deer-flow-pacgate/Dockerfile';      ctx = '.' },
    @{ n = 'deer-flow-frontend';        cwd = $pa;                          f = 'deploy/deer-flow-frontend-pacgate/Dockerfile'; ctx = '.' }
)

foreach ($b in $builds) {
    A ("`n=== {0} ===" -f $b.n)
    A ("  cwd    : {0}" -f $b.cwd)
    A ("  file   : {0}" -f $b.f)
    # `docker build -f` resolves the Dockerfile path against the CWD, NOT the
    # context. Running from the wrong directory gives a misleading
    # "open Dockerfile: no such file or directory". So cd into the context.
    Push-Location $b.cwd
    $t0 = Get-Date
    $r = & docker build --check -f $b.f $b.ctx 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    $secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
    A ("  exit={0}  ({1}s)" -f $code, $secs)
    foreach ($x in @($r | Select-Object -First 25)) { A ("    " + "$x") }
}

A "`n=== VERDICT ==="
A '  See per-build exit codes above. exit=0 means the build graph is valid.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"