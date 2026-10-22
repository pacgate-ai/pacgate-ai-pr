# qm-pacgate re-audit: containers, health, auth gates, sandbox wiring, magic-link readiness — 2026-10-10
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$qm = "$w\pacgate-ai\deploy\qm-pacgate"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }

# 1. Container inventory vs compose
Add-Section "QM CONTAINERS vs COMPOSE"
$qmCompose = Get-Content "$qm\compose.qm.yaml" -Encoding UTF8
$expected = ($qmCompose | Select-String "container_name: (.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
$out += "compose defines: $($expected -join ', ')"
$running = docker ps -a --format "{{.Names}}|{{.Status}}" | Select-String "qm-"
$out += "running:"; $out += ($running | ForEach-Object { $_.ToString() })
foreach ($c in $expected) {
    $line = $running | Where-Object { $_ -match [regex]::Escape($c) }
    if ("$line" -match "Up") { Pass "container $c" "$line" } else { Fail "container $c" "$line" }
}

# 2. Digest pins still match running images
Add-Section "DIGEST PIN CHECK"
$pins = ($qmCompose | Select-String "image: ghcr.io/yc-software/qm/(\w+)@sha256:(\w+)" | ForEach-Object { @{ name = $_.Matches[0].Groups[1].Value; digest = $_.Matches[0].Groups[2].Value } })
foreach ($p in $pins) {
    $cname = "qm-pacgate-$($p.name)"
    $imgId = docker inspect $cname --format "{{.Image}}" 2>$null
    if ("$imgId".Contains($p.digest)) { Pass "digest $cname" "matches pinned sha256:$($p.digest.Substring(0,12))" }
    else { Fail "digest $cname" "running=$imgId pinned=$($p.digest.Substring(0,12))" }
}

# 3. Health surfaces
Add-Section "HEALTH"
foreach ($probe in @(@("portal", "http://localhost:8181/healthz"), @("core", "http://localhost:8180/healthz"), @("mailpit", "http://localhost:8025/api/v1/version"))) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $probe[1] -TimeoutSec 15 -UseBasicParsing
        $sw.Stop()
        Time "$($probe[0]) $($probe[1])" $sw.ElapsedMilliseconds "HTTP $($r.StatusCode)"
    } catch {
        $sw.Stop()
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($probe[0] -eq "mailpit" -and $code) { Time "$($probe[0])" $sw.ElapsedMilliseconds "HTTP $code" }
        else { Fail "$($probe[0]) health" "HTTP $code" }
    }
}

# 4. Auth gates (401 = gate working)
Add-Section "AUTH GATES (401 = correct)"
foreach ($probe in @(@("portal front door", "http://localhost:8181/"), @("core root", "http://localhost:8180/"), @("core api", "http://localhost:8180/api/health"))) {
    try {
        $r = Invoke-WebRequest -Uri $probe[1] -TimeoutSec 15 -UseBasicParsing
        $out += "[NOTE] $($probe[0]): HTTP $($r.StatusCode) (unexpected — expected 401)"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code -eq 401) { Pass "$($probe[0]) gate" "401 (auth enforced)" }
        else { $out += "[NOTE] $($probe[0]): HTTP $code" }
    }
}

# 5. Sandbox wiring (the plan-025 lane)
Add-Section "SANDBOX WIRING"
$sbxEnv = docker exec qm-pacgate-core sh -c "env | grep -E 'LOCAL_SANDBOX|FLY_BASE' 2>/dev/null" 2>&1
$out += "core sandbox env: $sbxEnv"
$dockerCli = docker exec qm-pacgate-core sh -c "which docker && docker --version 2>/dev/null || echo no-docker-cli" 2>&1
$out += "core docker CLI: $dockerCli"
$sock = docker exec qm-pacgate-core sh -c "ls -la /var/run/docker.sock 2>/dev/null || echo no-socket" 2>&1
$out += "core docker socket: $sock"
$sbxImg = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "sandbox-local"
$out += "sandbox-local image: $sbxImg"
# stale sandbox containers (known: 2 exited)
$stale = docker ps -a --format "{{.Names}} {{.Status}}" | Select-String "qm-sbx"
$out += "sandbox containers: $stale"

# 6. qm DB state
Add-Section "QM DB"
$qmDb = docker exec qm-pacgate-pg psql -U postgres -l 2>&1 | Select-String "qm|postgres"
$out += "databases: $qmDb"

# 7. Magic-link readiness (allowlist + transport)
Add-Section "MAGIC-LINK READINESS"
$qmEnvFile = "$qm\.env"
if (Test-Path $qmEnvFile) {
    $qmEnv = Get-Content $qmEnvFile -Encoding UTF8
    $transport = ($qmEnv | Select-String "AUTH_EMAIL_TRANSPORT=(.+)").Matches[0].Groups[1].Value
    $allowlist = ($qmEnv | Select-String "AUTH_ALLOWED_EMAILS=(.+)").Matches[0].Groups[1].Value
    $resend = ($qmEnv | Select-String "RESEND_API_KEY=(.*)").Matches[0].Groups[1].Value
    $out += "transport: $transport"
    $out += "allowlist: $allowlist"
    $out += "RESEND_API_KEY set: $([bool]$resend)"
    if ($transport -eq "smtp") { Pass "email transport" "smtp (mailpit local — no external key needed)" }
} else { Fail "qm .env" "not found" }

# 8. Mailpit message count (evidence of the e2e magic-link flow)
try {
    $mp = Invoke-RestMethod -Uri "http://localhost:8025/api/v1/messages" -TimeoutSec 10
    Time "mailpit messages" 0 "total=$($mp.total)"
} catch { $out += "[NOTE] mailpit: $($_.Exception.Message)" }

$out | Out-File -FilePath "$w\runtime\audit5-qm-1010.txt" -Encoding utf8
Write-Output "AUDIT5 DONE"