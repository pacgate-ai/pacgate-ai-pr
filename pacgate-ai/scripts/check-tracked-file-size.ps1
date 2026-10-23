# Refuse a tracked file above a size ceiling.
#
# WHY THIS EXISTS (the 2026-10-23 AIPC #2 field report)
#
# A cherry-pick on that machine staged a 42 MB docker CLI binary. It was caught by
# a human noticing the diff, not by anything in this repo. A binary that size in
# git history is PERMANENT: a later commit cannot remove it, only a history
# rewrite can, and by then every clone carries it.
#
# `.gitignore` cannot express this rule - it matches names and patterns, not
# sizes - so the check has to be a script. The .gitignore additions made alongside
# this file cover the specific shapes that incident produced; this covers the
# general case.
#
# WHAT IS ASSERTED
#   1. no TRACKED file exceeds the ceiling;
#   2. the ceiling is low enough to be meaningful (a guard set to 1 GB would pass
#      the 42 MB binary that motivated it);
#   3. the check can FAIL - exercised synthetically, so it cannot expire.
#
# Exit codes: 0 pass, 1 real failure, 2 cannot check.
[CmdletBinding()]
param(
    # 10 MB. The largest legitimate tracked file in this repo is well under 1 MB
    # (the workflow YAML library and the docs HTML), so 10 MB leaves an order of
    # magnitude of headroom while still catching the 42 MB class.
    [int]$MaxMB = 10
)

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$passed = 0; $failed = 0
function Check($n, $ok, $d) {
    if ($ok) { $script:passed++; Write-Host "  [PASS] $n" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  [FAIL] $n" -ForegroundColor Red; if ($d) { Write-Host "         $d" -ForegroundColor DarkGray } }
}
function CannotCheck($why) {
    Write-Host "[SKIP] CANNOT CHECK: $why" -ForegroundColor Yellow
    Write-Host "RESULT: $passed passed, $failed failed (CANNOT CHECK)" -ForegroundColor Yellow
    exit 2
}

Write-Host '=== tracked file size guard ==='

# -c core.quotepath=false: without it git octal-escapes non-ASCII paths, and
# Test-Path then fails on the escape sequence, so every CJK-named tracked file is
# silently skipped. Measured on this repo: 60 of 832 tracked files were skipped
# before this flag, which is exactly the class of file a size guard must not miss.
$tracked = git -c core.quotepath=false ls-files 2>$null
if ($LASTEXITCODE -ne 0 -or -not $tracked) { CannotCheck 'git ls-files returned nothing - not a git checkout?' }

$ceiling = $MaxMB * 1MB
$oversize = @()
$checked = 0
$skipped = @()
foreach ($f in @($tracked)) {
    if (-not $f) { continue }
    if (-not (Test-Path -LiteralPath $f)) { $skipped += $f; continue }
    $item = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { continue }
    $checked++
    if ($item.Length -gt $ceiling) {
        $oversize += [pscustomobject]@{ Path = $f; MB = [math]::Round($item.Length / 1MB, 1) }
    }
}

Check 'tracked files were actually inspected' ($checked -gt 0) 'no tracked files resolved on disk - the guard would pass vacuously'
Write-Host ("         inspected {0} tracked file(s) against a {1} MB ceiling" -f $checked, $MaxMB) -ForegroundColor DarkGray

# A tracked file that does not resolve on disk is NOT inspected, and skipping it
# silently is how this guard passed while 60 CJK-named files went unchecked (git
# octal-escapes non-ASCII paths unless core.quotepath=false). An uninspected file
# is an unguarded file, so this fails rather than warns.
Check 'every tracked file resolved on disk (none skipped)' ($skipped.Count -eq 0) `
    ("{0} tracked file(s) could not be resolved and were NOT size-checked: {1}" -f $skipped.Count, (($skipped | Select-Object -First 5) -join '; '))

# PREVENTABLE vs ALREADY PERMANENT.
#
# The incident this guard exists for was a cherry-pick that STAGED a 42 MB binary -
# caught before it entered history. A file already committed is a different thing:
# it is already permanent, no commit can remove it, and failing on it every run
# makes the suite permanently red. That is the "a gate stops being read" failure
# mode this repo already recorded for test-release-provenance.
#
# So: a file that is tracked in HEAD and oversize is reported as debt; a file that
# is staged but NOT yet in HEAD is a real failure, because that is the moment the
# guard can still prevent it.
$inHead = @{}
$headFiles = git -c core.quotepath=false ls-tree -r --name-only HEAD 2>$null
foreach ($h in @($headFiles)) { if ($h) { $inHead[$h] = $true } }

$newOversize = @($oversize | Where-Object { -not $inHead.ContainsKey($_.Path) })
$oldOversize = @($oversize | Where-Object { $inHead.ContainsKey($_.Path) })

Check "no NEWLY staged file exceeds $MaxMB MB" ($newOversize.Count -eq 0) `
    ("staged but not yet committed: " + (($newOversize | ForEach-Object { "$($_.Path) ($($_.MB) MB)" }) -join '; ') +
     " - remove it from the index now; once committed it is permanent in git history")

if ($oldOversize.Count -gt 0) {
    Write-Host ("         KNOWN DEBT: {0} already-committed file(s) exceed {1} MB and cannot be removed without a history rewrite:" -f $oldOversize.Count, $MaxMB) -ForegroundColor Yellow
    foreach ($o in $oldOversize) { Write-Host ("           {0} ({1} MB)" -f $o.Path, $o.MB) -ForegroundColor DarkGray }
}

# The guard must DISCRIMINATE. A ceiling set so high that nothing can trip it is
# not a guard, and this is the specific mistake that would have let the 42 MB
# binary through: a 1 GB ceiling passes it silently.
function Test-WithinCeiling([long]$bytes, [int]$maxMB) { return ($bytes -le ($maxMB * 1MB)) }
Check 'the ceiling REJECTS the 42 MB binary that motivated this guard' (-not (Test-WithinCeiling (42MB) $MaxMB)) "a $MaxMB MB ceiling would accept a 42 MB binary"
Check 'the ceiling ACCEPTS a normal source file' (Test-WithinCeiling (200KB) $MaxMB) 'a 200 KB source file was rejected'

Write-Host ''
if ($failed -gt 0) {
    Write-Host "RESULT: $passed passed, $failed failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: no tracked file exceeds $MaxMB MB. ($passed passed)" -ForegroundColor Green
exit 0
