# Verify run #11 outcome: what did it publish? + fix the workflow-text check.
$ErrorActionPreference = "Continue"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$upstream = "JZKK720/pacgate-ai-pr"

Write-Output "=== workflow text check (fixed) ==="
$wf = Invoke-RestMethod -Uri "$api/repos/$upstream/contents/.github/workflows/build-ghcr.yml?ref=main" -Headers $h -TimeoutSec 30
$wfText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($wf.content))
$refs = @($wfText -split "`n" | Select-String "GHCR_RELEASE_PAT|packages: write|password-stdin")
Write-Output "references: $($refs.Count)"
$refs | ForEach-Object { Write-Output "  $($_.Line.Trim())" }

Write-Output "=== run #11 jobs ==="
$runs = Invoke-RestMethod -Uri "$api/repos/$upstream/actions/runs?per_page=5" -Headers $h -TimeoutSec 30
$run11 = $runs.workflow_runs | Where-Object { $_.run_number -eq 11 }
if ($run11) {
    Write-Output "run#11: $($run11.conclusion) sha=$($run11.head_sha.Substring(0,7)) event=$($run11.event)"
    $jobs = Invoke-RestMethod -Uri "$api/repos/$upstream/actions/runs/$($run11.id)/jobs" -Headers $h -TimeoutSec 30
    $jobs.jobs | ForEach-Object { Write-Output "  job: $($_.name) -> $($_.conclusion) ($($_.completed_at))" }
}

Write-Output "=== GHCR jzkk720 tags NOW (did run #11 publish?) ==="
foreach ($img in @("pacgate-api","pacgate-mcp","deer-flow-pacgate","deer-flow-frontend-pacgate")) {
    try {
        $t = (Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:jzkk720/$img`:pull" -TimeoutSec 15).token
        $hh = @{ Authorization = "Bearer $t" }
        $m = Invoke-WebRequest -Uri "https://ghcr.io/v2/jzkk720/$img/tags/list" -Headers $hh -TimeoutSec 15 -UseBasicParsing
        Write-Output "jzkk720/$img : $($m.Content)"
    } catch { Write-Output "jzkk720/$img : HTTP $($_.Exception.Response.StatusCode.value__)" }
}