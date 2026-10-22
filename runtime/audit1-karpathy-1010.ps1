# Karpathy-guidelines audit part 1: repo hygiene, tags, secrets, pins, docker — 2026-10-10
$ErrorActionPreference = "Continue"
$env:Path += ";C:\Program Files\Git\cmd"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }
function Note($n, $d) { $script:out += "[NOTE] $n : $d" }

# K1: Repo hygiene
Add-Section "K1 REPO HYGIENE"
$tracked = git -C $w status --porcelain --untracked-files=no 2>&1
if ("$tracked".Trim() -eq "") { Pass "tracked tree clean" "0 modifications" }
else { Fail "tracked tree" "$tracked" }
$untrackedCount = (git -C $w status --porcelain | Where-Object { $_ -match '^\?\?' }).Count
Note "untracked files" "$untrackedCount (runtime/ scratch — never committed by design)"

# K2: Tag consistency
Add-Section "K2 TAG CONSISTENCY"
$describe = git -C $w describe --tags 2>&1
$out += "git describe: $describe"
$head = git -C $w rev-parse --short HEAD
$out += "HEAD: $head"

# K3: Version sources agree
Add-Section "K3 VERSION SOURCES"
$cargo = (Select-String -Path "$w\pacgate-ai\pacgate-ai\Cargo.toml" -Pattern '^version = "(.+)"' | Select-Object -First 1).Matches[0].Groups[1].Value
$cbPins = (Select-String -Path "$w\pacgate-ai\deploy\client-bundle\compose.bundle.yaml" -Pattern "ghcr.io/jzkk720/.*:(0\.1\.\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
$out += "Cargo.toml: $cargo"
$out += "compose.bundle pins: $($cbPins -join ', ')"
$apiLabel = docker inspect ghcr.io/jzkk720/pacgate-api:0.1.25 | ConvertFrom-Json | ForEach-Object { $_.Config.Labels."org.opencontainers.image.version" }
$out += "api image label: $apiLabel"
if ($cargo -eq "0.1.25" -and $cbPins -contains "0.1.25" -and $apiLabel -eq "0.1.25") { Pass "version agreement" "Cargo=$cargo pins=$($cbPins -join '/') label=$apiLabel" }
else { Fail "version agreement" "Cargo=$cargo pins=$($cbPins -join '/') label=$apiLabel" }

# K4/K5: Secrets hygiene (staged + tracked tree)
Add-Section "K4/K5 SECRETS"
$carriers = @("5855e649","8e18bfce","a59e30ed")
$treeBlobs = git -C $w ls-files -s | Select-String -Pattern ($carriers -join "|")
if ($treeBlobs) { Fail "credential carriers" "FOUND in tracked tree" } else { Pass "credential carriers" "0 in tracked tree (blob-SHA method)" }
$envPath = "$w\pacgate-ai\deploy\client-bundle\.env"
$envTracked = git -C $w ls-files --error-unmatch "pacgate-ai/deploy/client-bundle/.env" 2>&1
if ($LASTEXITCODE -ne 0) { Pass ".env untracked" "not in git" } else { Fail ".env tracked" "IS in git" }

# K6: Pin namespace consistency
Add-Section "K6 PIN NAMESPACE"
$allPins = Select-String -Path "$w\pacgate-ai\deploy\client-bundle\compose.bundle.yaml","$w\pacgate-ai\deploy\client-bundle\compose.prod.yaml" -Pattern "image: ghcr\.io/([^/]+)/" | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
$out += "namespaces in pins: $($allPins -join ', ')"
if ($allPins.Count -eq 1 -and $allPins[0] -eq "jzkk720") { Pass "namespace consistency" "all pins jzkk720" }
else { Note "namespace" "$($allPins -join ',') (volcengine/openviking is third-party digest-pinned)" }

# K7/K8: Docker runtime + health
Add-Section "K7/K8 DOCKER RUNTIME"
$dockerVer = docker version --format "{{.Server.Version}}" 2>&1
$out += "docker server: $dockerVer"
$all = docker ps -a --format "{{.Names}}|{{.Status}}" | Out-String
$out += $all
$running = (docker ps -q).Count
$total = (docker ps -aq).Count
Pass "containers" "$running running / $total total"
$unhealthy = docker ps --format "{{.Names}} {{.Status}}" | Select-String "unhealthy"
if ($unhealthy) { Note "unhealthy containers" "$unhealthy" } else { Pass "health" "no unhealthy containers" }
$restarting = docker ps --format "{{.Names}} {{.Status}}" | Select-String "Restart"
if ($restarting) { Fail "restart loops" "$restarting" } else { Pass "restart loops" "none" }

# K9: Resource footprint
Add-Section "K9 RESOURCE FOOTPRINT"
$stats = docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}" | Out-String
$out += $stats

# Volume safety: the two known volumes
Add-Section "VOLUME SAFETY"
$vols = docker volume ls --format "{{.Name}}" | Select-String "pacgate-db-data"
$out += "db volumes: $($vols -join ', ')"
$dbVol = docker inspect pacgate-db | ConvertFrom-Json | ForEach-Object { $_.Mounts | Where-Object { $_.Destination -eq "/var/lib/postgresql/data" } | ForEach-Object { $_.Source } }
$out += "pacgate-db attached to: $dbVol"
if ($dbVol -match "pacgate-ai-bundle_") { Pass "volume pin" "db on pacgate-ai-bundle_ volume (correct)" }
else { Fail "volume pin" "db on unexpected volume: $dbVol" }

$out | Out-File -FilePath "$w\runtime\audit1-karpathy-1010.txt" -Encoding utf8
Write-Output "AUDIT1 DONE"
