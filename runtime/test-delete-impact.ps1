$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\delete-impact-bindmounts.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('DELETE-IMPACT TEST 1: do running containers bind-mount from C:\pacgate-ai-pr ?')
$lines.Add('')
$lines.Add('If any container bind-mounts a path under C:\pacgate-ai-pr, deleting that')
$lines.Add('directory breaks the container IMMEDIATELY (the mount disappears).')
$lines.Add('')

$hits = 0
$totalMounts = 0

foreach ($n in @(& docker ps -a --format '{{.Names}}')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    foreach ($m in @($j[0].Mounts)) {
        $totalMounts++
        $src = "$($m.Source)"
        if ($src -like '*pacgate-ai-pr*') {
            $hits++
            $lines.Add("  *** DEPENDS: $n")
            $lines.Add("        source : $src")
            $lines.Add("        target : $($m.Destination)")
            $lines.Add("        type   : $($m.Type)")
            $lines.Add('')
        }
    }
}

$lines.Add("--- summary ---")
$lines.Add("  total mounts examined      : $totalMounts")
$lines.Add("  mounts under pacgate-ai-pr : $hits")
$lines.Add('')
if ($hits -gt 0) {
    $lines.Add('  VERDICT: DELETING C:\pacgate-ai-pr WOULD IMMEDIATELY BREAK THESE CONTAINERS.')
} else {
    $lines.Add('  VERDICT: no live bind-mount dependency found for this check.')
}

# Also: which compose project's config files point there? Docker records the
# path used at `up` time, which is needed for `down`, `up`, and `config`.
$lines.Add('')
$lines.Add('--- compose config_files recorded by Docker ---')
foreach ($n in @(& docker ps -a --format '{{.Names}}')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    $l = $j[0].Config.Labels
    $cf = $l.'com.docker.compose.project.config_files'
    if ($cf -like '*pacgate-ai-pr*') {
        $lines.Add("  $n")
        $lines.Add("      project      : $($l.'com.docker.compose.project')")
        $lines.Add("      config_files : $cf")
        $lines.Add("      working_dir  : $($l.'com.docker.compose.project.working_dir')")
    }
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
