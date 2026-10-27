# Determine EXACTLY which version of loop_detection_middleware.py is live.
# `grep -c -e a -e b` counts lines matching ANY pattern, so the earlier
# "windowed_markers=6" was ambiguous - it may be Layer 1's own deque usage.
# Read the actual structures instead.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$f = '/app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py'

'=== file size / line count ==='
& docker exec deer-flow sh -c "wc -l $f" 2>&1

''
'=== class + method structure ==='
& docker exec deer-flow grep -n -E '^(class |    def |def )' $f 2>&1

''
'=== counter data structures (the discriminator) ==='
& docker exec deer-flow grep -n -E 'deque|Counter|_tool_call_counts|tool_freq_overrides|tool_freq_hard_limit|window' $f 2>&1

$ErrorActionPreference = $prevEap
