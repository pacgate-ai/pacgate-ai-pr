# Confirm the discriminator: is Layer 2's per-tool counter MONOTONIC (old) or
# WINDOWED (new)? And confirm the config gap that would make the patch inert.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$f = '/app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py'

'=== LIVE: Layer 2 counter mutation sites ==='
& docker exec deer-flow grep -n -E '_tool_freq|tool_freq' $f 2>&1

''
'=== LIVE: does it use a deque for the per-tool counter? ==='
& docker exec deer-flow grep -n -E 'deque|Counter\(' $f 2>&1

''
'=== NEW patch: same sites ==='
$new = Join-Path $env:TEMP 'new-loop.py'
if (Test-Path $new) {
    Select-String -Path $new -Pattern '_tool_freq|deque|Counter\(' | Select-Object -First 25 |
        ForEach-Object { '  {0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
}

$ErrorActionPreference = $prevEap
