$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg15.txt'
[System.IO.File]::WriteAllText($f, "chore(relocate): final state verification tooling`r`n", (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline -1
"uncommitted: $((& git -C $repo status --porcelain | Measure-Object -Line).Lines)"
"--- mirror refresh ---"
& git -C 'C:\backup-pacgate-law-mirror.git' fetch --all --prune
"mirror main: $(& git -C 'C:\backup-pacgate-law-mirror.git' rev-parse refs/heads/main)"
"repo   HEAD: $(& git -C $repo rev-parse HEAD)"