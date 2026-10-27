# Fix Defect 1: the new gate merges native stderr under $ErrorActionPreference='Stop',
# so PS 5.1 promotes the container Python's LangChain deprecation warning to a
# TERMINATING error and the gate aborts before reading its own verdict.
#
# This is the THIRD occurrence of this bug in this repo (test-memory-lane.ps1 was
# fixed for it twice: our d1ed509 and upstream's 86a9feb). Without this fix the
# gate is permanently red on every AIPC, which ships PowerShell 5.1.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$g = Join-Path (Get-Location) 'pacgate-ai\scripts\test-loop-detection-window.ps1'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($g))

$old = '    $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1'
if (-not $t.Contains($old)) { throw 'anchor not found - inspect the file before editing' }

$nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
$new = @(
'    # Pacgate 2026-10-27: the container python emits a LangChainPendingDeprecation'
'    # Warning on STDERR when it imports deerflow. Under $ErrorActionPreference ='
'    # ''Stop'' (set at the top of this gate) PowerShell 5.1 promotes a native'
'    # command''s stderr to a TERMINATING error, so the gate aborted before it could'
'    # read the verdict it had just produced - permanently red on every AIPC, which'
'    # ships 5.1. Scope the preference down for this one call. Same defect already'
'    # fixed twice in test-memory-lane.ps1 (d1ed509, 86a9feb).'
'    $prevEap = $ErrorActionPreference'
'    $ErrorActionPreference = ''Continue'''
'    try {'
'        $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1'
'    }'
'    finally { $ErrorActionPreference = $prevEap }'
) -join $nl

$t = $t.Replace($old, $new)
[System.IO.File]::WriteAllText($g, $t, [System.Text.UTF8Encoding]::new($false))
'patched'
