# Sync fork/main with upstream/main via merge-upstream API, then verify.
$ErrorActionPreference = "Stop"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$fork = "pacgate-ai/pacgate-ai-pr"
$upstream = "JZKK720/pacgate-ai-pr"

# 0. Confirm fork has 0 unique commits (safe fast-forward)
$cmp = Invoke-RestMethod -Uri "$api/repos/$upstream/compare/pacgate-ai:main...main" -Headers $h -TimeoutSec 30
Write-Output "ahead_by=$($cmp.ahead_by) behind_by=$($cmp.behind_by) (upstream vs fork)"
# FIX: basehead = fork:main...upstream:main -> ahead_by = upstream-only commits,
# behind_by = fork-only commits. Safe fast-forward requires behind_by == 0.
if ($cmp.behind_by -ne 0) { Write-Output "STOP: fork has unique commits, fast-forward unsafe"; exit 1 }

# 1. merge-upstream
$body = @{ branch = "main" } | ConvertTo-Json
try {
    $r = Invoke-RestMethod -Uri "$api/repos/$fork/merge-upstream" -Method Post -Headers $h -TimeoutSec 60 -Body $body -ContentType "application/json"
    Write-Output "merge-upstream: $($r.message) (type=$($r.merge_type))"
} catch {
    Write-Output "merge-upstream resp: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}

# 2. Verify fork/main now == upstream/main
$fMain = Invoke-RestMethod -Uri "$api/repos/$fork/git/ref/heads/main" -Headers $h -TimeoutSec 30
Write-Output "fork/main now: $($fMain.object.sha)"
$upMain = Invoke-RestMethod -Uri "$api/repos/$upstream/git/ref/heads/main" -Headers $h -TimeoutSec 30
Write-Output "upstream/main:  $($upMain.object.sha)"
if ($fMain.object.sha -eq $upMain.object.sha) { Write-Output "SYNC-OK" } else { Write-Output "SYNC-MISMATCH" }