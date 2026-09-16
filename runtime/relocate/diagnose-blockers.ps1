param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# BLOCKER DIAGNOSIS
#   FAIL 1: only 478 of 515 tracked files extracted -> Windows `tar` cannot
#           write CJK filenames ("Invalid empty pathname").
#   FAIL 2: the archive DOES contain credential files -> the vendored assets
#           tree inside pacgate-ai/ carries them.
#
# This script (a) tests alternative extraction methods and (b) confirms
# exactly which credential files the archive carries. No repo mutation.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\BLOCKER-DIAGNOSIS.txt'
$work = 'C:\temp\blkdiag'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('BLOCKER DIAGNOSIS')
$r.Add("run at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$r.Add('')

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

# ---------------------------------------------------------------------------
# (A) How many tracked files have non-ASCII names?
# ---------------------------------------------------------------------------
$r.Add('=== A. How many tracked files have non-ASCII (CJK) names? ===')
$tracked = @(& git -C $src -c core.quotepath=false ls-files 2>$null)
$nonAscii = @($tracked | Where-Object { $_ -match '[^\x00-\x7F]' })
$r.Add("  total tracked : $($tracked.Count)")
$r.Add("  non-ASCII     : $($nonAscii.Count)")
$r.Add('')
$r.Add('  examples:')
foreach ($f in ($nonAscii | Select-Object -First 5)) {
    $leaf = ($f -split '/')[-1]
    $r.Add("      $leaf")
}
$r.Add('')

# ---------------------------------------------------------------------------
# (B) Test alternative extraction methods on the CJK problem
# ---------------------------------------------------------------------------
$r.Add('=== B. Extraction method comparison ===')
$r.Add('')

# --- method 1: Windows tar (known failing) ---
$r.Add('  --- B1. tar.exe (system bsdtar) ---')
$k1 = 'B1-tar'
$d1 = Join-Path $work $k1
New-Item -ItemType Directory -Path $d1 -Force | Out-Null
$tar = Join-Path $work 'src.tar'
& git -C $src archive --format=tar HEAD -o $tar 2>$null
$e1 = & tar -xf $tar -C $d1 2>&1
$c1 = @(Get-ChildItem $d1 -Recurse -File -Force -ErrorAction SilentlyContinue).Count
$r.Add("      extracted: $c1 / $($tracked.Count)   $(if ($c1 -eq $tracked.Count) { 'OK' } else { 'INCOMPLETE' })")
$r.Add('')

# --- method 2: git checkout-index ---
$r.Add('  --- B2. git checkout-index (writes tracked files directly) ---')
$d2 = Join-Path $work 'B2-checkoutindex'
New-Item -ItemType Directory -Path $d2 -Force | Out-Null
$prefix = $d2.TrimEnd('\') + '\'
& git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | ForEach-Object { if ($_ -notmatch '^\s*$') { $r.Add("      $_") } }
$c2 = @(Get-ChildItem $d2 -Recurse -File -Force -ErrorAction SilentlyContinue).Count
$r.Add("      extracted: $c2 / $($tracked.Count)   $(if ($c2 -eq $tracked.Count) { 'OK' } else { 'INCOMPLETE' })")
$r.Add('')

# --- method 3: Python tarfile (explicit UTF-8 handling) ---
$r.Add('  --- B3. Python tarfile ---')
$d3 = Join-Path $work 'B3-python'
New-Item -ItemType Directory -Path $d3 -Force | Out-Null
$py = 'C:\Program Files\Python313\python.exe'
if (Test-Path -LiteralPath $py) {
    $script = Join-Path $work 'extract.py'
    $code = @'
import tarfile, sys, os
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
n = 0
with tarfile.open(src, "r:") as t:
    for m in t.getmembers():
        try:
            t.extract(m, dst)
            if m.isfile():
                n += 1
        except Exception as e:
            print("SKIP", m.name, e, file=sys.stderr)
print("EXTRACTED", n)
'@
    [System.IO.File]::WriteAllText($script, $code, (New-Object System.Text.UTF8Encoding($false)))
    $res = & $py $script $tar $d3 2>&1
    foreach ($x in $res) { $r.Add("      $x") }
} else { $r.Add('      python not found') }
$c3 = @(Get-ChildItem $d3 -Recurse -File -Force -ErrorAction SilentlyContinue).Count
$r.Add("      extracted: $c3 / $($tracked.Count)   $(if ($c3 -eq $tracked.Count) { 'OK' } else { 'INCOMPLETE' })")
$r.Add('')

# --- method 4: robocopy from the WORKING TREE (only tracked files) ---
$r.Add('  --- B4. robocopy from working tree (copying only tracked paths) ---')
$d4 = Join-Path $work 'B4-robocopy'
New-Item -ItemType Directory -Path $d4 -Force | Out-Null
$copied = 0; $failed = 0
foreach ($f in $tracked) {
    $s = Join-Path $src ($f -replace '/','\')
    $t = Join-Path $d4 ($f -replace '/','\')
    if (Test-Path -LiteralPath $s) {
        $td = Split-Path $t -Parent
        if (-not (Test-Path -LiteralPath $td)) { New-Item -ItemType Directory -Path $td -Force | Out-Null }
        try { Copy-Item -LiteralPath $s -Destination $t -Force; $copied++ } catch { $failed++ }
    } else { $failed++ }
}
$r.Add("      copied: $copied   failed: $failed   $(if ($copied -eq $tracked.Count) { 'OK' } else { 'INCOMPLETE' })")
$r.Add('')

# ---------------------------------------------------------------------------
# (C) Credential content inside the archive
# ---------------------------------------------------------------------------
$r.Add('=== C. Which credential files does the archive actually carry? ===')
$r.Add('')
$credPatterns = @('OPERATOR.md')
$hh = @($tracked | Where-Object { $_ -match 'OPERATOR\.md$' })
$r.Add("  tracked OPERATOR.md entries: $($hh.Count)")
foreach ($x in $hh) { $r.Add("      $x") }

# Any MCP授权 .md / docx anywhere in tracked set?  (CJK built from code points)
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
$g = ConvertFrom-CodePoints @(0x6388,0x6743)   # "authorization"
$mcpDir = 'MCP' + $g
$mcpHits = @($tracked | Where-Object { $_ -like "*$mcpDir*" })
$r.Add('')
# NOTE: use ${mcpDir} -- "$mcpDir:" would parse as a drive-qualified variable.
$r.Add("  tracked files under ${mcpDir}: $($mcpHits.Count)")
foreach ($x in $mcpHits) { $r.Add("      $($x -replace '/','/')") }

$r.Add('')
$r.Add('  => These ARE in the archive, because they are git-tracked in pacgate-ai-pr.')
$r.Add('     The migration MUST exclude them explicitly, not rely on absence.')
$r.Add('')

# ---------------------------------------------------------------------------
# (D) verdict
# ---------------------------------------------------------------------------
$r.Add('=== D. Verdict ===')
$r.Add('')
$best = @(
    @{ N = 'tar.exe';        C = $c1 },
    @{ N = 'checkout-index'; C = $c2 },
    @{ N = 'python tarfile'; C = $c3 },
    @{ N = 'robocopy';       C = $c4 = $copied }
) | Sort-Object { -$_.C }
foreach ($b in $best) { $r.Add(('  {0,-16} {1,5} / {2}' -f $b.N, $b.C, $tracked.Count)) }
$r.Add('')
$winner = $best[0]
$r.Add("  BEST METHOD: $($winner.N) ($($winner.C) of $($tracked.Count))")
if ($winner.C -eq $tracked.Count) {
    $r.Add('  => Use this method for the real migration.')
} else {
    $r.Add('  => No method extracted everything; investigate before proceeding.')
}

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "wrote $out"
Write-Output "  tar=$c1  checkout-index=$c2  python=$c3  robocopy=$copied  (of $($tracked.Count))"