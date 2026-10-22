# Backup deerflow.db via SQLite shared-read (FileShare.ReadWrite) - file is locked by the running container
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$dst = Join-Path $repo 'runtime\backup-pre-0.1.25-20261009'
$files = @(
    'data\deer-flow\data\deerflow.db',
    'data\deer-flow\data\checkpoints.db'
)
foreach ($f in $files) {
    $src = Join-Path $repo ('pacgate-ai\deploy\client-bundle\' + $f)
    $rel = $f -replace '\\', '__'
    $out = Join-Path $dst $rel
    $fsIn = [System.IO.FileStream]::new($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $fsOut = [System.IO.FileStream]::new($out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $fsIn.CopyTo($fsOut)
    $fsOut.Close(); $fsIn.Close()
    Write-Output ("BACKED UP: " + $f + " (" + (Get-Item $out).Length + " bytes)")
}
Write-Output DONE