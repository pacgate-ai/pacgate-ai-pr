$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\hardcoded-path-references.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('HARDCODED PATH REFERENCES (what breaks when the tree moves)')
$lines.Add('')

# ============================================================================
# Scan the FILESYSTEM (not git output) for text files that mention the old
# absolute path. Iterating git output would corrupt CJK paths on this machine.
# ============================================================================

$patterns = @('C:\pacgate-ai-pr', 'C:/pacgate-ai-pr', 'pacgate-ai-pr')
$exts = @('.ps1','.py','.yaml','.yml','.json','.md','.sh','.conf','.env','.example','.txt','.ts','.js','.toml','.sql','.patch','.cmd','.bat')

$hits = New-Object System.Collections.Generic.List[object]
$scanned = 0

foreach ($f in (Get-ChildItem 'C:\pacgate-ai-pr' -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $p = $f.FullName
    if ($p -like '*\pacgate-ai\target\*') { continue }
    if ($p -like '*\deploy\deer-flow-src\*') { continue }
    if ($p -like '*\node_modules\*') { continue }
    if ($p -like '*\.git\*') { continue }
    if ($p -like '*\deploy\client-bundle\data\*') { continue }
    if ($exts -notcontains $f.Extension.ToLower()) { continue }
    if ($f.Length -gt 400000) { continue }

    $scanned++
    try {
        $txt = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($p))
    } catch { continue }

    $count = 0
    foreach ($pat in $patterns) {
        $idx = 0
        while (($idx = $txt.IndexOf($pat, $idx, [System.StringComparison]::OrdinalIgnoreCase)) -ge 0) { $count++; $idx += $pat.Length }
    }
    if ($count -gt 0) {
        $hits.Add([PSCustomObject]@{
            Count = $count
            Path  = $p.Replace('C:\pacgate-ai-pr\','')
        })
    }
}

$lines.Add("text files scanned: $scanned")
$lines.Add("files referencing the old path: $($hits.Count)")
$lines.Add('')
$lines.Add('--- by reference count (highest coupling first) ---')
foreach ($h in ($hits | Sort-Object Count -Descending | Select-Object -First 30)) {
    $lines.Add(('  {0,4} refs  {1}' -f $h.Count, $h.Path))
}

$lines.Add('')
$lines.Add('--- grouped by top-level area ---')
$byArea = $hits | ForEach-Object { ($_.Path -split '\\')[0] } | Group-Object | Sort-Object Count -Descending
foreach ($g in $byArea) { $lines.Add(('  {0,-26} {1} file(s)' -f $g.Name, $g.Count)) }

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
