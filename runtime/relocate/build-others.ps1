$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$log  = Join-Path $repo 'runtime\relocate\BUILD-OTHERS.log'

"=== BUILD REMAINING IMAGES ===" | Out-File $log -Encoding utf8
"started: $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8

$builds = @(
    @{ n = 'pacgate-mcp';      cwd = (Join-Path $pa 'deploy\pacgate-mcp'); f = 'Dockerfile'; tag = 'pacgate-mcp:local-verify' },
    @{ n = 'deer-flow-pacgate'; cwd = $pa; f = 'deploy/deer-flow-pacgate/Dockerfile'; tag = 'deer-flow-pacgate:local-verify' },
    @{ n = 'deer-flow-frontend'; cwd = $pa; f = 'deploy/deer-flow-frontend-pacgate/Dockerfile'; tag = 'deer-flow-frontend:local-verify' }
)

$results = @()
foreach ($b in $builds) {
    "" | Out-File $log -Append -Encoding utf8
    "=== $($b.n) ===" | Out-File $log -Append -Encoding utf8
    "cwd: $($b.cwd)" | Out-File $log -Append -Encoding utf8
    "file: $($b.f)" | Out-File $log -Append -Encoding utf8

    Push-Location $b.cwd
    $t0 = Get-Date
    & docker build --progress=plain -f $b.f -t $b.tag . 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
    $code = $LASTEXITCODE
    Pop-Location

    $secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
    "exit=$code  duration=${secs}s" | Out-File $log -Append -Encoding utf8
    $results += [pscustomobject]@{ Name = $b.n; Exit = $code; Secs = $secs }
    Write-Host "$($b.n): exit=$code (${secs}s)"
}

"" | Out-File $log -Append -Encoding utf8
"=== SUMMARY ===" | Out-File $log -Append -Encoding utf8
foreach ($r in $results) { "$($r.Name): exit=$($r.Exit) ($($r.Secs)s)" | Out-File $log -Append -Encoding utf8 }
"finished: $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8

Write-Host "`nlog: $log"