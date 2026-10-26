# Download the 8 files touched by upstream 86a9feb.
# git transport cannot reach github.com from this host (TLS reset); curl can.
# Read-only with respect to the repo: writes only under $env:TEMP\86a9feb.
$ErrorActionPreference = 'Stop'

$base = 'https://raw.githubusercontent.com/JZKK720/pacgate-ai-pr/86a9feb'
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

New-Item -ItemType Directory -Force -Path $out | Out-Null

$failed = 0
foreach ($f in $files) {
    $dest = Join-Path $out ($f -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    $code = (curl.exe -sS -w '%{http_code}' --max-time 60 "$base/$f" -o $dest) -join ''
    $sz = if (Test-Path $dest) { (Get-Item $dest).Length } else { -1 }
    '{0,-4} {1,8}  {2}' -f $code, $sz, $f
    if ($code -ne '200' -or $sz -le 0) { $failed++ }
}

"failed=$failed"
