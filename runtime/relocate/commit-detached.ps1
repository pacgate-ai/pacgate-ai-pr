$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg10.txt'
$msg = @"
chore(relocate): detached runner for the deer-flow builds

The first deer-flow build attempt was KILLED when its task terminal closed,
losing ~40 minutes of apt downloads. Relaunched via Start-Process so the build
survives independently of any terminal, with a .done marker file to poll.

Also records the HTTP proof for the Rust image: the locally built
pacgate-api:local-verify was run on the live pacgate-ai-bundle_default network
against the real pacgate-db and served 4/4 endpoints (HTTP 401 = the auth
middleware working as intended), after logging
"Connected to database" -> "Migrations applied" -> "RAG store initialized"
-> "Listening on http://0.0.0.0:8080".
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline | Select-Object -First 3
