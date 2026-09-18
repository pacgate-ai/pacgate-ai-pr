# End-to-end branding verification on the RUNNING stack.
$ErrorActionPreference = "Continue"
Write-Output "=== running frontend image + branding ==="
$img = docker inspect deer-flow-frontend --format "{{.Config.Image}}"
Write-Output "running image: $img"
$cnt = docker exec deer-flow-frontend sh -c "grep -rl 'pacgate' /app/frontend/.next 2>/dev/null | wc -l"
Write-Output "pacgate-marked files in RUNNING container: $cnt (expect >0)"
Write-Output "=== served HTML contains branding? ==="
$html = curl.exe -s --noproxy "*" --max-time 10 http://127.0.0.1:8090/ 2>$null
if ($html -match "pacgate") { Write-Output "served HTML: contains 'pacgate' = YES" } else { Write-Output "served HTML: contains 'pacgate' = NO (may be client-rendered; chunk check below)" }
$chunk = docker exec deer-flow-frontend sh -c "grep -rl 'pacgate' /app/frontend/.next/static 2>/dev/null | head -3"
Write-Output "branded static chunks:"
$chunk | ForEach-Object { Write-Output "  $_" }
Write-Output "=== image ID match (running vs pulled) ==="
$runImg = docker inspect deer-flow-frontend --format "{{.Image}}"
$localImg = docker images "ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.90" --format "{{.ID}}"
Write-Output "running=$runImg"
Write-Output "local  =$localImg"
if ($runImg -eq $localImg) { Write-Output "MATCH: running container uses the verified branded image" } else { Write-Output "MISMATCH" }