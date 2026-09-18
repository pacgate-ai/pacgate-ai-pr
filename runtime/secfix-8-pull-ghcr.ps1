# Pull the 3 remaining GHCR images.
$ErrorActionPreference = "Continue"
foreach ($img in @("ghcr.io/jzkk720/pacgate-api:0.1.90","ghcr.io/jzkk720/pacgate-mcp:0.1.90","ghcr.io/jzkk720/deer-flow-pacgate:0.1.90")) {
    Write-Output "pulling $img ..."
    docker pull $img 2>&1 | Select-Object -Last 1
    Write-Output "exit=$LASTEXITCODE"
}
Write-Output "--- final local presence ---"
docker images "ghcr.io/jzkk720/*" --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"