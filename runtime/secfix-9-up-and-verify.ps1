# Recreate the pacgate stack with the new jzkk720:0.1.90 images, then verify health.
# Same compose project (pacgate-ai-bundle) -> same volumes, DB untouched.
$ErrorActionPreference = "Continue"
Set-Location "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle"
Write-Output "=== up -d (recreate changed services) ==="
docker compose -f compose.bundle.yaml up -d 2>&1 | Select-Object -Last 10
Write-Output "up exit=$LASTEXITCODE"
Write-Output "=== wait for services ==="
Start-Sleep -Seconds 20
Write-Output "=== container states ==="
docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}" | Select-String "pacgate|deer-flow|openviking" | Out-String -Width 160
Write-Output "=== restart counts (crash-loop check) ==="
docker inspect pacgate-api pacgate-mcp deer-flow deer-flow-frontend pacgate-nginx pacgate-db --format "{{.Name}} restarts={{.RestartCount}} exit={{.State.ExitCode}}" | Out-String
Write-Output "=== DB integrity ==="
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select 'tenants='||count(*) from tenants; select 'users='||count(*) from users;" 2>&1 | Out-String
Write-Output "=== endpoint probes ==="
foreach ($probe in @(@("nginx-root","http://127.0.0.1:8089/"), @("frontend-root","http://127.0.0.1:8090/"), @("api-version(expect401)","http://127.0.0.1:8089/pacgate/version"))) {
    $code = curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --max-time 10 $probe[1] 2>$null
    Write-Output "$($probe[0]) -> HTTP $code"
}