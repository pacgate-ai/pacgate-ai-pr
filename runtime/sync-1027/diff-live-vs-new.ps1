# The live middleware already exposes window_size / tool_freq_overrides, so the
# "monotonic counter" premise needs checking rather than assuming. Diff the LIVE
# file against the NEW patch, and check whether the live CONFIG carries the
# loop_detection block (without it, defaults 50/50 apply and bash still stops).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')
$git = 'C:\Program Files\Git\cmd\git.exe'

$live = Join-Path $env:TEMP 'live-loop.py'
$new = Join-Path $env:TEMP 'new-loop.py'

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker exec deer-flow cat /app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py 2>$null |
    Out-File -FilePath $live -Encoding utf8
& $git show 'upstream/main:deploy/client-bundle/patches/deer-flow-loop-detection.py' 2>$null |
    Out-File -FilePath $new -Encoding utf8
$ErrorActionPreference = $prevEap

'=== sizes ==='
'  live_lines = ' + (Get-Content $live).Count
'  new_lines  = ' + (Get-Content $new).Count

''
'=== live vs new: differing line count ==='
$d = Compare-Object (Get-Content $live) (Get-Content $new)
"  diff_lines = $($d.Count)"
$d | Select-Object -First 25 | ForEach-Object { '  {0} {1}' -f $_.SideIndicator, $_.InputObject.Trim() }

''
'=== does the LIVE mounted config carry a loop_detection block? ==='
$cfg = 'pacgate-ai\deploy\client-bundle\deer-flow-config.yaml'
$txt = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Resolve-Path $cfg)))
'  local_config_has_loop_detection = ' + $txt.Contains('loop_detection:')
'  local_config_has_bash_override  = ' + $txt.Contains('tool_freq_overrides')

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$liveCfg = & docker exec deer-flow grep -c 'loop_detection' /app/backend/config.yaml 2>&1
'  live_container_config_loop_detection_lines = ' + ("$liveCfg".Trim())
$liveOv = & docker exec deer-flow grep -c 'tool_freq_overrides' /app/backend/config.yaml 2>&1
'  live_container_config_overrides_lines      = ' + ("$liveOv".Trim())
$ErrorActionPreference = $prevEap
