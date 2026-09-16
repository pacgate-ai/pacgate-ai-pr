$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$log  = Join-Path $repo 'runtime\relocate\BUILD-DEERFLOW.log'
$done = Join-Path $repo 'runtime\relocate\BUILD-DEERFLOW.done'

# Detached runner: the previous attempt was KILLED when its task terminal
# closed, losing ~40 min of apt downloads. Launch via Start-Process so the
# build survives independently of any terminal.
Remove-Item $done -Force -ErrorAction SilentlyContinue

$inner = Join-Path $repo 'runtime\relocate\build-deerflow-inner.ps1'
@"
`$ErrorActionPreference = 'Continue'
`$pa = '$pa'
`$log = '$log'
`$done = '$done'
"=== DEER-FLOW BUILDS (detached) ===" | Out-File `$log -Encoding utf8
"started: `$(Get-Date -Format o)" | Out-File `$log -Append -Encoding utf8

`$builds = @(
    @{ n = 'deer-flow-pacgate';  f = 'deploy/deer-flow-pacgate/Dockerfile';          tag = 'deer-flow-pacgate:local-verify' },
    @{ n = 'deer-flow-frontend'; f = 'deploy/deer-flow-frontend-pacgate/Dockerfile'; tag = 'deer-flow-frontend:local-verify' }
)
`$results = @()
foreach (`$b in `$builds) {
    "" | Out-File `$log -Append -Encoding utf8
    "=== `$(`$b.n) ===" | Out-File `$log -Append -Encoding utf8
    Push-Location `$pa
    `$t0 = Get-Date
    & docker build --progress=plain -f `$b.f -t `$b.tag . 2>&1 | Tee-Object -FilePath `$log -Append | Out-Null
    `$code = `$LASTEXITCODE
    Pop-Location
    `$secs = [math]::Round(((Get-Date)-`$t0).TotalSeconds, 1)
    "exit=`$code  duration=`${secs}s" | Out-File `$log -Append -Encoding utf8
    `$results += "`$(`$b.n): exit=`$code (`${secs}s)"
}
"" | Out-File `$log -Append -Encoding utf8
"=== SUMMARY ===" | Out-File `$log -Append -Encoding utf8
`$results | Out-File `$log -Append -Encoding utf8
"finished: `$(Get-Date -Format o)" | Out-File `$log -Append -Encoding utf8
"done" | Out-File `$done -Encoding utf8
"@ | Out-File $inner -Encoding utf8

Write-Host "launching detached build..."
Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$inner) `
    -WindowStyle Hidden
Write-Host "launched. log: $log"
Write-Host "done marker: $done"