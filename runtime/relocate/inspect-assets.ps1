$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$new  = Join-Path $repo 'pacgate-ai-assets'
$out  = Join-Path $repo 'runtime\relocate\ASSETS-STRUCTURE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'pacgate-ai-assets STRUCTURE (decide how the monorepo should carry it)'
A ('=' * 62)
A ''
A "  HEAD: " + ((& git -C $new rev-parse --short HEAD 2>$null) -join '')
A "  branch: " + ((& git -C $new branch --show-current 2>$null) -join '')
A "  remotes:"
& git -C $new remote -v 2>$null | ForEach-Object { A ("    " + $_) }

A "`n=== Top-level entries ==="
Get-ChildItem $new -Force | Sort-Object Name | ForEach-Object {
    $t = if ($_.PSIsContainer) { 'DIR ' } else { 'FILE' }
    A ("  {0} {1}" -f $t, $_.Name)
}

A "`n=== Size by top-level entry (what would enter the monorepo) ==="
foreach ($e in (Get-ChildItem $new -Force | Sort-Object Name)) {
    if ($e.PSIsContainer) {
        $f = @(Get-ChildItem $e.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
        A ("  {0,-30} {1,7} files {2,9} MB" -f $e.Name, $f.Count, $mb)
    } else {
        A ("  {0,-30} {1,7} file  {2,9} MB" -f $e.Name, 1, [math]::Round($e.Length/1MB,3))
    }
}

A "`n=== File types (by count) ==="
$byExt = @{}
Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    ForEach-Object {
        $e = if ($_.Extension) { $_.Extension.ToLower() } else { '(none)' }
        if (-not $byExt.ContainsKey($e)) { $byExt[$e] = @{ n = 0; mb = 0 } }
        $byExt[$e].n++
        $byExt[$e].mb += $_.Length
    }
foreach ($k in ($byExt.Keys | Sort-Object { -$byExt[$_].n })) {
    A ("  {0,-12} {1,6} files  {2,8} MB" -f $k, $byExt[$k].n, [math]::Round($byExt[$k].mb/1MB,1))
}

A "`n=== Nested repos present? (blocks direct tracking) ==="
$nested = @(Get-ChildItem $new -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '.git' })
foreach ($n in $nested) { A ("  " + $n.FullName) }

A "`n=== Would git track its CONTENTS, or just a gitlink? ==="
$dry = @(& git -C $repo add -A --dry-run -- pacgate-ai-assets 2>&1)
$warn = @($dry | Where-Object { $_ -match 'embedded|warning' })
A ("  dry-run lines: {0}" -f $dry.Count)
A ("  embedded-repo warnings: {0}" -f $warn.Count)
foreach ($w in ($warn | Select-Object -First 5)) { A ("    " + $w) }
if ($dry.Count -le 3) { foreach ($d in $dry) { A ("    " + $d) } }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
