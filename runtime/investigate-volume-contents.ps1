$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\volume-contents-investigation.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('READ-ONLY INVESTIGATION OF THE TWO pacgate-db-data VOLUMES')
$lines.Add('')
$lines.Add('Method: mount each volume READ-ONLY (:ro) into a throwaway container and')
$lines.Add('inspect it. Nothing is written, moved, or deleted.')
$lines.Add('')

# Use an image already present locally to avoid a pull (and the timeout risk).
$img = 'nginx:1.27-alpine'
$local = @(& docker images --format '{{.Repository}}:{{.Tag}}')
if ($local -notcontains $img) {
    $alt = @($local | Where-Object { $_ -like '*alpine*' } | Select-Object -First 1)
    if ($alt.Count -gt 0) { $img = $alt[0] }
}
$lines.Add("image used for inspection: $img")
$lines.Add('')

$volumes = @('pacgate-ai-bundle_pacgate-db-data', 'client-bundle_pacgate-db-data')

foreach ($v in $volumes) {
    $lines.Add("================ $v ================")

    # Read-only mount -> the container cannot modify the volume.
    $cmd = 'du -sh /v 2>/dev/null; echo "---top-level---"; ls -1 /v 2>/dev/null; ' +
           'echo "---version file---"; cat /v/PG_VERSION 2>/dev/null || echo "(no PG_VERSION)"; ' +
           'echo "---base dirs---"; ls -1 /v/base 2>/dev/null | head -20; ' +
           'echo "---file count---"; find /v -type f 2>/dev/null | wc -l; ' +
           'echo "---db catalog mtime (newest 3)---"; ls -lt /v/base 2>/dev/null | head -4; ' +
           'echo "---global---"; ls -1 /v/global 2>/dev/null | head -5'

    $res = & docker run --rm -v "${v}:/v:ro" --entrypoint sh $img -c $cmd 2>&1
    if ($res) {
        foreach ($r in $res) { $lines.Add("  $r") }
    } else {
        $lines.Add('  (no output - container may have failed to start)')
    }
    $lines.Add('')
}

# Also record which volume the LIVE container uses, for contrast.
$lines.Add('================ live attachment ================')
foreach ($n in @('pacgate-db', 'pacgate-api')) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    foreach ($m in @($j[0].Mounts)) {
        if ($m.Type -eq 'volume') { $lines.Add(('  {0,-14} -> {1}  ({2})' -f $n, $m.Name, $m.Destination)) }
    }
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
