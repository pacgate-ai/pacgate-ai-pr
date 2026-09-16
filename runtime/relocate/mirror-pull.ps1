$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\MIRROR-PULL.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'PULL RUST BASE IMAGES VIA THE DAOCLOUD MIRROR'
A ('=' * 78)
A ''
A 'docker.io is unreachable from this machine, but the daocloud mirror is'
A 'already in use (python:3.12-slim and node:22-alpine are cached from it).'
A 'Pull the Rust base images through the same mirror so the build graph can be'
A 'validated offline.'

$mirror = 'docker.m.daocloud.io/library'
foreach ($img in @('rust:1.94-bookworm', 'debian:bookworm-slim')) {
    A ("`n=== {0} ===" -f $img)
    $t0 = Get-Date
    $r = & docker pull "$mirror/$img" 2>&1
    $code = $LASTEXITCODE
    $secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
    A ("  pull exit={0} ({1}s)" -f $code, $secs)
    foreach ($x in @($r | Select-Object -Last 4)) { A ("    " + "$x") }
    if ($code -eq 0) {
        & docker tag "$mirror/$img" $img 2>&1 | Out-Null
        A ("  tagged as {0}" -f $img)
    }
}

A "`n=== Now re-run the Rust build check ==="
Push-Location (Join-Path $repo 'pacgate-ai')
$r = & docker build --check -f Dockerfile . 2>&1
$code = $LASTEXITCODE
Pop-Location
A ("  exit={0}" -f $code)
foreach ($x in @($r | Select-Object -Last 20)) { A ("    " + "$x") }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"