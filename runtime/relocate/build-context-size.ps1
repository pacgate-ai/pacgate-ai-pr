$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\BUILD-CONTEXT-SIZE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BUILD CONTEXT SIZE (the missing .dockerignore problem)'
A ('=' * 78)
A ''
A 'The Rust Dockerfile does `COPY . .` with context = the platform root.'
A 'There is NO .dockerignore anywhere, so the ENTIRE platform tree is sent to'
A 'the Docker daemon on every build. Measure what that actually is.'

$total = 0
$rows = @()
foreach ($d in @(Get-ChildItem $pa -Directory -Force -ErrorAction SilentlyContinue)) {
    $f = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
    $total += $mb
    $rows += [pscustomobject]@{ Name = $d.Name; Files = $f.Count; MB = $mb }
}
$rows = $rows | Sort-Object MB -Descending
A "`n=== Top-level directories in the build context ==="
foreach ($r in $rows) {
    $flag = if ($r.MB -gt 100) { '  <-- huge' } else { '' }
    A ("  {0,-28} {1,8} files {2,10} MB{3}" -f $r.Name, $r.Files, $r.MB, $flag)
}
A ("`n  TOTAL context: {0} MB" -f [math]::Round($total,1))

A "`n=== What SHOULD be excluded (candidates for .dockerignore) ==="
$cands = @(
    @{ p = 'deploy\client-bundle\data';  why = 'client runtime data (1.9 GB) - never needed to compile Rust' },
    @{ p = 'deploy\client-bundle\openviking'; why = 'runtime state' },
    @{ p = 'deploy\deer-flow-src';       why = 'cloned upstream source (if present)' },
    @{ p = 'target';                     why = 'Rust build output (if present)' },
    @{ p = 'deploy\qm-pacgate\node_modules'; why = 'installed deps' },
    @{ p = 'graphify-out';               why = 'generated knowledge graph' }
)
$saved = 0
foreach ($c in $cands) {
    $p = Join-Path $pa $c.p
    if (-not (Test-Path $p)) { A ("  {0,-40} (absent)" -f $c.p); continue }
    $f = @(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
    $saved += $mb
    A ("  {0,-40} {1,8} MB   {2}" -f $c.p, $mb, $c.why)
}
A ("`n  excludable: {0} MB of {1} MB  ({2}% of the context)" -f `
    [math]::Round($saved,1), [math]::Round($total,1), [math]::Round(100*$saved/$total,1))

A "`n=== Impact ==="
A '  Not a build FAILURE - the build would still work. But every `docker build`'
A '  would tar and transfer the whole context to the daemon first. On a 1.9 GB'
A '  context that is minutes of pure overhead per build, and it grows as client'
A '  data accumulates.'
A ''
A '  Fix: add a .dockerignore at the platform root excluding the runtime dirs.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"