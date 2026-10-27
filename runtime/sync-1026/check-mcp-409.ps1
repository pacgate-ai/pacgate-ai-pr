# The chat session reaches pacgate-api through pacgate-mcp, not nginx.
# Look for 409 / download / sanitize activity in the MCP server's own log.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $mcpLog = Join-Path $env:TEMP 'pacgate-mcp.log'
    & docker logs pacgate-mcp 2>&1 | Out-File -FilePath $mcpLog -Encoding utf8
}
finally { $ErrorActionPreference = $prevEap }

$lines = Get-Content $mcpLog
"mcp_log_lines=$($lines.Count)"

'=== 409 in pacgate-mcp log ==='
$h = $lines | Select-String -Pattern '409|conflict' -CaseSensitive:$false
"hit_count=$($h.Count)"
$h | Select-Object -Last 10 | ForEach-Object {
    $t = $_.Line.Trim()
    '  ' + $t.Substring(0, [Math]::Min(200, $t.Length))
}

'=== download / sanitize / verify tool activity ==='
$lines | Select-String -Pattern 'download|sanitize|verify' | Select-Object -Last 10 | ForEach-Object {
    $t = $_.Line.Trim()
    '  ' + $t.Substring(0, [Math]::Min(200, $t.Length))
}

'=== pending documents that will 409 if read ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker exec pacgate-db psql -U pacgate -d pacgate -t -A -c "SELECT sanitization_state, count(*) FROM documents WHERE matter_id='769225d9-804c-4a3f-8775-8dcc4c676d0e' GROUP BY 1 ORDER BY 2 DESC;" 2>&1
}
finally { $ErrorActionPreference = $prevEap }
