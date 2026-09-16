$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\tracked-vs-excluded-audit.txt'

$lines = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- tracked set
$tracked = @(& git -C C:\pacgate-ai-pr -c core.quotepath=false ls-files)
$lines.Add("TRACKED FILES: $($tracked.Count)")
$lines.Add('')

# Per top-level dir under deploy
$lines.Add('--- tracked, grouped by deploy subdir ---')
$byDir = $tracked | Where-Object { $_ -like 'deploy/*' } | ForEach-Object { ($_ -split '/')[1] } | Group-Object | Sort-Object Count -Descending
foreach ($g in $byDir) { $lines.Add(('  {0,-34} {1}' -f $g.Name, $g.Count)) }
$lines.Add('')

# ------------------------------------------------- what is IGNORED on disk?
# Enumerate real on-disk files then ask git if each is ignored. This reveals the
# gap between "on disk" (what the stack needs to run) and "in git" (deliverable).
$lines.Add('--- on-disk but IGNORED (cannot ship via git as-is) ---')
$roots = @(
    'C:\pacgate-ai-pr\deploy\client-bundle',
    'C:\pacgate-ai-pr\deploy\qm-pacgate',
    'C:\pacgate-ai-pr\deploy\deer-flow-src',
    'C:\pacgate-ai-pr\deploy\client-delivery'
)
foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    $files = Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue
    $ignored = 0; $kept = 0; $ignoredBytes = 0
    $samples = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $rel = $f.FullName.Replace('C:\pacgate-ai-pr\','').Replace('\','/')
        $chk = & git -C C:\pacgate-ai-pr check-ignore -- $rel 2>$null
        if ($chk) {
            $ignored++; $ignoredBytes += $f.Length
            if ($samples.Count -lt 4) { $samples.Add("      e.g. $rel  ($([math]::Round($f.Length/1KB,1)) KB)") }
        } else { $kept++ }
    }
    $lines.Add(('  {0}' -f $r.Replace('C:\pacgate-ai-pr\','')))
    $lines.Add(('      on-disk={0}  ignored={1}  not-ignored={2}' -f $files.Count, $ignored, $kept))
    $lines.Add(('      ignored bytes = {0} MB' -f [math]::Round($ignoredBytes/1MB,1)))
    foreach ($s in $samples) { $lines.Add($s) }
    $lines.Add('')
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
