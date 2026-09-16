$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg3.txt'
$msg = @"
refactor(relocate): make the platform location-independent

Task 2 of the relocation. The platform now works from any checkout path.

Findings that changed the plan:
  - The bind mounts are RELATIVE (./data:/data, ./patches/...:...), not
    absolute. Compose resolves them against the compose file's own directory,
    so they follow the move automatically. The plan's premise that the stack
    "bind-mounts absolute paths under C:\pacgate-ai-pr" was WRONG -- verified
    by reading compose.bundle.yaml and by the live container labels.
  - Only 2 functional files referenced the old path, both in stale comments
    (build-images.ps1, build-frontend.ps1). Their code already used
    `$PSScriptRoot`, so they were location-agnostic already.
  - No compose file, .env, or runtime config contained the old path.

Changes:
  - build-images.ps1 / build-frontend.ps1: comment no longer names a machine
  - 6 handbooks/plans: C:\pacgate-ai-pr -> <monorepo>\pacgate-ai, so the
    instructions are correct on this machine, machine #2 and the developer's
    clone alike (20 replacements)

Safety: only the drive-letter form was replaced, so GitHub URLs such as
github.com/JZKK720/pacgate-ai-pr were left untouched (verified 0 damaged).
Files were rewritten via raw bytes + UTF-8, never Get-Content, to avoid the
GBK double-encoding trap; verified 0 mojibake.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline -3
