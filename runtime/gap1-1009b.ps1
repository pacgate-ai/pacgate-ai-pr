# Gap 1 execution v2: compose validation needs a .env (fresh deploys get one from
# install.ps1). Copy the LIVE .env (gitignored, machine-local) into the worktree
# ONLY for validation, then validate, then stage + commit.
$ErrorActionPreference = 'Stop'
$wt = 'C:\Users\pacga\github-pr\pacgate-law\runtime\wt-v0125'
$liveEnv = 'c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\.env'

# --- 4. validate compose config (needs .env; copy live one temporarily) ---
$envDst = Join-Path $wt 'deploy\client-bundle\.env'
$envCopied = $false
if (-not (Test-Path $envDst) -and (Test-Path $liveEnv)) {
    Copy-Item $liveEnv $envDst
    $envCopied = $true
    Write-Output 'validation: copied live .env into worktree (temporary, will delete)'
}
Push-Location (Join-Path $wt 'deploy\client-bundle')
cmd /c "docker compose -f compose.bundle.yaml config > nul 2>&1"
$cfgExit = $LASTEXITCODE
if ($cfgExit -eq 0) { Write-Output 'compose config: VALID' } else { Write-Output "compose config: INVALID (exit $cfgExit)"; Pop-Location; exit 1 }
Pop-Location
if ($envCopied) { Remove-Item $envDst -Force; Write-Output 'validation: temporary .env deleted' }

# --- 5. stage + secret scan ---
Set-Location $wt
git add deploy/client-bundle/patches/deer-flow-tool-policy.py deploy/client-bundle/patches/deer-flow-skill-storage.py deploy/client-bundle/compose.bundle.yaml deploy/client-bundle/deer-flow-config.yaml deploy/client-bundle/compose.prod.yaml
Write-Output '--- staged ---'
git diff --cached --stat | Select-Object -Last 8
Write-Output '--- secret scan on staged diff ---'
$secretHits = git diff --cached | Select-String -Pattern 'api_key|API_KEY|Bearer|password|sk-|secret' | Select-Object -First 3
if ($secretHits) { Write-Output 'SECRET HITS FOUND:'; $secretHits } else { Write-Output '(clean)' }
Write-Output '--- confirm .env NOT staged ---'
$envStaged = git diff --cached --name-only | Select-String -SimpleMatch '.env'
if ($envStaged) { Write-Output 'ENV STAGED - ABORT'; exit 1 } else { Write-Output '(no .env staged - good)' }
