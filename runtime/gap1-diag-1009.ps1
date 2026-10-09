# Diagnose the compose config failure in the worktree.
$ErrorActionPreference = 'Continue'
$wt = 'C:\Users\pacga\github-pr\pacgate-law\runtime\wt-v0125'
Set-Location (Join-Path $wt 'deploy\client-bundle')
Write-Output '--- .env present? ---'
Test-Path .env
Write-Output '--- compose config output (first 25 lines) ---'
docker compose -f compose.bundle.yaml config 2>&1 | Select-Object -First 25
Write-Output '--- exit ---'
$LASTEXITCODE