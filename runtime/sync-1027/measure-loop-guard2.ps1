# The previous measurement was WRONG: `LoopDetectionMiddleware()` with no args
# uses class defaults (50/30/50, no overrides), which is not how the gateway
# builds it. Measure the CONFIGURED path instead - that is what actually runs.
$ErrorActionPreference = 'Stop'

$py = @'
import sys
sys.path.insert(0, "/app/backend/packages/harness")
sys.path.insert(0, "/app/backend")

# 1. What does the config file actually say?
from deerflow.config import get_app_config
cfg = get_app_config()
ld = getattr(cfg, "loop_detection", None)
print("CONFIG_PRESENT=%s" % (ld is not None))
if ld is not None:
    print("CONFIG_WARN=%s" % getattr(ld, "tool_freq_warn", None))
    print("CONFIG_HARD=%s" % getattr(ld, "tool_freq_hard_limit", None))
    ov = getattr(ld, "tool_freq_overrides", None) or {}
    print("CONFIG_OVERRIDES=%s" % {k: (v.warn, v.hard_limit) for k, v in ov.items()})

# 2. Build it the way the gateway does, from that config.
from deerflow.agents.middlewares.loop_detection_middleware import LoopDetectionMiddleware
if ld is not None:
    m = LoopDetectionMiddleware.from_config(ld)
    print("BUILT_WINDOW=%d" % m._tool_freq_window)
    print("BUILT_WARN=%d" % m.tool_freq_warn)
    print("BUILT_HARD=%d" % m.tool_freq_hard_limit)
    print("BUILT_BASH=%s" % (m._tool_freq_overrides.get("bash"),))
'@

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>$null }
finally { $ErrorActionPreference = $prevEap }

'=== configured path (what the gateway actually builds) ==='
@($out) | Where-Object { "$_" -match '=' } | ForEach-Object { '  ' + "$_".Trim() }
