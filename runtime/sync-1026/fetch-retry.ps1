# Retry the downloads that failed, then verify EVERY file against the API's
# reported byte size. A file whose size disagrees is a truncated transfer, not a
# success - downloading is the one step where a silent partial is most likely.
$ErrorActionPreference = 'Stop'

$base = 'https://raw.githubusercontent.com/JZKK720/pacgate-ai-pr/86a9feb'
$apiBase = 'https://api.github.com/repos/JZKK720/pacgate-ai-pr/contents'
$out = Join-Path $env:TEMP '86a9feb'

$files = @(
    'deploy/client-bundle/compose.bundle.yaml'
    'deploy/client-bundle/compose.prod.yaml'
    'deploy/client-bundle/patches/deer-flow-memory-prompt.py'
    'plans/031-aipc-latency-root-cause-and-fix.md'
    'plans/README.md'
    'scripts/run-all-checks.ps1'
    'scripts/test-memory-lane.ps1'
    'scripts/test-memory-prompt-stability.ps1'
)

foreach ($f in $files) {
    $dest = Join-Path $out ($f -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    # Up to 4 attempts: the TLS path to raw.githubusercontent.com drops
    # intermittently from this host (observed 000 after ~21 s).
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $code = (curl.exe -sS -w '%{http_code}' --max-time 90 "$base/$f" -o $dest) -join ''
        $sz = if (Test-Path $dest) { (Get-Item $dest).Length } else { -1 }
        if ($code -eq '200' -and $sz -gt 0) { break }
        Start-Sleep -Seconds 2
    }
    'download  http={0,-4} bytes={1,8}  {2}' -f $code, $sz, $f
}

'--- verification against API ---'
$bad = 0
foreach ($f in $files) {
    $dest = Join-Path $out ($f -replace '/', '\')
    $meta = (curl.exe -sS --max-time 60 "$apiBase/$f`?ref=86a9feb") | ConvertFrom-Json
    $expect = [int]$meta.size
    $actual = (Get-Item $dest).Length
    $ok = ($actual -eq $expect)
    if (-not $ok) { $bad++ }
    '{0,-6} api={1,8} local={2,8}  {3}' -f $(if ($ok) { 'OK' } else { 'BAD' }), $expect, $actual, $f
}
"size_mismatches=$bad"
