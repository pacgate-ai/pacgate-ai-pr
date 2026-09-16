$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\volume-mtime.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('VOLUME MTIME COMPARISON (read-only)')
$lines.Add('')

$img = 'nginx:1.27-alpine'
$vols = @('pacgate-ai-bundle_pacgate-db-data', 'client-bundle_pacgate-db-data')

foreach ($v in $vols) {
    $lines.Add("=== $v ===")

    # ONE simple command per invocation avoids quoting problems in busybox sh.
    $lines.Add('  [size]')
    $r = & docker run --rm -v "${v}:/v:ro" --entrypoint du $img -sh /v 2>&1
    foreach ($x in $r) { $lines.Add("    $x") }

    $lines.Add('  [PG_VERSION]')
    $r = & docker run --rm -v "${v}:/v:ro" --entrypoint cat $img /v/PG_VERSION 2>&1
    foreach ($x in $r) { $lines.Add("    $x") }

    $lines.Add('  [pg_wal entry count]')
    $r = & docker run --rm -v "${v}:/v:ro" --entrypoint ls $img -1 /v/pg_wal 2>&1
    $lines.Add("    entries: $(@($r).Count)")

    $lines.Add('  [newest 4 in pg_wal, by mtime]')
    $r = & docker run --rm -v "${v}:/v:ro" --entrypoint ls $img -lt /v/pg_wal 2>&1
    foreach ($x in (@($r) | Select-Object -First 5)) { $lines.Add("    $x") }

    $lines.Add('  [newest 4 in base, by mtime]')
    $r = & docker run --rm -v "${v}:/v:ro" --entrypoint ls $img -lt /v/base 2>&1
    foreach ($x in (@($r) | Select-Object -First 5)) { $lines.Add("    $x") }

    $lines.Add('')
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
