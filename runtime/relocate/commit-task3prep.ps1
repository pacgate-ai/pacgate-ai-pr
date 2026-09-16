$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg5.txt'
$msg = @"
feat(relocate): fix the compose name defect and add the cutover script

Two pieces of preparation for the cutover (Task 3), both non-destructive.

1. compose.prod.yaml was missing its `name:` key. Compose would have derived
   the project name from the directory ("client-bundle"), prefixing named
   volumes differently and attaching the stack to a DIFFERENT, EMPTY database
   volume -- presenting as data loss while the real data sat untouched in
   pacgate-ai-bundle_pacgate-db-data. Both compose files now declare
   `name: pacgate-ai-bundle`; verified they resolve identically.

   This is a pre-existing latent defect, not caused by the move, but the move
   is the right moment to fix it.

2. task3-cutover.ps1 -- the downtime step, dry-run by default. Stops the stack
   from the OLD location, copies the ~1.9 GB of runtime state that git does not
   carry (data/, openviking/, .env, deer-flow-extensions-config.json,
   qm node_modules), restarts from the NEW location, then verifies the stack
   attached to the authoritative volume and that the DB actually answers.

   The runtime-state copy is the gap Phase 1 could not cover: git carries only
   tracked content, and the stack needs 1,915.7 MB of gitignored state that
   currently exists only at the old path. It is copied AFTER the stop so the
   1.6 GB checkpoints.db is not captured mid-write.

Also fixes a variable-collision bug found while writing the verifier: a loop
variable named `$l` silently aliases `$L` because PowerShell is
case-insensitive, which destroyed the results list.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline
