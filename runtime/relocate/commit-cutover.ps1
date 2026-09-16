$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg6.txt'
$msg = @"
feat(relocate): cut the running stack over to the monorepo path

Task 3 complete. The stack now runs from
  pacgate-law\pacgate-ai\deploy\client-bundle\compose.bundle.yaml
  pacgate-law\pacgate-ai\deploy\qm-pacgate\compose.qm.yaml

Verified after the cutover:
  - 25 containers running, 0 restart loops
  - pacgate-db on pacgate-ai-bundle_pacgate-db-data (the authoritative volume)
  - 0 container mounts under C:\pacgate-ai-pr; 19 under pacgate-law
  - DB content intact: tenants=1, users=3, "Pacgate Law", 25 MB
  - checkpoints.db (1,635.7 MB) present at the new path and actively written
    (a -shm sidecar appeared during verification, proving a live rw mount)
  - 7/7 service endpoints responding; no error lines in api/deer-flow/nginx

Method: pre-copy the 1.9 GB of gitignored runtime state while the stack still
ran, then stop, then re-run robocopy so only files changed since the pre-copy
transfer. That makes the copy consistent (the 1.6 GB checkpoints.db is
re-copied after its writer stopped) while keeping downtime to seconds.

Two bugs found and fixed while doing this:
  - `$ErrorActionPreference='Stop'` plus a native command (docker) writing
    progress to STDERR raises NativeCommandError and aborts the script. Docker
    writes normal progress text to stderr, so this is not a real failure. The
    cutover aborted mid-way on `docker compose down`; recovered by resuming
    from the known state (stack down, pre-copy complete).
  - `$j | ConvertFrom-Json` returns a JSON array as a SINGLE object in
    PowerShell 5.1, so Where-Object treated 13 deer-flow mounts as one item and
    the mount count was wrong (1 instead of 13). Enumerate explicitly.

The old location is untouched and remains the rollback.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline | Select-Object -First 4
