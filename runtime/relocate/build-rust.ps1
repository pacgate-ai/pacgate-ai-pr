$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$log  = Join-Path $repo 'runtime\relocate\BUILD-RUST.log'

"=== FULL RUST BUILD ===" | Out-File -FilePath $log -Encoding utf8
"started: $(Get-Date -Format o)" | Out-File -FilePath $log -Append -Encoding utf8
"context: $pa" | Out-File -FilePath $log -Append -Encoding utf8
"" | Out-File -FilePath $log -Append -Encoding utf8

Push-Location $pa
$t0 = Get-Date
# --progress=plain gives full compiler output (no TUI), which is what we need
# to diagnose a failure. BuildKit is the default builder.
& docker build --progress=plain -f Dockerfile -t pacgate-api:local-verify . 2>&1 |
    Tee-Object -FilePath $log -Append
$code = $LASTEXITCODE
Pop-Location

$secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
"" | Out-File -FilePath $log -Append -Encoding utf8
"=== RESULT ===" | Out-File -FilePath $log -Append -Encoding utf8
"exit code: $code" | Out-File -FilePath $log -Append -Encoding utf8
"duration : $secs s ($([math]::Round($secs/60,1)) min)" | Out-File -FilePath $log -Append -Encoding utf8
"finished : $(Get-Date -Format o)" | Out-File -FilePath $log -Append -Encoding utf8

Write-Host "exit=$code  duration=${secs}s"
Write-Host "log: $log"