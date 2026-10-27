# Red-check the new gate BEFORE adopting it: run upstream's
# test-loop-detection-window.ps1 against our CURRENT (unpatched) tree. It must
# FAIL, otherwise it is a blind gate and adopting it proves nothing.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\pacgate-ai')
$git = 'C:\Program Files\Git\cmd\git.exe'

$gatePath = '.\scripts\test-loop-detection-window.ps1'
$patchPath = '.\deploy\client-bundle\patches\deer-flow-loop-detection.py'

'=== preconditions ==='
'  gate already present? ' + (Test-Path $gatePath)
'  patch already present? ' + (Test-Path $patchPath)

# Materialise the gate from upstream WITHOUT committing it, so we can run it.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $git show 'upstream/main:scripts/test-loop-detection-window.ps1' 2>$null |
    Out-File -FilePath $gatePath -Encoding utf8
$ErrorActionPreference = $prevEap

'  gate materialised: ' + (Test-Path $gatePath)
''
'=== run against UNPATCHED tree (expect FAIL) ==='
# The gate shells out to docker, whose stderr (a langgraph deprecation warning)
# is promoted to a TERMINATING error under $ErrorActionPreference='Stop'. Scope
# it down, and capture the child's exit code explicitly.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gatePath 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $prevEap }
$out | Select-Object -Last 18 | ForEach-Object { '  ' + "$_".Trim() }
"exit=$code"
if ($code -eq 0) {
    '  *** BLIND GATE: passed without the patch - do not adopt as-is ***'
}
else {
    '  OK: gate rejects the unpatched tree (exit ' + $code + ')'
}

# Leave the tree as we found it.
Remove-Item $gatePath -Force -ErrorAction SilentlyContinue
'  gate removed again: ' + (-not (Test-Path $gatePath))
