$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg11.txt'
$msg = @"
chore(relocate): local bare mirror as interim insurance

The monorepo has no remote and a squashed history, so it is currently the only
copy of this content and cannot be reconstructed from pacgate-ai-pr. Created a
bare mirror at C:\backup-pacgate-law-mirror.git (18 MB) and verified it by
cloning it back: 14/14 commits, HEAD matches, 619 files restored including
Cargo.toml and compose.bundle.yaml.

This protects against accidental deletion or a bad git operation. It does NOT
protect against disk failure - it is on the same physical disk. A real remote
is still required.

Remote readiness assessed: github.com IS reachable from this machine (HTTP 200,
VPN up), but `gh auth status` reports not logged in and no token is stored, so
a push needs authentication before it can happen. Options recorded in
runtime/relocate/REMOTE-OPTIONS.txt.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline -1
