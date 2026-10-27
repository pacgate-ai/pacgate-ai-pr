# Classify each of the 16 files changed by 86a9feb..upstream/main against our
# local subtree, so we know which need a MERGE (local delta exists) vs a clean
# swap. Read-only.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$git = 'C:\Program Files\Git\cmd\git.exe'

function Test-Blob([string]$rev, [string]$path) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = & $git cat-file -e ("{0}:{1}" -f $rev, $path) 2>&1 }
    finally { $ErrorActionPreference = $prevEap }
    return ($LASTEXITCODE -eq 0)
}
function Get-Blob([string]$rev, [string]$path) { return (& $git rev-parse ("{0}:{1}" -f $rev, $path)).Trim() }

# Files changed upstream between our adopted base and upstream/main.
$changed = (& $git -c core.quotepath=false diff --name-only 86a9feb..upstream/main) |
Where-Object { $_ -ne '' }

$merge = @(); $clean = @(); $new = @()
foreach ($f in $changed) {
    $localPath = "pacgate-ai/$f"
    $hasLocal = Test-Blob 'HEAD' $localPath
    $hasBase = Test-Blob '86a9feb' $f

    if (-not $hasBase) {
        # Upstream ADDS this file; we may or may not already have it.
        if ($hasLocal) { $merge += "$f  (upstream adds; we already have a local copy)" }
        else { $new += $f }
        continue
    }
    if (-not $hasLocal) { $new += "$f  (absent locally)"; continue }

    $l = Get-Blob 'HEAD' $localPath
    $b = Get-Blob '86a9feb' $f
    if ($l -eq $b) { $clean += $f }
    else { $merge += "$f  (LOCAL DELTA - must merge, not overwrite)" }
}

'=== CLEAN (local == adopted base; upstream change applies directly) ==='
if ($clean.Count -eq 0) { '  (none)' } else { $clean | ForEach-Object { '  ' + $_ } }

''
'=== NEW (upstream adds; no local copy) ==='
if ($new.Count -eq 0) { '  (none)' } else { $new | ForEach-Object { '  ' + $_ } }

''
'=== MERGE REQUIRED (local delta present) ==='
if ($merge.Count -eq 0) { '  (none)' } else { $merge | ForEach-Object { '  ' + $_ } }

''
"clean=$($clean.Count) new=$($new.Count) merge=$($merge.Count) total=$($changed.Count)"
