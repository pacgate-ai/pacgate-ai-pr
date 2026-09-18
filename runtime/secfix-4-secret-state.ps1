# Todo 4: assess GHCR_RELEASE_PAT secret state + CI blocker status.
# The pacgate-ai PAT has NO admin access to upstream (secrets API = 403),
# so this script gathers what IS observable and produces a decision summary.
$ErrorActionPreference = "Continue"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$upstream = "JZKK720/pacgate-ai-pr"

Write-Output "=== 1. Secrets API access ==="
try {
    $s = Invoke-RestMethod -Uri "$api/repos/$upstream/actions/secrets" -Headers $h -TimeoutSec 30
    Write-Output "secrets visible: $($s.total_count)"
    $s.secrets | ForEach-Object { Write-Output "  - $($_.name) updated=$($_.updated_at)" }
} catch {
    Write-Output "secrets API: HTTP $($_.Exception.Response.StatusCode.value__) (403 = no admin access, expected)"
}

Write-Output "=== 2. Does the workflow reference GHCR_RELEASE_PAT? ==="
$wf = Invoke-RestMethod -Uri "$api/repos/$upstream/contents/.github/workflows/build-ghcr.yml?ref=main" -Headers $h -TimeoutSec 30
$wfText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($wf.content))
$refs = @($wf -split "`n" | Select-String "GHCR_RELEASE_PAT|packages: write|password-stdin")
Write-Output "references found: $($refs.Count)"
$refs | ForEach-Object { Write-Output "  $($_.Line.Trim().Substring(0, [Math]::Min(100, $_.Line.Trim().Length)))" }

Write-Output "=== 3. Latest CI run state (is the blocker still live?) ==="
$runs = Invoke-RestMethod -Uri "$api/repos/$upstream/actions/runs?per_page=3" -Headers $h -TimeoutSec 30
$runs.workflow_runs | ForEach-Object { Write-Output "  run#$($_.run_number) $($_.conclusion) sha=$($_.head_sha.Substring(0,7)) $($_.created_at)" }

Write-Output "=== 4. jzkk720 package write-permission probe (the proven blocker) ==="
# Anonymous token for jzkk720/pacgate-api - if CI could write, a fresh CI run would
# succeed; we cannot dispatch without admin, so we check the package's repo-link state.
try {
    $pkgs = Invoke-RestMethod -Uri "$api/users/jzkk720/packages/container/pacgate-api" -Headers $h -TimeoutSec 30
    Write-Output "jzkk720/pacgate-api: visibility=$($pkgs.visibility) repo-link=$($pkgs.repository.full_name)"
} catch {
    Write-Output "package probe: HTTP $($_.Exception.Response.StatusCode.value__)"
}