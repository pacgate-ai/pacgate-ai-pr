# Audit: where do 409s actually appear, and from which path?
#
# The earlier attempts died on nested quoting in `sh -c '... node -e "..."'`.
# Dump the raw log to a file first, then analyse it in PowerShell - no quoting
# crossing a shell boundary at all.
$ErrorActionPreference = 'Stop'

$logFile = Join-Path $env:TEMP 'deerflow-gateway.log'
# Docker writes container logging to stderr. Under $ErrorActionPreference='Stop'
# PowerShell 5.1 promotes a native command's stderr to a TERMINATING error, so
# the capture died on the first warning line. Scope the preference down for this
# one call (the same fix this repo applied in test-memory-lane.ps1).
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker logs deer-flow 2>&1 | Out-File -FilePath $logFile -Encoding utf8
}
finally { $ErrorActionPreference = $prevEap }
$lines = Get-Content $logFile
"log_lines=$($lines.Count)"

'=== any literal 409 / Conflict / conflict ==='
$hits = $lines | Select-String -Pattern '409|Conflict|conflict' -CaseSensitive:$false
"hit_count=$($hits.Count)"
$hits | Select-Object -Last 15 | ForEach-Object { '  ' + $_.Line.Trim().Substring(0, [Math]::Min(200, $_.Line.Trim().Length)) }

'=== HTTP status codes seen in gateway access lines ==='
$lines | Select-String -Pattern 'HTTP/1\.1" (\d{3})' -AllMatches | ForEach-Object {
    foreach ($m in $_.Matches) { $m.Groups[1].Value }
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
    '  {0,5}  HTTP {1}' -f $_.Count, $_.Name
}

'=== memory update outcomes after the 01:34 restart ==='
$lines | Select-String -Pattern 'Memory update (failed|skipped|refused)' | ForEach-Object {
    if ($_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') {
        $ts = $Matches[1]
        '  ' + $ts + '  ' + ($_.Line -replace '^.*? - ', '').Trim()
    }
}
