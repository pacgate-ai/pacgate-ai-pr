param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# DEFINITIVE EXTRACTION AUDIT
#
# `data_dirs` discrepancy: the index reportedly has 515 entries and 515 files
# were extracted, yet at least one whole directory is absent. Enumerate both
# sides and diff them to find exactly what is missing and why.
#
# Both lists are written to files to avoid console/encoding interference.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$work = 'C:\temp\extaudit'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\EXTRACTION-AUDIT.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('DEFINITIVE EXTRACTION AUDIT')
$r.Add('=' * 60)
$r.Add('')

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# ---- extract
$prefix = $stage.TrimEnd('\') + '\'
& git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | Out-Null

# ---- side A: the INDEX, written by git to a file as raw bytes (-z, NUL separated)
$idxRaw = Join-Path $work 'index.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
$idxBytes = [System.IO.File]::ReadAllBytes($idxRaw)
$idxList = @([System.Text.Encoding]::UTF8.GetString($idxBytes) -split "`0" | Where-Object { $_ -ne '' })

# ---- side B: what actually landed on disk
$stageList = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force |
               ForEach-Object { $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/') })

$r.Add("index entries (git ls-files -z) : $($idxList.Count)")
$r.Add("files actually on disk         : $($stageList.Count)")
$r.Add('')

# ---- diff by ORDINAL comparison (no culture/normalization surprises)
$idxSet   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$stageSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($x in $idxList)   { $idxSet.Add($x) | Out-Null }
foreach ($x in $stageList) { $stageSet.Add($x) | Out-Null }

$missing = New-Object System.Collections.Generic.List[string]
foreach ($x in $idxList) { if (-not $stageSet.Contains($x)) { $missing.Add($x) } }

$extra = New-Object System.Collections.Generic.List[string]
foreach ($x in $stageList) { if (-not $idxSet.Contains($x)) { $extra.Add($x) } }

$r.Add("IN INDEX BUT NOT ON DISK : $($missing.Count)")
foreach ($m in ($missing | Sort-Object)) { $r.Add("    $m") }
$r.Add('')

$r.Add("ON DISK BUT NOT IN INDEX : $($extra.Count)")
foreach ($e in ($extra | Sort-Object | Select-Object -First 20)) { $r.Add("    $e") }
if ($extra.Count -gt 20) { $r.Add("    ... +$($extra.Count - 20) more") }
$r.Add('')

# ---- does the docs directory exist at all in the stage?
$r.Add('--- directory existence check ---')
foreach ($d in @('docs', 'docs/progress-reportcard', 'docs/assets', 'docs/assets/q&a')) {
    $p = Join-Path $stage ($d -replace '/','\')
    $r.Add(("  {0,-32} exists={1}" -f $d, (Test-Path -LiteralPath $p)))
}
$r.Add('')

# ---- what IS under docs in the stage?
$r.Add('--- contents of stage\docs (first 15) ---')
$dd = Join-Path $stage 'docs'
if (Test-Path -LiteralPath $dd) {
    foreach ($f in (Get-ChildItem -LiteralPath $dd -Force | Select-Object -First 15)) {
        $r.Add("    $(if ($f.PSIsContainer) { '[dir] ' } else { '[file]' }) $($f.Name)")
    }
} else { $r.Add('    docs\ MISSING ENTIRELY') }

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "AUDIT: index=$($idxList.Count) disk=$($stageList.Count) missing=$($missing.Count) extra=$($extra.Count)"
Write-Output "  wrote $out"