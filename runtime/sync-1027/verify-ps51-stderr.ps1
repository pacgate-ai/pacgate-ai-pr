# Prove the PS 5.1 native-stderr defect in upstream's new gate, in isolation.
#
# The gate does:  $out = $py | & docker exec -i deer-flow python 2>&1
# under $ErrorActionPreference = 'Stop'. The container's python emits a
# LangChainPendingDeprecationWarning on stderr, and PS 5.1 promotes a native
# command's stderr to a TERMINATING error - so the gate aborts before it can read
# the verdict it just produced. This repo already fixed the identical bug twice
# (test-memory-lane.ps1, d1ed509 and 86a9feb).
$ErrorActionPreference = 'Stop'

'=== A. the gate''s exact pattern, under Stop ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    $out = 'print("HELLO")' | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
    '  survived; out=' + ("$out".Trim())
}
catch {
    '  ABORTED: ' + $_.Exception.GetType().Name
    '  message: ' + ($_.Exception.Message -split "`n")[0]
}
finally { $ErrorActionPreference = $prevEap }

''
'=== B. same call with the preference scoped down (the known fix) ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out2 = 'print("HELLO")' | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $prevEap }
'  exit=' + $code
'  captured lines=' + (@($out2).Count)
@($out2) | ForEach-Object { '    ' + "$_".Trim() } | Select-Object -First 6

''
'=== C. does the container python actually write to stderr? ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $err = 'import sys; sys.stderr.write("STDERR_PROBE\n"); print("STDOUT_PROBE")' |
        & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
}
finally { $ErrorActionPreference = $prevEap }
@($err) | ForEach-Object { '    ' + "$_".Trim() }
