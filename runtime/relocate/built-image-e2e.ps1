$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\BUILT-IMAGE-E2E.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'END-TO-END TEST: the LOCALLY BUILT image against the LIVE database'
A ('=' * 78)
A ''
A 'This is the strongest available proof. It runs the image we just compiled'
A 'from the monorepo path against the real pacgate-db, on the real network.'
A 'If this serves HTTP, the build is genuinely usable - not just "it compiled".'

# ---- 1. what we are testing ------------------------------------------------
A "`n=== 1. Image under test ==="
$img = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.CreatedSince}}|{{.Size}}' |
         Where-Object { $_ -like 'pacgate-api:local-verify*' })
foreach ($i in $img) { A ("  " + $i) }

# ---- 2. the live DB's network ----------------------------------------------
A "`n=== 2. Live DB network (so the built image can reach it) ==="
$net = (docker inspect pacgate-db --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>$null)
A ("  pacgate-db network: {0}" -f $net)

# ---- 3. env the real container uses ----------------------------------------
A "`n=== 3. Env vars the running pacgate-api uses (names only, values hidden) ==="
$envs = @(docker inspect pacgate-api --format '{{range .Config.Env}}{{println .}}{{end}}' 2>$null)
foreach ($e in $envs) {
    $k = ($e -split '=')[0]
    if ($k -match 'PASSWORD|SECRET|TOKEN|KEY') { A ("  {0}=<hidden>" -f $k) }
    else { A ("  " + $e) }
}

# ---- 4. run the BUILT image on the live network ----------------------------
A "`n=== 4. Run the built image against the live DB ==="
$name = 'pacgate-api-builttest'
& docker rm -f $name 2>&1 | Out-Null

# Reuse the real container's env + network so this is a true integration test.
# NOTE: pass env via --env-file, NOT repeated -e flags. Some values contain
# spaces (OPENVIKING_CONF_CONTENT is JSON), and PowerShell's array-to-native
# argument marshalling splits them, producing
# "docker run requires at least 1 argument".
$envFile = Join-Path $env:TEMP 'pg-e2e.env'
$envLines = @()
foreach ($e in $envs) {
    if ($e -match '^(PATH|HOSTNAME|HOME)=') { continue }
    if ($e -notmatch '=') { continue }
    $envLines += $e
}
[System.IO.File]::WriteAllLines($envFile, $envLines, (New-Object System.Text.UTF8Encoding($false)))
A ("  wrote {0} env vars to a temp env-file" -f $envLines.Count)

$runArgs = @('run','-d','--name',$name,'--network',$net,'--env-file',$envFile,'pacgate-api:local-verify')
A ("  docker run --network {0} --env-file <temp> pacgate-api:local-verify" -f $net)
$id = (& docker @runArgs 2>&1) -join ''
A ("  container id: {0}" -f $id.Trim())
Remove-Item $envFile -Force -ErrorAction SilentlyContinue

# ---- 5. did it stay up? ----------------------------------------------------
A "`n=== 5. Container state after 15s ==="
Start-Sleep -Seconds 15
$st = (& docker inspect $name --format '{{.State.Status}} restarts={{.RestartCount}} exit={{.State.ExitCode}}' 2>&1) -join ''
A ("  {0}" -f $st.Trim())

A "`n=== 6. Its logs (did it connect to the DB?) ==="
$logs = @(& docker logs $name 2>&1)
foreach ($x in @($logs | Select-Object -First 25)) { A ("    " + "$x") }

# ---- 7. does it serve HTTP? ------------------------------------------------
A "`n=== 7. HTTP probe against the built image ==="
$ip = (& docker inspect $name --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>$null)
A ("  container IP: {0}" -f $ip)
foreach ($path in @('/', '/healthz', '/api/health')) {
    $r = (& docker exec $name sh -c "command -v curl >/dev/null && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080$path || echo NOCURL" 2>&1) -join ''
    A ("  {0,-14} -> {1}" -f $path, $r.Trim())
}

# ---- 8. cleanup ------------------------------------------------------------
A "`n=== 8. Cleanup ==="
& docker rm -f $name 2>&1 | Out-Null
A ("  removed test container: {0}" -f (-not (@(docker ps -a --format '{{.Names}}') -contains $name)))

A "`n=== VERDICT ==="
A '  See sections 5-7. If the container stayed Up and served HTTP, the locally'
A '  built image is functionally equivalent to the pulled one.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"