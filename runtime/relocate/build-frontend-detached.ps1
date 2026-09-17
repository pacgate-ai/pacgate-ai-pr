$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$log  = Join-Path $repo 'runtime\relocate\BUILD-FRONTEND.log'
$done = Join-Path $repo 'runtime\relocate\BUILD-FRONTEND.done'
$inner = Join-Path $repo 'runtime\relocate\build-frontend-inner.ps1'

Remove-Item $done -Force -ErrorAction SilentlyContinue

# Detached (survives terminal close - learned the hard way).
@"
`$ErrorActionPreference = 'Continue'
`$pa = '$pa'
`$log = '$log'
`$done = '$done'
"=== FRONTEND BUILD (detached, via the supported entry point) ===" | Out-File `$log -Encoding utf8
"started: `$(Get-Date -Format o)" | Out-File `$log -Append -Encoding utf8
"" | Out-File `$log -Append -Encoding utf8

# Use build-frontend.ps1 - the SUPPORTED entry point. It clones the pinned
# bytedance source if absent (already present), applies the PacGate frontend
# overrides, and then runs docker build. Calling docker build directly is what
# failed before, because it skips the override step.
Push-Location `$pa
`$t0 = Get-Date
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path `$pa 'deploy\build-frontend.ps1') -Tag 'local-verify' 2>&1 |
    Tee-Object -FilePath `$log -Append | Out-Null
`$code = `$LASTEXITCODE
Pop-Location

`$secs = [math]::Round(((Get-Date)-`$t0).TotalSeconds, 1)
"" | Out-File `$log -Append -Encoding utf8
"=== RESULT ===" | Out-File `$log -Append -Encoding utf8
"exit=`$code  duration=`${secs}s" | Out-File `$log -Append -Encoding utf8
"finished: `$(Get-Date -Format o)" | Out-File `$log -Append -Encoding utf8
"done" | Out-File `$done -Encoding utf8
"@ | Out-File $inner -Encoding utf8

Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$inner) -WindowStyle Hidden
Write-Host "launched detached frontend build"
Write-Host "  log : $log"
Write-Host "  done: $done"