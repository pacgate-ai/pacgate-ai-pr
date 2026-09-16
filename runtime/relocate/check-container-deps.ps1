$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\container-dependency-check.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('CONTAINER DEPENDENCY CHECK before moving pacgate-ai -> pacgate-ai-assets')
$r.Add('=' * 70)
$r.Add('')
$r.Add('Phase 1 relocates the submodule directory inside pacgate-law. If any RUNNING')
$r.Add('container bind-mounts a path under pacgate-law, moving it would break that')
$r.Add('container the same way deleting would.')
$r.Add('')

$lawRoot = 'c:\Users\pacga\github-pr\pacgate-law'
$hits = 0
$total = 0

foreach ($n in @(& docker ps -a --format '{{.Names}}')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    foreach ($m in @($j[0].Mounts)) {
        $total++
        $src = "$($m.Source)"
        # Look for ANY path under the pacgate-law repo
        if ($src -like "*pacgate-law*") {
            $hits++
            $r.Add("  *** DEPENDS on pacgate-law: $n")
            $r.Add("        source: $src")
            $r.Add("        target: $($m.Destination)")
        }
    }
    # Also check compose config paths
    $cf = $j[0].Config.Labels.'com.docker.compose.project.config_files'
    if ($cf -like '*pacgate-law*') {
        $hits++
        $r.Add("  *** COMPOSE CONFIG in pacgate-law: $n")
        $r.Add("        config: $cf")
    }
}

$r.Add('')
$r.Add("total mounts examined : $total")
$r.Add("dependencies on pacgate-law : $hits")
$r.Add('')
if ($hits -eq 0) {
    $r.Add('VERDICT: SAFE. No running container depends on any path under pacgate-law,')
    $r.Add('so relocating the submodule directory inside it cannot break a container.')
} else {
    $r.Add('VERDICT: CAUTION. Containers depend on pacgate-law paths - review above.')
}

# Additionally: confirm the submodule dir is not itself a mount source
$r.Add('')
$r.Add('--- is the submodule path itself referenced by any container? ---')
$sub = $lawRoot + '\pacgate-ai'
$found = $false
foreach ($n in @(& docker ps -a --format '{{.Names}}')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    foreach ($m in @($j[0].Mounts)) {
        if ("$($m.Source)" -like "*$sub*") { $r.Add("  $n -> $($m.Source)"); $found = $true }
    }
}
if (-not $found) { $r.Add('  (none) - the submodule path is not a mount source') }

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"