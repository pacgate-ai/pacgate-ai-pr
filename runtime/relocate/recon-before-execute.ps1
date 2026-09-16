$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$src  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\RECON-BEFORE-EXECUTE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A "RECON BEFORE PHASE 1 EXECUTE"
A ("=" * 62)

A "`n=== 1. Backups (rollback anchors) ==="
foreach ($b in @('C:\backup-pacgate-ai-pr-git', 'C:\backup-pacgate-law-git')) {
    if (Test-Path $b) {
        $f = @(Get-ChildItem $b -Recurse -File -Force -ErrorAction SilentlyContinue)
        $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
        A ("  OK      {0}  files={1}  {2} MB" -f $b, $f.Count, $mb)
    } else {
        A ("  MISSING {0}" -f $b)
    }
}

A "`n=== 2. Source state (must be untouched) ==="
A ("  HEAD: " + (& git -C $src rev-parse --short HEAD))
$modified = @(& git -C $src status --porcelain | Where-Object { $_ -match '^(.M|M.|MM|AM)' })
A ("  modified tracked files: {0}   (MUST be 0)" -f $modified.Count)
foreach ($m in $modified) { A ("    ! " + $m) }

A "`n=== 3. pacgate-law git state ==="
A ("  commits: " + (& git -C $repo rev-list --count HEAD 2>$null))
A ("  branch : " + (& git -C $repo branch --show-current 2>$null))
A "  index entries (ls-files --stage):"
& git -C $repo ls-files --stage | ForEach-Object { A ("    " + $_) }

A "`n=== 4. .gitmodules ==="
$gm = Join-Path $repo '.gitmodules'
if (Test-Path $gm) {
    [System.IO.File]::ReadAllLines($gm) | ForEach-Object { A ("    " + $_) }
} else { A "  (none)" }

A "`n=== 5. Is pacgate-ai a real submodule? ==="
$pa = Join-Path $repo 'pacgate-ai'
A ("  dir exists      : " + (Test-Path $pa))
$paGit = Join-Path $pa '.git'
A ("  .git present    : " + (Test-Path $paGit))
A ("  .git is a dir   : " + (Test-Path $paGit -PathType Container))
A ("  .git is a file  : " + (Test-Path $paGit -PathType Leaf))
A "  top-level entries:"
if (Test-Path $pa) {
    Get-ChildItem $pa -Force | ForEach-Object { A ("    " + $_.Name) }
}

A "`n=== 6. deer-flow: submodule or embedded repo? ==="
$df = Join-Path $repo 'deer-flow'
$dfGit = Join-Path $df '.git'
if (Test-Path $dfGit -PathType Container)     { $t = 'directory (embedded repo)' }
elseif (Test-Path $dfGit -PathType Leaf)      { $t = 'file (submodule)' }
else                                          { $t = 'none' }
A ("  .git type       : " + $t)
A ("  branch          : " + (& git -C $df branch --show-current 2>$null))
A ("  commits         : " + (& git -C $df rev-list --count HEAD 2>$null))

A "`n=== 7. Sizing (what must NOT be committed) ==="
foreach ($p in @('deer-flow', 'pacgate-ai', 'docs', 'runtime', 'pacgate-ai-assets')) {
    $full = Join-Path $repo $p
    if (Test-Path $full) {
        $f = @(Get-ChildItem $full -Recurse -File -Force -ErrorAction SilentlyContinue)
        $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
        A ("  {0,-18} files={1,-8} {2} MB" -f $p, $f.Count, $mb)
    } else {
        A ("  {0,-18} (absent)" -f $p)
    }
}

A "`n=== 8. Free space ==="
A ("  C: free = {0} GB" -f [math]::Round((Get-PSDrive C).Free / 1GB, 1))

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
