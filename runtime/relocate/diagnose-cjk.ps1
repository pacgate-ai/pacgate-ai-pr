param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# Diagnose the CJK count mismatch (got=54, want=59).
#
# The "want" value came from `git ls-files` piped through PowerShell, which
# decodes git's UTF-8 stdout as GBK on this machine -> mojibake -> the count is
# NOT trustworthy. Compare FILESYSTEM to FILESYSTEM instead: that is accurate
# because .NET already handles the paths correctly.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$work = 'C:\temp\cjkdiag'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\CJK-DIAGNOSIS.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('CJK EXTRACTION VERIFICATION (filesystem vs filesystem)')
$r.Add('')

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# --- extract via checkout-index (the chosen method)
$prefix = $stage.TrimEnd('\') + '\'
& git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | Out-Null

# --- ground truth from the SOURCE working tree, limited to tracked paths.
#     We build the tracked list from git but only use it to FILTER filesystem
#     entries, so name decoding never matters.
$trackedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($t in @(& git -C $src -c core.quotepath=false ls-files 2>$null)) {
    $trackedSet.Add(($t -replace '/','\')) | Out-Null
}

$r.Add("tracked entries (git, may be mojibake): $($trackedSet.Count)")
$r.Add('')

# Source-side CJK count, taken from the FILESYSTEM (accurate Unicode).
$srcCjk = New-Object System.Collections.Generic.List[string]
foreach ($f in (Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\pacgate-ai\target\*') { continue }
    if ($f.FullName -like '*\deploy\deer-flow-src\*') { continue }
    if ($f.FullName -like '*\.git\*') { continue }
    if ($f.FullName -like '*\node_modules\*') { continue }
    if ($f.Name -match '[^\x00-\x7F]') { $srcCjk.Add($f.FullName) }
}
$r.Add("SOURCE working tree, files with non-ASCII names (excluding target/, deer-flow-src/, .git/): $($srcCjk.Count)")

# Stage-side CJK count.
$stgCjk = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '[^\x00-\x7F]' })
$r.Add("STAGE, files with non-ASCII names: $($stgCjk.Count)")
$r.Add('')

# The meaningful comparison: are all TRACKED cjk files present in the stage?
$trackedCjk = @($srcCjk | Where-Object { $trackedSet.Contains($_.Substring($src.Length + 1)) })
$r.Add("of those, actually TRACKED by git: $($trackedCjk.Count)")
$r.Add("stage non-ASCII count            : $($stgCjk.Count)")
$r.Add('')
$r.Add("=> If these two match, extraction is complete and the earlier 54-vs-59")
$r.Add("   mismatch was purely a git-output decoding artifact, not data loss.")
$r.Add('')

# Show a few stage-side CJK names (proves real CJK survived)
$r.Add('sample CJK files present in stage:')
foreach ($f in ($stgCjk | Select-Object -First 8)) {
    $r.Add("    $($f.Name)")
}

$r.Add('')
$r.Add('sample TRACKED CJK files from source:')
foreach ($f in ($trackedCjk | Select-Object -First 8)) {
    $r.Add("    $(Split-Path $f -Leaf)")
}

$match = ($trackedCjk.Count -eq $stgCjk.Count)
$r.Add('')
$r.Add('=' * 58)
$r.Add("VERDICT: $(if ($match) { 'COMPLETE - no CJK data loss' } else { 'MISMATCH - investigate' })")
$r.Add('=' * 58)

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "wrote $out"
Write-Output "  trackedCJK=$($trackedCjk.Count)  stageCJK=$($stgCjk.Count)"