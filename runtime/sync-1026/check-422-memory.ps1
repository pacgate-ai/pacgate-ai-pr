# What are the 21 HTTP 422s, and what happened to the memory lane after restart?
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $env:TEMP 'deerflow-gateway.log'
if (-not (Test-Path $logFile)) { throw 'run check-gateway-409.ps1 first to produce the log' }
$lines = Get-Content $logFile

'=== lines containing HTTP 422 ==='
$lines | Select-String -Pattern 'HTTP/1\.1" 422' | Select-Object -First 8 | ForEach-Object {
    $t = $_.Line.Trim()
    '  ' + $t.Substring(0, [Math]::Min(220, $t.Length))
}

''
'=== 422 context: which route? ==='
$lines | Select-String -Pattern '422' | ForEach-Object {
    $l = $_.Line
    if ($l -match '"(GET|POST|PUT|DELETE) ([^ ]+) HTTP[^"]*" 422') { '  ' + $Matches[1] + ' ' + $Matches[2] }
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
    '  {0,4}  {1}' -f $_.Count, $_.Name
}

''
'=== memory updater outcomes (any timestamp form) ==='
$mem = $lines | Select-String -Pattern 'Memory update'
"memory_log_lines=$($mem.Count)"
$mem | Select-Object -Last 12 | ForEach-Object {
    $t = $_.Line.Trim()
    '  ' + $t.Substring(0, [Math]::Min(180, $t.Length))
}

''
'=== any "timed out" occurences ==='
$to = $lines | Select-String -Pattern 'timed out'
"timed_out_count=$($to.Count)"
$to | Select-Object -Last 6 | ForEach-Object {
    $t = $_.Line.Trim()
    '  ' + $t.Substring(0, [Math]::Min(160, $t.Length))
}
