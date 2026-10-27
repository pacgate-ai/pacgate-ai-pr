# Is the loop-guard bug real on THIS machine? Upstream cites thread 6cc8dfae with
# "[FORCED STOP] Tool bash called 50 times" (92 calls / 71 bash / 55 distinct).
# Look for that evidence in our own logs before accepting the fix.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1) -join "`n"
$ErrorActionPreference = $prevEap

'=== FORCED STOP occurrences ==='
$fs = [regex]::Matches($gw, '(?m)^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)[^\n]*FORCED STOP[^\n]*')
"count=$($fs.Count)"
$fs | Select-Object -First 10 | ForEach-Object { '  ' + $_.Value.Substring(0, [Math]::Min(200, $_.Value.Length)) }

''
'=== loop-detection related lines (any) ==='
$ld = [regex]::Matches($gw, '(?m)^[^\n]*(loop_detection|LoopDetection|loop detection|Tool .* called \d+ times)[^\n]*')
"count=$($ld.Count)"
$ld | Select-Object -First 12 | ForEach-Object { '  ' + $_.Value.Trim().Substring(0, [Math]::Min(190, $_.Value.Trim().Length)) }

''
'=== thread 6cc8dfae present? ==='
"mentions=" + ([regex]::Matches($gw, '6cc8dfae')).Count

''
'=== is the middleware file currently the OLD (monotonic) version? ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$f = '/app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py'
$exists = & docker exec deer-flow sh -c "test -f $f && echo yes || echo no" 2>&1
'  file_exists = ' + ("$exists".Trim())
$markers = & docker exec deer-flow grep -c -e 'deque' -e 'Counter' -e 'tool_freq_overrides' $f 2>&1
'  windowed_markers(deque/Counter/overrides) = ' + ("$markers".Trim())
$mono = & docker exec deer-flow grep -c -e 'reset()' -e '_tool_call_counts' $f 2>&1
'  monotonic_markers(reset/_tool_call_counts) = ' + ("$mono".Trim())
$ErrorActionPreference = $prevEap
