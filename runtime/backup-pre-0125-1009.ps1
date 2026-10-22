# Backup runtime state before 0.1.25 upgrade (2026-10-09)
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$cb = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$qm = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'
$dst = Join-Path $repo 'runtime\backup-pre-0.1.25-20261009'
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# 1. Critical rendered configs (byte-level copy, encoding-safe)
$critical = @(
    'deer-flow-extensions-config.json',
    'deer-flow-config.yaml',
    '.env',
    'compose.bundle.yaml',
    'compose.prod.yaml',
    'nginx\default.conf'
)
foreach ($f in $critical) {
    $src = Join-Path $cb $f
    if (Test-Path $src) {
        $rel = $f -replace '\\', '__'
        $bytes = [System.IO.File]::ReadAllBytes($src)
        [System.IO.File]::WriteAllBytes((Join-Path $dst $rel), $bytes)
        Write-Output ("BACKED UP: " + $f + " (" + $bytes.Length + " bytes)")
    } else {
        Write-Output ("MISSING: " + $f)
    }
}

# 2. deerflow.db (shared-read copy past SQLite lock)
$db = Join-Path $cb 'data\deer-flow\deerflow.db'
if (Test-Path $db) {
    $bytes = [System.IO.File]::ReadAllBytes($db)
    [System.IO.File]::WriteAllBytes((Join-Path $dst 'deerflow.db'), $bytes)
    Write-Output ("BACKED UP: deerflow.db (" + $bytes.Length + " bytes)")
}

# 3. qm .env
$qmEnv = Join-Path $qm '.env'
if (Test-Path $qmEnv) {
    $bytes = [System.IO.File]::ReadAllBytes($qmEnv)
    [System.IO.File]::WriteAllBytes((Join-Path $dst 'qm__env'), $bytes)
    Write-Output ("BACKED UP: qm .env (" + $bytes.Length + " bytes)")
}

# 4. DB row counts (via docker exec)
$counts = docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select 'tenants=' || count(*) from tenants; select 'users=' || count(*) from users; select 'documents=' || count(*) from documents;" 2>&1
$counts | Out-File -Encoding utf8 (Join-Path $dst 'db-counts.txt')
Write-Output "DB COUNTS:"
Write-Output $counts
Write-Output "DONE"