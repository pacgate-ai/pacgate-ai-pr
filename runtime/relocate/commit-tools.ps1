$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg2.txt'
[System.IO.File]::WriteAllText($f, "chore: phase 1 relocation tooling, evidence and recovery notes`n", (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline
& git -C $repo status --short
