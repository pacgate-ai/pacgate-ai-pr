$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg12.txt'
$msg = @"
fix(relocate): the backup mirror was silently going stale

Found a real defect in the mirror I created minutes earlier. `git clone --bare`
does NOT set a fetch refspec, so `git fetch --all` updated only FETCH_HEAD and
left refs/heads/main frozen. The mirror had already fallen behind the source
(fccebb0 vs a556ae2) - a backup that silently stops updating is worse than no
backup, because it looks like one.

Fix: recreate with `git clone --mirror`, which sets
  remote.origin.fetch = +refs/*:refs/*
so every fetch updates all refs.

Proved the fix rather than assuming it: made a throwaway commit in the source,
fetched, and confirmed the mirror followed it (96621e1 on both sides), then
reset the probe commit and confirmed they re-synced. Restore test clones back
624 files including Cargo.toml.

Also fixed a parse error in the script itself (an unterminated single-quoted
string containing a refspec).
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline -1
