# Was test-release-provenance.ps1 green BEFORE this adoption?
# The adoption is committed in HEAD, so a stash cannot revert it. Use a throwaway
# worktree at the pre-adoption commit instead.
$ErrorActionPreference = 'Stop'
$git = 'C:\Program Files\Git\cmd\git.exe'
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$wt = Join-Path $env:TEMP 'prov-check'

Remove-Item -Recurse -Force $wt -ErrorAction SilentlyContinue
& $git -C $repo worktree prune 2>&1 | Out-Null
# git writes "Preparing worktree" to stderr; under Stop that is terminating.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { & $git -C $repo worktree add --detach $wt HEAD~1 2>&1 | Out-Null }
finally { $ErrorActionPreference = $prevEap }

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    Push-Location (Join-Path $wt 'pacgate-ai')
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-release-provenance.ps1 2>&1
    $code = $LASTEXITCODE
    Pop-Location
}
finally { $ErrorActionPreference = $prevEap }

'=== provenance at HEAD~1 (before the loop-guard adoption) ==='
$out | Select-String -Pattern 'PASS|FAIL|provenance defect' | ForEach-Object { '  ' + "$_".Trim() }
"exit=$code"

& $git -C $repo worktree remove --force $wt 2>&1 | Out-Null
& $git -C $repo worktree prune 2>&1 | Out-Null
'worktree removed'
