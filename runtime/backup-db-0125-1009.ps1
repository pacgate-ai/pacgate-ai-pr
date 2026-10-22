# Backup deerflow.db + checkpoints.db (shared-read byte copy)
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$dst = Join-Path $repo 'runtime\backup-pre-0.1.25-20261009'
$files = @(
    'data\deer-flow\data\deerflow.db',
    'data\deer-flow\data\checkpoints.db',
    'data\deer-flow\.jwt_secret'
)
foreach ($f in $files) {
    $src = Join-Path $repo ('pacgate-ai\deploy\client-bundle\' + $f)
    if (Test-Path $src) {
        $rel = $f -replace '\\', '__'
        $bytes = [System.IO.File]::ReadAllBytes($src)
        [System.IO.File]::WriteAllBytes((Join-Path $dst $rel), $bytes)
        Write-Output ("BACKED UP: " + $f + " (" + $bytes.Length + " bytes)")
    } else {
        Write-Output ("MISSING: " + $f)
    }
}
Write-Output DONE