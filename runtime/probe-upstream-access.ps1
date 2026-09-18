# Probe upstream (JZKK720/pacgate-ai-pr) access with the stored GitHub PAT.
# NEVER prints the token itself - only metadata and permission booleans.
$ErrorActionPreference = "Continue"

$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$tokenLine = ($cred | Select-String "^password=").Line
$userLine  = ($cred | Select-String "^username=").Line
if (-not $tokenLine) { Write-Output "NO-TOKEN: credential manager returned no password"; exit 1 }
$token = $tokenLine.Substring(9)
Write-Output "credential username: $($userLine.Substring(9))"
Write-Output "token length: $($token.Length) (not printed)"

$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-probe"; Accept = "application/vnd.github+json" }

# 1. Which account does this token belong to?
try {
    $me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -TimeoutSec 20
    Write-Output "authenticated-as: $($me.login)"
} catch {
    Write-Output "auth-check FAIL: $($_.Exception.Message)"
}

# 2. Token scopes (from response header - safe to print)
try {
    $resp = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -TimeoutSec 20 -UseBasicParsing
    Write-Output "X-OAuth-Scopes: $($resp.Headers['X-OAuth-Scopes'])"
} catch {
    Write-Output "scope-check FAIL: $($_.Exception.Message)"
}

# 3. Access to upstream repo + permission level
try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr" -Headers $headers -TimeoutSec 20
    Write-Output "upstream-repo-visible: yes (private=$($r.private))"
    Write-Output "permissions: admin=$($r.permissions.admin) maintain=$($r.permissions.maintain) push=$($r.permissions.push) pull=$($r.permissions.pull)"
} catch {
    Write-Output "upstream-repo-access FAIL: $($_.Exception.Message)"
}

# 4. Can this token read repo secrets metadata (admin-level probe)?
try {
    $null = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr/actions/secrets" -Headers $headers -TimeoutSec 20
    Write-Output "secrets-list: OK (admin-level access confirmed)"
} catch {
    Write-Output "secrets-list FAIL: $($_.Exception.Response.StatusCode.value__)"
}

# 5. Workflow dispatch permission probe (GET workflow, not dispatching yet)
try {
    $wf = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr/actions/workflows/build-ghcr.yml" -Headers $headers -TimeoutSec 20
    Write-Output "workflow-visible: yes (state=$($wf.state))"
} catch {
    Write-Output "workflow-visible FAIL: $($_.Exception.Response.StatusCode.value__)"
}