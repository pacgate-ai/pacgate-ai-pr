$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\bindmount-deletion-experiment.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('EXPERIMENT: what actually happens to a CONTAINER when its bind-mount source')
$lines.Add('is deleted? (tested with a THROWAWAY container + THROWAWAY directory --')
$lines.Add('no real data involved)')
$lines.Add('')

# Build a sandbox: temp dir with a file, mounted read-write into a throwaway container.
$tmp = 'c:\Users\pacga\github-pr\pacgate-law\runtime\_sandbox_mount_test'
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $tmp 'marker.txt'), 'hello', (New-Object System.Text.UTF8Encoding($false)))

$img = 'nginx:1.27-alpine'
$name = 'bindtest-throwaway'

& docker rm -f $name 2>$null | Out-Null

# Start a long-running container that reads the mount periodically.
& docker run -d --name $name -v "${tmp}:/data" --entrypoint sh $img -c "while true; do cat /data/marker.txt >/dev/null 2>&1 && echo OK >> /tmp/probe.log || echo FAIL >> /tmp/probe.log; sleep 2; done" 2>&1 | Out-Null

Start-Sleep -Seconds 3

$lines.Add('--- phase 1: mount source exists ---')
$state1 = (& docker inspect $name --format '{{.State.Running}}' 2>$null)
$lines.Add("  container running      : $state1")
$probe1 = (& docker exec $name sh -c "cat /data/marker.txt 2>&1" 2>&1)
$lines.Add("  read /data/marker.txt  : $probe1")
$lines.Add('')

$lines.Add('--- phase 2: DELETE the host source directory while container runs ---')
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
$lines.Add("  host dir exists now    : $(Test-Path -LiteralPath $tmp)")
Start-Sleep -Seconds 3

$state2 = (& docker inspect $name --format '{{.State.Running}}' 2>$null)
$lines.Add("  container still running: $state2   <-- key finding")
$lines.Add('')

$lines.Add('--- phase 3: can the container still read the mount? ---')
$probe2 = (& docker exec $name sh -c "ls /data 2>&1; echo '---'; cat /data/marker.txt 2>&1" 2>&1)
foreach ($p in $probe2) { $lines.Add("    $p") }
$lines.Add('')

$lines.Add('--- phase 4: does the app see an empty/stale mount? ---')
$probe3 = (& docker exec $name sh -c "ls -la /data 2>&1 | head -5" 2>&1)
foreach ($p in $probe3) { $lines.Add("    $p") }
$lines.Add('')

$lines.Add('--- phase 5: what did the loop observe? ---')
$log = (& docker exec $name sh -c "tail -5 /tmp/probe.log 2>&1" 2>&1)
foreach ($p in $log) { $lines.Add("    $p") }
$lines.Add('')

# cleanup
& docker rm -f $name 2>$null | Out-Null
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
$lines.Add('  (throwaway container and sandbox directory cleaned up)')
$lines.Add('')

$lines.Add('INTERPRETATION:')
$lines.Add('  If the container STAYS RUNNING but the mount becomes empty/unreadable,')
$lines.Add('  then deleting C:\pacgate-ai-pr does NOT crash the stack instantly --')
$lines.Add('  it silently strips data and config from running services, which is')
$lines.Add('  arguably WORSE (silent, not loud) and certainly not "running perfectly".')

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
