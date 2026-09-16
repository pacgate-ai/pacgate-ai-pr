$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\volume-generations.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('VOLUME GENERATIONS + PROJECT-NAME CONFLICT')
$lines.Add('')

# Avoid `docker run` (slow/hangs). `volume inspect` is enough to show that two
# generations exist, which is the point.
foreach ($v in @('client-bundle_pacgate-db-data', 'pacgate-ai-bundle_pacgate-db-data', 'qm-pacgate-pgdata', 'qm-pacgate-coredata')) {
    $lines.Add("=== $v ===")
    $j = & docker volume inspect $v 2>$null | ConvertFrom-Json
    if ($j) {
        $lines.Add("  CreatedAt : $($j.CreatedAt)")
        $lines.Add("  Driver    : $($j.Driver)")
        $labelText = ''
        foreach ($p in $j.Labels.PSObject.Properties) {
            if ($p.Name -like '*compose*') { $labelText += "$($p.Name)=$($p.Value) " }
        }
        $lines.Add("  Compose labels: $(if ($labelText) { $labelText } else { '(none)' })")
    } else {
        $lines.Add('  (not found)')
    }
    $lines.Add('')
}

# Which containers reference each volume
$lines.Add('=== container -> volume (live attachment) ===')
foreach ($n in @(& docker ps -a --format '{{.Names}}')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    $vols = @($j[0].Mounts | Where-Object { $_.Type -eq 'volume' })
    if ($vols.Count -eq 0) { continue }
    foreach ($m in $vols) { $lines.Add(('  {0,-22} -> {1}' -f $n, $m.Name)) }
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
