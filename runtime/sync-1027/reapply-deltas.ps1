# Re-apply the 62 local deltas after the swap to 44f7f43.
#
# 58 files are restored verbatim. The 4 that upstream ALSO changed are merged:
# upstream's new content is kept, and only our local additions are re-inserted.
# Restoring those 4 verbatim would silently erase upstream's fix.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$repo = (Get-Location).Path
$preserve = Join-Path $repo 'runtime\sync-1027\local-preserve'
$listFile = Join-Path $repo 'runtime\sync-1027\local-delta-list.txt'

$upstreamTouched = @(
    'pacgate-ai/deploy/client-bundle/compose.bundle.yaml'
    'pacgate-ai/deploy/client-bundle/compose.prod.yaml'
    'pacgate-ai/deploy/client-bundle/deer-flow-config.yaml'
    'pacgate-ai/scripts/run-all-checks.ps1'
)

$rows = (([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($listFile))) -split "`n") |
Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split "`t")[0] }

'--- A. restoring files upstream does NOT touch ---'
$n = 0
foreach ($p in $rows) {
    if ($upstreamTouched -contains $p) { continue }
    $src = Join-Path $preserve ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { "SKIP_MISSING $p"; continue }
    $dst = Join-Path $repo ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    [System.IO.File]::WriteAllBytes($dst, [System.IO.File]::ReadAllBytes($src))
    $n++
}
"restored_verbatim=$n"

'--- B. verifying the 4 merge files ---'
# Upstream already added the loop-detection mount to both compose files and the
# loop_detection block to deer-flow-config.yaml, so these are assertions, not
# inserts. Our own additions must still be present.
$base = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
foreach ($f in @('compose.bundle.yaml', 'compose.prod.yaml')) {
    $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $base $f)))
    "  --- $f"
    foreach ($needle in @('deer-flow-loop-detection.py', 'deer-flow-memory-prompt.py',
            'deer-flow-memory-updater.py', 'deer-flow-uploads-middleware.py',
            'deer-flow/skills/public')) {
        '    {0,-6} {1}' -f $t.Contains($needle), $needle
    }
}

$cfg = Join-Path $base 'deer-flow-config.yaml'
$ct = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($cfg))
'  --- deer-flow-config.yaml'
foreach ($needle in @('loop_detection:', 'tool_freq_overrides', 'subagents:', 'custom_agents')) {
    '    {0,-6} {1}' -f $ct.Contains($needle), $needle
}

$rac = Join-Path $repo 'pacgate-ai\scripts\run-all-checks.ps1'
$rt = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($rac))
'  --- run-all-checks.ps1'
foreach ($needle in @("'scripts/test-prompt-contract.ps1'", "'scripts/test-loop-detection-window.ps1'")) {
    '    {0,-6} {1}' -f $rt.Contains($needle), $needle
}
