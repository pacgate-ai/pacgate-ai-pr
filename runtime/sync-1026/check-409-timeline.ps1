# Timeline: when did the 2 MCP 409s happen, and did each recover?
# Also: memory lane success vs failure after the 01:34 restart.
$ErrorActionPreference = 'Stop'

'=== MCP: every document 409, with surrounding lines ==='
$mcp = Get-Content (Join-Path $env:TEMP 'pacgate-mcp.log')
for ($i = 0; $i -lt $mcp.Count; $i++) {
    if ($mcp[$i] -match 'download.*409|409 Conflict') {
        $prev = if ($i -gt 0) { $mcp[$i - 1].Trim() } else { '' }
        $next = if ($i -lt $mcp.Count - 1) { $mcp[$i + 1].Trim() } else { '' }
        $cur = $mcp[$i].Trim()
        '---'
        '  PREV: ' + $prev.Substring(0, [Math]::Min(150, $prev.Length))
        '  HIT : ' + $cur.Substring(0, [Math]::Min(150, $cur.Length))
        '  NEXT: ' + $next.Substring(0, [Math]::Min(150, $next.Length))
    }
}

''
'=== memory lane: success vs failure counts (this container) ==='
$gw = Get-Content (Join-Path $env:TEMP 'deerflow-gateway.log')
$ok = ($gw | Select-String -Pattern 'Memory updated successfully').Count
$q = ($gw | Select-String -Pattern 'Memory update queued').Count
$to = ($gw | Select-String -Pattern 'Memory update failed: timed out').Count
$parse = ($gw | Select-String -Pattern 'Failed to parse LLM response for memory update').Count
$oos = ($gw | Select-String -Pattern 'refused as out of scope').Count
"updated_successfully = $ok"
"queued               = $q"
"failed_timed_out     = $to"
"failed_parse         = $parse"
"refused_out_of_scope = $oos"

''
'=== timestamps of memory outcomes ==='
$gw | Select-String -Pattern 'Memory updated successfully|Memory update failed: timed out|Failed to parse LLM response for memory update' |
ForEach-Object {
    $t = $_.Line.Trim()
    if ($t -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') {
        '  ' + $Matches[1] + '  ' + ($t -replace '^.*? - \w+ - ', '')
    }
}
