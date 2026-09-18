# Retry clone of the fork with backoff. ASCII output only.
$tmp = "C:\Users\pacga\github-pr\pacgate-law\runtime\tmp-sec-fix"
$ok = $false
foreach ($i in 1..4) {
    Write-Output "clone attempt $i..."
    git clone --quiet https://github.com/pacgate-ai/pacgate-ai-pr.git $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) { $ok = $true; break }
    Start-Sleep -Seconds 8
}
if ($ok) {
    Write-Output "CLONE-OK"
    Write-Output "head: $(git -C $tmp log --oneline -1)"
} else {
    Write-Output "CLONE-FAILED-ALL-ATTEMPTS exit=$LASTEXITCODE"
}