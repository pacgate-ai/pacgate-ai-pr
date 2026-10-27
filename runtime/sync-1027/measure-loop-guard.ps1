# Task 7: measure the loop-guard effect on the live stack.
$ErrorActionPreference = 'Stop'

$py = @'
import sys
sys.path.insert(0, "/app/backend/packages/harness")
from deerflow.agents.middlewares.loop_detection_middleware import LoopDetectionMiddleware
m = LoopDetectionMiddleware()
print("WINDOW=%d" % m._tool_freq_window)
print("GLOBAL_WARN=%d" % m.tool_freq_warn)
print("GLOBAL_HARD=%d" % m.tool_freq_hard_limit)
print("BASH_OVERRIDE=%s" % (m._tool_freq_overrides.get("bash"),))
print("HAS_COUNTER=%s" % hasattr(m, "_tool_name_counter"))
print("HAS_HISTORY=%s" % hasattr(m, "_tool_name_history"))
'@

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>$null
}
finally { $ErrorActionPreference = $prevEap }

'=== live middleware parameters ==='
@($out) | Where-Object { "$_" -match '=' } | ForEach-Object { '  ' + "$_".Trim() }

''
'=== force-stops since the recreate ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1) -join "`n"
$ErrorActionPreference = $prevEap
'  forcing_stop_count = ' + ([regex]::Matches($gw, 'forcing stop')).Count
'  freq_warning_count = ' + ([regex]::Matches($gw, 'Tool frequency warning')).Count
'  repetitive_warning = ' + ([regex]::Matches($gw, 'Repetitive tool calls detected')).Count
