# Pull jzkk720 frontend 0.1.90 and verify branding inside it.
$ErrorActionPreference = "Continue"
$img = "ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.90"
Write-Output "pulling $img ..."
docker pull $img 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -Last 4
Write-Output "pull exit: $LASTEXITCODE"
$present = docker images "ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.90" --format "{{.ID}} {{.Size}}"
Write-Output "image present: $present"
if ($present) {
    Write-Output "=== branding grep test (decisive) ==="
    $cnt = docker run --rm --entrypoint sh $img -c "grep -rl 'pacgate' /app/frontend/.next 2>/dev/null | wc -l"
    Write-Output "pacgate-marked .next files: $cnt (0 = UNBRANDED, >0 = branded)"
    $cnt2 = docker run --rm --entrypoint sh $img -c "grep -rl 'pacgate' /app/frontend/.next 2>/dev/null | head -5"
    Write-Output "sample files:"
    $cnt2 | ForEach-Object { Write-Output "  $_" }
    $bid = docker run --rm --entrypoint sh $img -c "cat /app/frontend/.next/BUILD_ID 2>/dev/null"
    Write-Output "BUILD_ID: $bid"
}