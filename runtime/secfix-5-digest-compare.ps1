# Compare jzkk720:0.1.90 frontend digest vs pacgate-ai:0.1.15 (known branded).
$ErrorActionPreference = "Continue"
$accept = "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json"
foreach ($pair in @(@("jzkk720","0.1.90"), @("pacgate-ai","0.1.15"))) {
    $ns = $pair[0]; $tag = $pair[1]; $img = "deer-flow-frontend-pacgate"
    try {
        $t = (Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:$ns/$img`:pull" -TimeoutSec 15).token
        $h = @{ Authorization = "Bearer $t"; Accept = $accept }
        $r = Invoke-WebRequest -Uri "https://ghcr.io/v2/$ns/$img/manifests/$tag" -Headers $h -Method Head -TimeoutSec 15 -UseBasicParsing
        $d = $r.Headers['Docker-Content-Digest']; if ($d -is [array]) { $d = $d[0] }
        Write-Output "$ns/$img`:$tag = $d"
    } catch { Write-Output "$ns/$img`:$tag : HTTP $($_.Exception.Response.StatusCode.value__)" }
}
Write-Output "=== also compare api/mcp/deer-flow 0.1.90 vs pacgate-ai 0.1.14 ==="
foreach ($img in @("pacgate-api","pacgate-mcp","deer-flow-pacgate")) {
    foreach ($pair in @(@("jzkk720","0.1.90"), @("pacgate-ai","0.1.14"))) {
        $ns = $pair[0]; $tag = $pair[1]
        try {
            $t = (Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:$ns/$img`:pull" -TimeoutSec 15).token
            $h = @{ Authorization = "Bearer $t"; Accept = $accept }
            $r = Invoke-WebRequest -Uri "https://ghcr.io/v2/$ns/$img/manifests/$tag" -Headers $h -Method Head -TimeoutSec 15 -UseBasicParsing
            $d = $r.Headers['Docker-Content-Digest']; if ($d -is [array]) { $d = $d[0] }
            Write-Output "$ns/$img`:$tag = $d"
        } catch { Write-Output "$ns/$img`:$tag : HTTP $($_.Exception.Response.StatusCode.value__)" }
    }
}