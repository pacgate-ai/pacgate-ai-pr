param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# Why are two CJK files missing from checkout-index output, when the total
# count matched (515/515)?
#
# Hypothesis: these paths are NOT actually tracked. `checkout-index -a` writes
# the INDEX, and the working tree may contain untracked files whose count
# coincidentally matches. Test by asking git directly, byte-safely.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\WHY-MISSING.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('WHY ARE THESE TWO FILES MISSING FROM checkout-index?')
$r.Add('=' * 62)
$r.Add('')

# Build the paths from code points (CJK literals in a BOM-less .ps1 get mangled).
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
$f1name = (ConvertFrom-CodePoints @(0x9879,0x76EE,0x65F6,0x95F4,0x7EBF,0x4E0E,0x5173,0x952E,0x8282,0x70B9)) + '.pdf'
$f2name = 'Pacgate_AI_Phase1_' + (ConvertFrom-CodePoints @(0x6280,0x672F,0x65B9,0x4E66,0x9762,0x6F84,0x6E05,0x95EE,0x9898,0x6E05,0x5355)) + '.docx'

$rel1 = 'docs/progress-reportcard/' + $f1name
$rel2 = 'docs/assets/q&a/' + $f2name

# --- Is each path TRACKED?  Use `git ls-files --error-unmatch`, byte-safe.
foreach ($pair in @(@{L='progress-reportcard pdf'; P=$rel1}, @{L='q&a docx'; P=$rel2})) {
    $r.Add("=== $($pair.L) ===")
    $r.Add("  path: $($pair.P)")

    $tracked = & git -C $src ls-files --error-unmatch -- $pair.P 2>&1
    $isTracked = ($LASTEXITCODE -eq 0)
    $r.Add("  tracked in git index : $isTracked")
    if (-not $isTracked) { $r.Add("      git says: $tracked") }

    # Present on disk?
    $onDisk = Test-Path -LiteralPath (Join-Path $src ($pair.P -replace '/','\'))
    $r.Add("  present on disk      : $onDisk")

    # If tracked, is it in the index only (assume-unchanged / skip-worktree)?
    if ($isTracked) {
        $ls = & git -C $src ls-files -v -- $pair.P 2>$null
        $r.Add("  index status flag    : $ls   (h=normal, S=skip-worktree, h+ assume-unchanged)")
    }

    # Is it ignored?
    $ign = & git -C $src check-ignore -v -- $pair.P 2>$null
    $r.Add("  ignored              : $(if ($ign) { $ign } else { 'no' })")
    $r.Add('')
}

# --- Count-based sanity: how many tracked files live under each dir?
$r.Add('=== tracked file counts under the two directories ===')
foreach ($d in @('docs/progress-reportcard', 'docs/assets')) {
    $n = @(& git -C $src -c core.quotepath=false ls-files -- $d 2>$null).Count
    $r.Add("  $d : $n tracked")
}
$r.Add('')

# --- The real question: does the SET of index entries match the working tree?
$r.Add('=== index vs working tree ===')
$idxCount = @(& git -C $src ls-files 2>$null).Count
$r.Add("  files in index        : $idxCount")
$r.Add("  files extracted by CI : 515 (measured earlier)")
$r.Add('')
$r.Add('  If these differ, some files are in the working tree but NOT tracked,')
$r.Add('  which explains missing files without any extraction bug.')
$r.Add('')

# --- Are these two specific files UNTRACKED (i.e. new local files)?
$r.Add('=== are they untracked local files? ===')
foreach ($pair in @(@{L='progress-reportcard pdf'; P=$rel1}, @{L='q&a docx'; P=$rel2})) {
    $status = & git -C $src status --porcelain -- $pair.P 2>&1
    $r.Add("  $($pair.L): status='$status'  ('??' = untracked)")
}
$r.Add('')
$r.Add('  NOTE: `git archive HEAD` and `checkout-index` both reflect the INDEX.')
$r.Add('  Untracked working-tree files are NOT included by either method.')
$r.Add('  => Files that exist on disk but were never committed simply do not move,')
$r.Add('     with either method. That is correct behaviour, not a bug.')

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"