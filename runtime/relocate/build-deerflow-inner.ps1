$ErrorActionPreference = 'Continue'
$pa = 'c:\Users\pacga\github-pr\pacgate-law\pacgate-ai'
$log = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\BUILD-DEERFLOW.log'
$done = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\BUILD-DEERFLOW.done'
"=== DEER-FLOW BUILDS (detached) ===" | Out-File $log -Encoding utf8
"started: $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8

$builds = @(
    @{ n = 'deer-flow-pacgate';  f = 'deploy/deer-flow-pacgate/Dockerfile';          tag = 'deer-flow-pacgate:local-verify' },
    @{ n = 'deer-flow-frontend'; f = 'deploy/deer-flow-frontend-pacgate/Dockerfile'; tag = 'deer-flow-frontend:local-verify' }
)
$results = @()
foreach ($b in $builds) {
    "" | Out-File $log -Append -Encoding utf8
    "=== $($b.n) ===" | Out-File $log -Append -Encoding utf8
    Push-Location $pa
    $t0 = Get-Date
    & docker build --progress=plain -f $b.f -t $b.tag . 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
    $code = $LASTEXITCODE
    Pop-Location
    $secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
    "exit=$code  duration=${secs}s" | Out-File $log -Append -Encoding utf8
    $results += "$($b.n): exit=$code (${secs}s)"
}
"" | Out-File $log -Append -Encoding utf8
"=== SUMMARY ===" | Out-File $log -Append -Encoding utf8
$results | Out-File $log -Append -Encoding utf8
"finished: $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8
"done" | Out-File $done -Encoding utf8
