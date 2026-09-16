$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\MOUNTS-RAW.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RAW MOUNT INSPECTION -- why did the previous scan report 0 bind mounts?'
A ('=' * 78)

# --- try several inspect formulations against one known container ------------
A "`n=== A. deer-flow, several format strings ==="
$formats = @(
    '{{json .Mounts}}',
    '{{range .Mounts}}{{.Type}}{{"\n"}}{{end}}',
    '{{range .Mounts}}{{.Type}}|{{.Source}}{{"\n"}}{{end}}',
    '{{range .Mounts}}[{{.Type}}] {{.Source}} => {{.Destination}}{{"\n"}}{{end}}'
)
foreach ($fmt in $formats) {
    A "`n  --- format: $fmt ---"
    $r = docker inspect deer-flow --format $fmt 2>&1
    if ($null -eq $r) { A '    (null)' }
    else {
        $lines = @("$r" -split "`n")
        A ("    lines: {0}" -f $lines.Count)
        foreach ($ln in ($lines | Select-Object -First 6)) { A ("      " + $ln) }
    }
}

# --- count mounts by type, all containers -----------------------------------
A "`n=== B. Mount counts per container (authoritative) ==="
$names = @(docker ps -a --format '{{.Names}}' | Sort-Object)
$totBind = 0; $totVol = 0
foreach ($n in $names) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = @($j | ConvertFrom-Json) } catch { continue }
    $b = @($m | Where-Object { $_.Type -eq 'bind' })
    $v = @($m | Where-Object { $_.Type -eq 'volume' })
    if ($b.Count -eq 0 -and $v.Count -eq 0) { continue }
    $totBind += $b.Count; $totVol += $v.Count
    A ("`n  [{0}]  bind={1}  volume={2}" -f $n, $b.Count, $v.Count)
    foreach ($x in $b) {
        $src = $x.Source
        $tag = if ($src -like '*pacgate-ai-pr*') { 'OLD' } elseif ($src -like '*pacgate-law*') { 'NEW' } else { 'EXT' }
        A ("      {0,-5} {1}" -f $tag, $src)
        A ("            -> {0}" -f $x.Destination)
    }
    foreach ($x in $v) {
        A ("      VOL   {0} -> {1}" -f $x.Name, $x.Destination)
    }
}
A ("`n  TOTAL bind mounts: {0}" -f $totBind)
A ("  TOTAL volume mounts: {0}" -f $totVol)

# --- any mount still pointing at the old path -------------------------------
A "`n=== C. Mounts still referencing the OLD path ==="
$oldRefs = @()
foreach ($n in $names) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = @($j | ConvertFrom-Json) } catch { continue }
    foreach ($x in $m) {
        if ($x.Source -like '*pacgate-ai-pr*') { $oldRefs += "$n : $($x.Source) -> $($x.Destination)" }
    }
}
A ("  count: {0}" -f $oldRefs.Count)
foreach ($o in $oldRefs) { A ("  " + $o) }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"