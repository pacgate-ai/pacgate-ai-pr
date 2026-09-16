$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = Join-Path $repo 'pacgate-ai'
$new  = Join-Path $repo 'pacgate-ai-assets'
$out  = Join-Path $repo 'runtime\relocate\RECOVERY.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RECOVERY: finish the interrupted pacgate-ai -> pacgate-ai-assets move'
A ('=' * 62)
A ''
A 'Cause: `Move-Item <dir> <dest>` moved the loose top-level files and .git, then'
A 'failed with "cannot delete pacgate-ai\.git - insufficient access". Move-Item'
A 'does not fail atomically, so the source was left PARTIALLY moved: the'
A 'subdirectories (assets, pacgate-ai) stayed behind. Nothing was lost.'
A ''
A 'Fix: move the stragglers with robocopy /MOVE (robust; handles the locked'
A '.git directory that Move-Item choked on), then drop the empty leftovers.'

function Stat($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 'ABSENT' }
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
    return "files=$($f.Count) MB=$mb"
}

A "`n=== BEFORE ==="
A ("  pacgate-ai        : " + (Stat $old))
A ("  pacgate-ai-assets : " + (Stat $new))

# ---- 1. move the stragglers -------------------------------------------------
A "`n=== 1. Move stragglers with robocopy /MOVE ==="
foreach ($sub in @('assets', 'pacgate-ai')) {
    $s = Join-Path $old $sub
    $d = Join-Path $new $sub
    if (-not (Test-Path -LiteralPath $s)) { A "  $sub : not present, skip"; continue }
    if (Test-Path -LiteralPath $d)        { A "  $sub : ALREADY at destination, skip"; continue }

    & robocopy $s $d /E /MOVE /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    # robocopy 0-7 = success
    $ok = $rc -lt 8
    A ("  {0,-12} move rc={1} -> {2}" -f $sub, $rc, $(if ($ok) { 'OK' } else { 'FAILED' }))
    if (-not $ok) { A "  ABORT: robocopy failed moving $sub" }
}

# ---- 2. remove the locked empty .git ---------------------------------------
A "`n=== 2. Remove the empty leftover .git ==="
$git = Join-Path $old '.git'
if (Test-Path -LiteralPath $git) {
    $n = @(Get-ChildItem -LiteralPath $git -Recurse -Force -ErrorAction SilentlyContinue).Count
    A "  entries in stray .git: $n"
    if ($n -eq 0) {
        # clear any read-only/system/hidden attribute, then remove
        & cmd /c "attrib -r -s -h `"$git`" /s /d" 2>&1 | Out-Null
        Remove-Item -LiteralPath $git -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $git) {
            & cmd /c "rmdir /s /q `"$git`"" 2>&1 | Out-Null
        }
        A ("  removed: " + (-not (Test-Path -LiteralPath $git)))
    } else {
        A "  !! stray .git is NOT empty - STOP and inspect manually"
    }
} else { A '  (no stray .git)' }

# ---- 3. remove the now-empty source dir ------------------------------------
A "`n=== 3. Remove the emptied pacgate-ai dir ==="
if (Test-Path -LiteralPath $old) {
    $left = @(Get-ChildItem -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue)
    A "  entries remaining: $($left.Count)"
    if ($left.Count -eq 0) {
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        A ("  removed: " + (-not (Test-Path -LiteralPath $old)))
    } else {
        A '  !! not empty - listing for inspection:'
        $left | Select-Object -First 15 | ForEach-Object { A ("      " + $_.FullName.Substring($repo.Length)) }
    }
} else { A '  (already gone)' }

# ---- 4. verify -------------------------------------------------------------
A "`n=== AFTER ==="
A ("  pacgate-ai        : " + (Stat $old))
A ("  pacgate-ai-assets : " + (Stat $new))

A "`n=== 4. Submodule repo still healthy? ==="
$head = (& git -C $new rev-parse --short HEAD 2>$null) -join ''
A ("  HEAD    : " + $head)
$dirty = @(& git -C $new status --porcelain 2>&1)
A ("  changes : {0}" -f $dirty.Count)
foreach ($d in ($dirty | Select-Object -First 12)) { A ("    " + $d) }

A "`n=== 5. Expected content present? ==="
foreach ($p in @('assets', 'pacgate-ai', '.gitignore', 'AGENTS.md', 'DEER-FLOW-INTEGRATION.md')) {
    A ("  {0,-26} {1}" -f $p, (Test-Path -LiteralPath (Join-Path $new $p)))
}

$total = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue).Count
A "`n  total files under pacgate-ai-assets: $total  (pre-move baseline was 262)"

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
