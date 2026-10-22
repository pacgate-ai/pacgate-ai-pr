# Backup runtime state before 0.1.25 upgrade — 2026-10-09
# Mirrors the 0.1.24 backup pattern (runtime/backup-pre-0.1.24-20261007/)
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$dst = "$w\runtime\backup-pre-0.1.25-20261009"
New-Item -ItemType Directory -Path $dst -Force | Out-Null
$out = @()
function Add-Section($title) { $script:out += ""; $script:out += "=== $title ===" }

function Copy-File($src, $name) {
    if (Test-Path $src) {
        $bytes = [System.IO.File]::ReadAllBytes($src)
        [System.IO.File]::WriteAllBytes("$dst\$name", $bytes)
        $script:out += "backed up: $name ($($bytes.Length)B)"
    } else { $script:out += "MISSING: $src" }
}

# 1. Config files (byte-level, UTF-8 safe)
Copy-File "$cb\.env" "client-bundle.env"
Copy-File "$cb\deer-flow-extensions-config.json" "deer-flow-extensions-config.json"
Copy-File "$cb\deer-flow-config.yaml" "deer-flow-config.yaml"
Copy-File "$cb\compose.bundle.yaml" "compose.bundle.yaml"
Copy-File "$cb\compose.prod.yaml" "compose.prod.yaml"
Copy-File "$cb\nginx\default.conf" "nginx-default.conf"

# 2. deerflow.db (shared-read copy past SQLite lock)
Copy-File "$cb\data\deer-flow\deerflow.db" "deerflow.db"

# 3. Current container state snapshot
Add-Section "CONTAINER SNAPSHOT"
$script:out += docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" | Out-String

# 4. Current image IDs
Add-Section "IMAGE IDs (pre-upgrade)"
$script:out += docker inspect deer-flow pacgate-api pacgate-mcp deer-flow-frontend ocr-service --format "{{.Name}} {{.Image}}" | Out-String

# 5. DB row counts (read-only sanity)
Add-Section "DB SANITY (tenants/users)"
try {
    $dbOut = docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select (select count(*) from tenants) as tenants, (select count(*) from users) as users;" 2>&1
    $script:out += $dbOut
} catch { $script:out += "DB check failed: $($_.Exception.Message)" }

$out | Out-File -FilePath "$dst\BACKUP-MANIFEST.txt" -Encoding utf8
Write-Output "BACKUP DONE -> $dst"
Get-ChildItem $dst | ForEach-Object { Write-Output "$($_.Name) $($_.Length)B" }
