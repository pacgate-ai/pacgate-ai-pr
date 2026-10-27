# Final audit: memory lane outcomes and 409 activity, scoped to the CURRENT
# container only. The earlier counts came from a stale log file that mixed
# pre-restart content; these read straight from the running container.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$gw = & docker logs deer-flow 2>&1
$mcp = & docker logs pacgate-mcp 2>&1
$ErrorActionPreference = $prevEap

$gwText = $gw -join "`n"
$mcpText = $mcp -join "`n"

'=== memory lane outcomes (current container) ==='
foreach ($pair in @(
        @('updated_successfully', 'Memory updated successfully'),
        @('queued', 'Memory update queued'),
        @('failed_timed_out', 'Memory update failed: timed out'),
        @('failed_parse', 'Failed to parse LLM response for memory update'),
        @('refused_out_of_scope', 'refused as out of scope')
    )) {
    $n = ([regex]::Matches($gwText, [regex]::Escape($pair[1]))).Count
    '  {0,-22} {1}' -f $pair[0], $n
}

''
'=== memory outcome timeline ==='
foreach ($m in [regex]::Matches($gwText, '(?m)^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*?(Memory updated successfully|Memory update failed: timed out|Failed to parse LLM response for memory update)')) {
    '  {0}  {1}' -f $m.Groups[1].Value, $m.Groups[2].Value
}

''
'=== 409 activity on document routes (current MCP container) ==='
$dl = [regex]::Matches($mcpText, 'documents/[^\s"]*/(download|sanitize|sanitize-status)[^"]*"\s*(?:HTTP/[0-9.]+ )?(\d{3})')
$tally = @{}
foreach ($m in $dl) {
    $k = $m.Groups[1].Value + ' ' + $m.Groups[2].Value
    $tally[$k] = 1 + ($tally[$k] | ForEach-Object { $_ })
}
if ($tally.Count -eq 0) { '  no document sub-route calls in this container log' }
else { $tally.GetEnumerator() | Sort-Object Name | ForEach-Object { '  {0,-24} {1}' -f $_.Key, $_.Value } }

''
'=== document states right now (deer-flow matter) ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker exec pacgate-db psql -U pacgate -d pacgate -t -A -c "SELECT sanitization_state, count(*) FROM documents WHERE matter_id='769225d9-804c-4a3f-8775-8dcc4c676d0e' GROUP BY 1 ORDER BY 2 DESC;" 2>&1 |
        ForEach-Object { '  ' + $_ }
}
finally { $ErrorActionPreference = $prevEap }
