# Check which compose images are present locally; pull docker.io ones via daocloud mirror.
$ErrorActionPreference = "Continue"
Write-Output "=== local image presence ==="
foreach ($img in @("ghcr.io/jzkk720/pacgate-api:0.1.90","ghcr.io/jzkk720/pacgate-mcp:0.1.90","ghcr.io/jzkk720/deer-flow-pacgate:0.1.90","ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.90","pgvector/pgvector:pg16","nginx:1.27-alpine")) {
    $r = docker images $img --format "{{.ID}}"
    if ($r) { Write-Output "PRESENT: $img ($r)" } else { Write-Output "MISSING: $img" }
}
Write-Output "=== pull docker.io images via daocloud mirror (proven workaround) ==="
foreach ($pair in @(@("docker.m.daocloud.io/library/nginx","1.27-alpine","nginx:1.27-alpine"))) {
    $src = $pair[0]; $tag = $pair[1]; $dst = $pair[2]
    Write-Output "pull $src`:$tag ..."
    docker pull "$src`:$tag" 2>&1 | Select-Object -Last 1
    if ($LASTEXITCODE -eq 0) { docker tag "$src`:$tag" $dst; Write-Output "tagged -> $dst" } else { Write-Output "MIRROR-PULL-FAIL for $dst" }
}
# pgvector is not under library/ on daocloud; try direct mirror path
Write-Output "pull pgvector via mirror ..."
docker pull "docker.m.daocloud.io/pgvector/pgvector:pg16" 2>&1 | Select-Object -Last 1
if ($LASTEXITCODE -eq 0) { docker tag "docker.m.daocloud.io/pgvector/pgvector:pg16" "pgvector/pgvector:pg16"; Write-Output "tagged -> pgvector/pgvector:pg16" } else { Write-Output "pgvector mirror FAIL (may not exist on daocloud)" }
Write-Output "=== final presence ==="
foreach ($img in @("ghcr.io/jzkk720/pacgate-api:0.1.90","ghcr.io/jzkk720/pacgate-mcp:0.1.90","ghcr.io/jzkk720/deer-flow-pacgate:0.1.90","ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.90","pgvector/pgvector:pg16","nginx:1.27-alpine")) {
    $r = docker images $img --format "{{.ID}}"
    if ($r) { Write-Output "PRESENT: $img" } else { Write-Output "MISSING: $img" }
}