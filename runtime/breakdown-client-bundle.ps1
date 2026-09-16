$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\client-bundle-breakdown.txt'

$lines = New-Object System.Collections.Generic.List[string]
$root = 'C:\pacgate-ai-pr\deploy\client-bundle'

# Break the bundle down by SUBDIRECTORY so we can classify each part as
#   ship / do-not-ship / regenerable
$lines.Add('CLIENT-BUNDLE BREAKDOWN (what makes up the 1,924 MB of excluded content)')
$lines.Add('')

$dirs = @(Get-ChildItem -LiteralPath $root -Force -Directory -ErrorAction SilentlyContinue)
$rows = New-Object System.Collections.Generic.List[object]
foreach ($d in $dirs) {
    $f = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
    $rows.Add([PSCustomObject]@{
        Name  = $d.Name
        Files = $f.Count
        MB    = [math]::Round((($f | Measure-Object Length -Sum).Sum)/1MB, 2)
    })
}
$lines.Add('--- subdirectories by size ---')
foreach ($r in ($rows | Sort-Object MB -Descending)) {
    $lines.Add(('  {0,-26} files={1,-6} {2,10} MB' -f $r.Name, $r.Files, $r.MB))
}
$lines.Add('')

# Tracked vs ignored inside each subdir
$lines.Add('--- tracked vs ignored inside each subdirectory ---')
foreach ($d in $dirs) {
    $f = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
    $ign = 0; $keep = 0
    foreach ($x in $f) {
        $rel = $x.FullName.Replace('C:\pacgate-ai-pr\','').Replace('\','/')
        $chk = & git -C C:\pacgate-ai-pr check-ignore -- $rel 2>$null
        if ($chk) { $ign++ } else { $keep++ }
    }
    $lines.Add(('  {0,-26} tracked={1,-6} ignored={2,-6}' -f $d.Name, $keep, $ign))
}
$lines.Add('')

# The 39 tracked files are the real deliverable payload; list them.
$lines.Add('--- TRACKED files in client-bundle (the shippable payload) ---')
$tracked = @(& git -C C:\pacgate-ai-pr -c core.quotepath=false ls-files 'deploy/client-bundle/')
foreach ($t in $tracked) { $lines.Add("  $t") }

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
