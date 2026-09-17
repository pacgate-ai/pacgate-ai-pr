$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\BUNDLE-DECISIVE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'DECISIVE TEST: is the object PRESENT, or is it ABSENT from the backup?'
A ('=' * 78)
A ''
A 'This distinguishes two very different claims:'
A '  (a) the commit OBJECT is not in the bundle          -> data LOSS'
A '  (b) the object IS in the bundle, but a fresh clone does not create a'
A '      local REF pointing at it                        -> no loss at all'
A ''
A '`rev-list --all` only walks LOCAL refs, so it answers neither on its own.'
A '`git cat-file -e` asks about the object database directly. That is the'
A 'question that matters for a backup.'

$bundle = 'C:\archive-pacgate-ai-pr\pacgate-ai-pr-history.bundle'
$test   = 'C:\temp\bundle-decisive'
if (Test-Path $test) { Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue }

A "`n=== 1. Clone the SHIPPED bundle ==="
& git clone -q $bundle $test 2>&1 | Out-Null
A ("  cloned: {0}" -f (Test-Path $test))

# the commit in question
$target = (& git -C $old rev-parse 28dc159 2>$null) -join ''
A ("  target commit: {0}" -f $target)

# ---- (a) object presence: the decisive question ----------------------------
A "`n=== 2. Is the OBJECT present in the clone's database? ==="
& git -C $test cat-file -e $target 2>$null
$objPresent = ($LASTEXITCODE -eq 0)
A ("  git cat-file -e  -> {0}" -f $(if ($objPresent) { 'PRESENT' } else { 'ABSENT' }))

if ($objPresent) {
    $t = (& git -C $test log -1 --format='%h %ad %s' --date=short $target 2>$null) -join ''
    A ("  readable as    : {0}" -f $t)
    $type = (& git -C $test cat-file -t $target 2>$null) -join ''
    A ("  object type    : {0}" -f $type)
}

# ---- (b) can it be recovered without the original? -------------------------
A "`n=== 3. Can the commit be fully recovered from the bundle alone? ==="
A '  If the object is present, `git checkout <sha>` / `git branch x <sha>`'
A '  works without ever touching C:\pacgate-ai-pr.'
& git -C $test branch recovered-28dc159 $target 2>&1 | ForEach-Object { A ("    " + $_) }
$nowHas = @(& git -C $test branch --list recovered-28dc159).Count
A ("  branch created from it: {0}" -f $(if ($nowHas) { 'YES' } else { 'NO' }))
if ($nowHas) {
    $files = @(& git -C $test ls-tree -r --name-only recovered-28dc159 2>$null)
    A ("  files in that tree    : {0}" -f $files.Count)
}

# ---- (c) full commit-set check using cat-file, not refs --------------------
A "`n=== 4. Complete check: is EVERY source commit object in the bundle? ==="
$srcAll = @(& git -C $old rev-list --all 2>$null)
$absent = New-Object System.Collections.Generic.List[string]
foreach ($c in $srcAll) {
    & git -C $test cat-file -e $c 2>$null
    if ($LASTEXITCODE -ne 0) { $absent.Add($c) }
}
A ("  source commits     : {0}" -f $srcAll.Count)
A ("  ABSENT from bundle : {0}   (must be 0)" -f $absent.Count)
foreach ($a in ($absent | Select-Object -First 10)) { A ("    ! " + $a.Substring(0,10)) }

# ---- (d) do it for every ref too -------------------------------------------
A "`n=== 5. Every ref that exists in the source ==="
$srcRefs = @(& git -C $old for-each-ref --format='%(objectname) %(refname)' 2>$null)
$badRefs = 0
foreach ($r in $srcRefs) {
    $sha = ($r -split '\s+')[0]
    & git -C $test cat-file -e $sha 2>$null
    if ($LASTEXITCODE -ne 0) { $badRefs++; A ("    ! ref object absent: " + $r) }
}
A ("  source refs: {0}   refs whose object is absent: {1}   (must be 0)" -f $srcRefs.Count, $badRefs)

A "`n=== VERDICT ==="
if ($objPresent -and $absent.Count -eq 0) {
    A '  NO DATA LOSS. Every source commit object is inside the bundle.'
    A '  The earlier "MISSING: 1" was a REF-MATERIALISATION artefact: a fresh'
    A '  clone does not create a local ref for refs/remotes/* entries, so'
    A '  `rev-list --all` cannot see that commit even though its objects are'
    A '  present. The backup is complete.'
} else {
    A ("  REAL LOSS: {0} commit object(s) absent from the bundle." -f $absent.Count)
}

Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"