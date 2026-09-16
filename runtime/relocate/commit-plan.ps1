$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg4.txt'
$msg = @"
docs(relocate): correct the plan's central premise after Phase 1

The plan asserted the stack bind-mounts ABSOLUTE paths under C:\pacgate-ai-pr
and that moving the directory would break it. That was wrong. Every mount in
compose.bundle.yaml is relative (./data:/data, ./patches/...:...), and Compose
resolves those against the compose file's own directory, so they follow the
move automatically. Confirmed against the live container labels too.

Records Task 1 and Task 2 as complete, and documents the two deviations that
reality forced:
  - Move-Item is not atomic on a directory containing .git; it left the move
    half-done. Recovered with robocopy /MOVE, 262 files = exact baseline.
  - pacgate-ai-assets/ and deer-flow/ are embedded repos, so git add would
    record phantom gitlinks. Both are ignored rather than embedded.

Also records the single-quoted '\\' scanning trap that produced a false
"0 hits" result.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline
