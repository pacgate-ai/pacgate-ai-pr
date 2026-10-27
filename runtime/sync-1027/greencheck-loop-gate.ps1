# Does the new gate go GREEN once the patch is in place? This is the decisive
# question for "can this AIPC work perfectly": if the gate dies on PowerShell 5.1
# native-stderr promotion (the bug this repo already fixed twice in
# test-memory-lane.ps1), it will be permanently red here even when correct.
#
# Everything is restored afterwards; nothing is committed.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\pacgate-ai')
$git = 'C:\Program Files\Git\cmd\git.exe'

$gatePath = '.\scripts\test-loop-detection-window.ps1'
$patchPath = '.\deploy\client-bundle\patches\deer-flow-loop-detection.py'
$auditPath = '.\scripts\audit-deer-flow-patches.ps1'

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $git show 'upstream/main:scripts/test-loop-detection-window.ps1' 2>$null | Out-File $gatePath -Encoding utf8
& $git show 'upstream/main:deploy/client-bundle/patches/deer-flow-loop-detection.py' 2>$null | Out-File $patchPath -Encoding utf8
& $git show 'upstream/main:scripts/audit-deer-flow-patches.ps1' 2>$null | Out-File $auditPath -Encoding utf8
$ErrorActionPreference = $prevEap

'=== files staged (uncommitted) ==='
foreach ($p in @($gatePath, $patchPath, $auditPath)) { '  {0} = {1}' -f $p, (Test-Path $p) }

''
'=== run gate WITH patch present ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gatePath 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $prevEap }

$out | ForEach-Object { '  ' + "$_".Trim() } | Select-Object -Last 30
"exit=$code"

''
'=== verdict ==='
if ($code -eq 0) { '  GREEN with patch present - gate is usable here' }
else {
    '  RED even with the patch present.'
    '  Check whether the failure is an ASSERTION or a PowerShell native-stderr abort:'
    $out | Select-String -Pattern 'NativeCommandError|CategoryInfo|FAIL' | Select-Object -First 8 |
        ForEach-Object { '    ' + "$_".Trim() }
}

''
'=== restoring tree ==='
Remove-Item $gatePath, $patchPath, $auditPath -Force -ErrorAction SilentlyContinue
& $git status --short -- scripts deploy 2>&1 | ForEach-Object { '  ' + "$_".Trim() }
'  (empty above = clean)'
