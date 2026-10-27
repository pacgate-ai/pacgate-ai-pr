# The first probe survived because plain `print()` writes nothing to stderr.
# The gate's script imports deerflow, which emits a LangChainPendingDeprecation
# Warning on stderr. Reproduce THAT, which is the real trigger.
$ErrorActionPreference = 'Stop'

$py = @'
import sys
sys.path.insert(0, "/app/backend/packages/harness")
import deerflow.agents.middlewares.loop_detection_middleware as m
print("IMPORT_OK")
'@

'=== A. gate pattern (2>&1 merge) under Stop, WITH the langgraph import ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
    '  survived; lines=' + (@($out).Count)
    @($out) | ForEach-Object { '    ' + "$_".Trim() } | Select-Object -First 4
}
catch {
    '  ABORTED: ' + $_.Exception.GetType().Name
    '  first line: ' + (("$($_.Exception.Message)" -split "`n")[0])
}
finally { $ErrorActionPreference = $prevEap }

''
'=== B. same, preference scoped to Continue (the fix) ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out2 = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $prevEap }
'  exit=' + $code + '  lines=' + (@($out2).Count)
@($out2) | ForEach-Object { '    ' + "$_".Trim() } | Select-Object -First 6
