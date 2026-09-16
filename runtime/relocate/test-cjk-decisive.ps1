param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# DECISIVE CJK TEST
#
# Rather than count non-ASCII names (which is confounded by mojibake), test the
# ACTUAL question: are the specific files that tar.exe DROPPED present when we
# use checkout-index?
#
# Method: extract with tar, then extract with checkout-index, and diff the two
# filesystems. Any file present in checkout-index but missing from tar is proof
# that tar silently lost data.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$work = 'C:\temp\cjkcmp'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\CJK-DECISIVE-TEST.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('DECISIVE CJK TEST: tar.exe vs checkout-index (filesystem diff)')
$r.Add('=' * 66)
$r.Add('')

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

$tarDir = Join-Path $work 'via-tar'
$ciDir  = Join-Path $work 'via-checkoutindex'
New-Item -ItemType Directory -Path $tarDir -Force | Out-Null
New-Item -ItemType Directory -Path $ciDir  -Force | Out-Null

# --- extract via tar
$tar = Join-Path $work 'src.tar'
& git -C $src archive --format=tar HEAD -o $tar 2>$null
& tar -xf $tar -C $tarDir 2>$null

# --- extract via checkout-index
$prefix = $ciDir.TrimEnd('\') + '\'
& git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | Out-Null

# --- build relative path sets (filesystem-derived names, accurate Unicode)
function Get-RelSet([string]$root) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\')
        $set.Add($rel) | Out-Null
    }
    return $set
}

$tarSet = Get-RelSet $tarDir
$ciSet  = Get-RelSet $ciDir

$r.Add("files via tar.exe         : $($tarSet.Count)")
$r.Add("files via checkout-index  : $($ciSet.Count)")
$r.Add('')

# files in checkout-index but NOT in tar == silently dropped by tar
$dropped = New-Object System.Collections.Generic.List[string]
foreach ($p in $ciSet) { if (-not $tarSet.Contains($p)) { $dropped.Add($p) } }

# files in tar but not in checkout-index == should not exist
$extra = New-Object System.Collections.Generic.List[string]
foreach ($p in $tarSet) { if (-not $ciSet.Contains($p)) { $extra.Add($p) } }

$r.Add("DROPPED by tar.exe (present in checkout-index, missing from tar): $($dropped.Count)")
foreach ($d in ($dropped | Sort-Object | Select-Object -First 20)) { $r.Add("    $d") }
if ($dropped.Count -gt 20) { $r.Add("    ... and $($dropped.Count - 20) more") }
$r.Add('')

$r.Add("EXTRA in tar (should be none): $($extra.Count)")
foreach ($e in ($extra | Sort-Object | Select-Object -First 10)) { $r.Add("    $e") }
$r.Add('')

# Are the dropped names non-ASCII?  (that would confirm the cause)
$droppedNonAscii = @($dropped | Where-Object { $_ -match '[^\x00-\x7F]' }).Count
$r.Add("of the dropped files, non-ASCII named: $droppedNonAscii of $($dropped.Count)")
$r.Add('')

$r.Add('=' * 66)
if ($dropped.Count -gt 0) {
    $r.Add("VERDICT: CONFIRMED. tar.exe silently drops $($dropped.Count) file(s).")
    $r.Add('         checkout-index is the correct extraction method.')
} else {
    $r.Add('VERDICT: tar.exe dropped nothing in this run; counts matched.')
}
$r.Add('=' * 66)

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "wrote $out"
Write-Output "  via tar=$($tarSet.Count)  via checkout-index=$($ciSet.Count)  dropped=$($dropped.Count)"