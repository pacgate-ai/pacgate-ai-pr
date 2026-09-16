$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\POST-CUTOVER-FUNCTIONAL.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'POST-CUTOVER FUNCTIONAL VERIFICATION'
A ('=' * 70)
A ''
A 'Containers being "up" is not proof the apps work - a bind mount that failed'
A 'to follow the move leaves a container running against an empty directory.'
A 'These checks exercise the actual services.'

# ---- helper ----------------------------------------------------------------
function Try-Url([string]$label, [string]$url) {
    try {
        $r = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        A ("  {0,-46} HTTP {1}" -f $label, $r.StatusCode)
        return $true
    } catch {
        $code = $null
        try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code) { A ("  {0,-46} HTTP {1} (responded)" -f $label, $code); return $true }
        A ("  {0,-46} FAILED: {1}" -f $label, $_.Exception.Message)
        return $false
    }
}

# ---- 1. ports actually listening -------------------------------------------
A "`n=== 1. Published ports ==="
$ports = docker ps --format '{{.Names}}|{{.Ports}}' | Where-Object { $_ -match 'pacgate|deer-flow|openviking|qm-' }
foreach ($p in $ports) {
    $q = $p -split '\|'
    $pub = @(($q[1] -split ',') | Where-Object { $_ -match '->' })
    if ($pub) { A ("  {0,-24} {1}" -f $q[0], ($pub -join ' ')) }
}

# ---- 2. HTTP endpoints -----------------------------------------------------
A "`n=== 2. Service endpoints ==="
$ok = 0; $bad = 0
$targets = @(
    @{ l = 'pacgate-api /healthz';    u = 'http://localhost:8089/healthz' },
    @{ l = 'pacgate-api /api/health'; u = 'http://localhost:8089/api/health' },
    @{ l = 'pacgate-api root';        u = 'http://localhost:8089/' },
    @{ l = 'deer-flow frontend';      u = 'http://localhost:8090/' },
    @{ l = 'nginx :8089';             u = 'http://localhost:8089/' },
    @{ l = 'qm portal';               u = 'http://localhost:8181/' },
    @{ l = 'qm mailpit';              u = 'http://localhost:8025/' }
)
foreach ($t in $targets) {
    if (Try-Url $t.l $t.u) { $ok++ } else { $bad++ }
}

# ---- 3. DB: prove the real data is attached --------------------------------
A "`n=== 3. Database content (proves the volume, not just the container) ==="
$qs = @(
    @{ l = 'tenants';        q = 'select count(*) from tenants;' },
    @{ l = 'users';          q = 'select count(*) from users;' },
    @{ l = 'tables';         q = 'select count(*) from information_schema.tables where table_schema=''public'';' },
    @{ l = 'db size';        q = 'select pg_size_pretty(pg_database_size(''pacgate''));' },
    @{ l = 'tenant names';   q = 'select string_agg(name, '', '') from tenants;' }
)
foreach ($x in $qs) {
    $r = (& docker exec pacgate-db psql -U pacgate -d pacgate -tAc $x.q 2>&1) -join ''
    A ("  {0,-14} {1}" -f $x.l, $r.Trim())
}

# ---- 4. deer-flow state (the admin user the handbook warned about) ----------
A "`n=== 4. deer-flow state (its admin user lives in ./data) ==="
foreach ($p in @('/data', '/app/backend/.deer-flow')) {
    $r = (& docker exec deer-flow sh -c "ls -la $p 2>/dev/null | head -8" 2>&1)
    A ("  --- deer-flow:$p ---")
    foreach ($x in @($r -split "`n" | Select-Object -First 6)) { A ("    " + $x) }
}
$dbIn = (& docker exec deer-flow sh -c "ls -la /data/*.db /data/deer-flow 2>/dev/null" 2>&1)
A "  --- db-ish files under /data ---"
foreach ($x in @($dbIn -split "`n" | Select-Object -First 8)) { A ("    " + $x) }

# ---- 5. bind mounts point at the NEW path, and files are readable -----------
A "`n=== 5. Mount sources are the NEW path and readable inside the container ==="
foreach ($pair in @(
        @{ c = 'pacgate-api';  d = '/data' },
        @{ c = 'deer-flow';    d = '/app/backend/config.yaml' },
        @{ c = 'pacgate-nginx'; d = '/etc/nginx/conf.d/default.conf' },
        @{ c = 'openviking';   d = '/app/.openviking' })) {
    $r = (& docker exec $pair.c sh -c "test -e $($pair.d) && echo PRESENT || echo MISSING" 2>&1) -join ''
    A ("  {0,-18} {1,-32} {2}" -f $pair.c, $pair.d, $r.Trim())
}

# ---- 6. startup errors? ----------------------------------------------------
A "`n=== 6. Recent errors in key containers (last 15 log lines) ==="
foreach ($c in @('pacgate-api','deer-flow','pacgate-nginx','openclaw')) {
    $exists = @(docker ps -a --format '{{.Names}}') -contains $c
    if (-not $exists) { continue }
    A ("  --- $c ---")
    $r = (& docker logs --tail 15 $c 2>&1)
    $errs = @($r | Where-Object { $_ -match 'error|fail|refus|denied|cannot|not found' })
    if ($errs.Count -eq 0) { A "    (no error-like lines)" }
    else { foreach ($x in ($errs | Select-Object -First 6)) { A ("    " + $x) } }
}

A "`n=== SUMMARY ==="
A ("  endpoints responding: {0}   failing: {1}" -f $ok, $bad)
A ("  containers running  : {0}" -f @(docker ps -q).Count)

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"