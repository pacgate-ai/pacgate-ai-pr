$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\BUILT-IMAGE-HTTP.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'HTTP PROOF: the locally built image serves requests'
A ('=' * 78)
A ''
A 'The previous run proved the built image connects to the DB and applies'
A 'migrations. This proves it actually SERVES HTTP. The slim runtime image has'
A 'no curl, so probe from the HOST via a published port instead.'

$name = 'pacgate-api-httptest'
& docker rm -f $name 2>&1 | Out-Null

# reuse the live container's env + network
$envs = @(docker inspect pacgate-api --format '{{range .Config.Env}}{{println .}}{{end}}' 2>$null)
$net  = (docker inspect pacgate-db --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>$null)
$envFile = Join-Path $env:TEMP 'pg-http.env'
$lines = @()
foreach ($e in $envs) { if ($e -match '=' -and $e -notmatch '^(PATH|HOSTNAME|HOME)=') { $lines += $e } }
[System.IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

# publish on a free host port so we can probe from Windows
$port = 18099
A ("`n=== Starting built image on host port {0} ===" -f $port)
$id = (& docker run -d --name $name --network $net --env-file $envFile -p "${port}:8080" pacgate-api:local-verify 2>&1) -join ''
A ("  id: {0}" -f $id.Trim())
Remove-Item $envFile -Force -ErrorAction SilentlyContinue

A "`n=== Waiting for startup ==="
Start-Sleep -Seconds 12
$st = (& docker inspect $name --format '{{.State.Status}} restarts={{.RestartCount}}' 2>&1) -join ''
A ("  state: {0}" -f $st.Trim())

A "`n=== HTTP probes from the HOST ==="
$ok = 0; $bad = 0
foreach ($p in @('/', '/healthz', '/api/health', '/api/matters')) {
    $url = "http://localhost:$port$p"
    try {
        $r = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        A ("  {0,-16} HTTP {1}" -f $p, $r.StatusCode)
        $ok++
    } catch {
        $code = $null
        try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code) { A ("  {0,-16} HTTP {1} (responded)" -f $p, $code); $ok++ }
        else { A ("  {0,-16} FAILED: {1}" -f $p, $_.Exception.Message); $bad++ }
    }
}

A "`n=== Container logs (tail) ==="
$logs = @(& docker logs --tail 8 $name 2>&1)
foreach ($x in $logs) { A ("    " + "$x") }

A "`n=== Cleanup ==="
& docker rm -f $name 2>&1 | Out-Null
A ("  removed: {0}" -f (-not (@(docker ps -a --format '{{.Names}}') -contains $name)))

A "`n=== VERDICT ==="
A ("  endpoints responding: {0}   failing: {1}" -f $ok, $bad)
if ($ok -gt 0) { A '  The locally built image SERVES HTTP against the live database.' }
else { A '  No endpoint responded - investigate.' }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"