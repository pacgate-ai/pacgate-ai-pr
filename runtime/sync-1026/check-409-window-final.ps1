# Resolve the contradiction: the MCP log has lines dated 2026-10-26 04:53 while
# the container reports StartedAt 2026-10-27T01:34:52Z.
#
# Hypothesis: docker restarted the container IN PLACE (compose up -d without
# --force-recreate). `docker logs` returns the whole accumulated json-log since
# the ORIGINAL creation, not since the last start; StartedAt only reports the
# latest start. If so, those 409s happened before the upgrade and are not a
# post-upgrade regression.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

'=== creation vs start (the two are NOT the same) ==='
foreach ($n in @('pacgate-mcp', 'deer-flow', 'pacgate-api')) {
    $c = & docker inspect $n --format '{{.Created}}' 2>&1
    $s = & docker inspect $n --format '{{.State.StartedAt}}' 2>&1
    '  {0,-14} created={1}  started={2}' -f $n, $c, $s
}

''
'=== first log line per container (earliest evidence retained) ==='
foreach ($n in @('pacgate-mcp', 'deer-flow')) {
    $first = (& docker logs $n 2>&1 | Select-Object -First 1)
    '  {0,-14} {1}' -f $n, ("$first".Trim().Substring(0, [Math]::Min(110, "$first".Trim().Length)))
}

''
'=== the two MCP 409 lines, verbatim, with any preceding timestamp ==='
$mcp = (& docker logs pacgate-mcp 2>&1)
for ($i = 0; $i -lt $mcp.Count; $i++) {
    if ($mcp[$i] -match '409 Conflict') {
        # walk backwards for the nearest dated line
        $ts = '?'
        for ($j = $i; $j -ge [Math]::Max(0, $i - 6); $j--) {
            if ($mcp[$j] -match '(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $ts = $Matches[1]; break }
        }
        $text = "$($mcp[$i])".Trim()
        '  409 @ {0}   {1}' -f $ts, $text.Substring(0, [Math]::Min(90, $text.Length))
    }
}

$ErrorActionPreference = $prevEap
