# Establish the time window of the pacgate-mcp log, and the timestamps of its 409s.
# Needed because the MCP container reports a restart at 01:34:52 but its log shows
# httpx lines dated 2026-10-26 - one of those two facts has to be wrong.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

'=== container start times ==='
foreach ($n in @('pacgate-mcp', 'deer-flow', 'pacgate-api')) {
    $s = & docker inspect $n --format '{{.State.StartedAt}}' 2>&1
    '  {0,-14} {1}' -f $n, $s
}

$mcp = (& docker logs pacgate-mcp 2>&1) -join "`n"
$ErrorActionPreference = $prevEap

''
'=== log time window (first / last dated line) ==='
$dates = [regex]::Matches($mcp, '(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') | ForEach-Object { $_.Groups[1].Value }
"  dated_lines = $($dates.Count)"
if ($dates.Count -gt 0) {
    '  first = ' + $dates[0]
    '  last  = ' + $dates[-1]
}

''
'=== each 409 with its full timestamp ==='
foreach ($m in [regex]::Matches($mcp, '(?m)^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)[^\n]*documents/([^\s"]+)/(download|sanitize|sanitize-status)"[^\n]*?(\d{3})')) {
    '  {0}  {1,-12} {2}' -f $m.Groups[1].Value, $m.Groups[3].Value, $m.Groups[4].Value
}
