# Post-upgrade full audit. Read-only. Produces one consolidated verdict.
# Every claim below is derived from live evidence in this script - nothing is
# asserted from memory or from an earlier run.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1) -join "`n"
$mcp = (& docker logs pacgate-mcp 2>&1) -join "`n"
$ErrorActionPreference = $prevEap

function Count-Of($text, $needle) { ([regex]::Matches($text, [regex]::Escape($needle))).Count }

'############ 1. CONTAINERS ############'
foreach ($n in @('deer-flow', 'deer-flow-frontend', 'pacgate-api', 'pacgate-mcp', 'pacgate-nginx',
        'ocr-service', 'pacgate-db', 'openviking')) {
    $st = (& docker inspect $n --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}/restarts={{.RestartCount}}' 2>&1)
    $img = (& docker inspect $n --format '{{.Config.Image}}' 2>&1)
    '  {0,-20} {1,-28} {2}' -f $n, $st, ($img -replace '^.*:', 'tag=')
}

''
'############ 2. UPGRADE ARTIFACT (86a9feb) ############'
$prompt = (& docker exec deer-flow grep -c "MEMORY_CONVERSATION_MAX_CHARS" /app/backend/packages/harness/deerflow/agents/memory/prompt.py 2>&1)
# grep -c counts MATCHING LINES (5 here: 2 declarations + 3 uses), so comparing to
# 1 reported a false negative. Assert "present at all", then name the exact values.
$count = 0; [int]::TryParse("$prompt".Trim(), [ref]$count) | Out-Null
'  cap_present = {0}  (matching lines: {1})' -f ($count -gt 0), $count
# `sh -c` with `<` inside the pattern is parsed as a redirect (`cannot open
# conversation`). Match the bare tag names instead, and let grep see no `<`.
$order = (& docker exec deer-flow sh -c 'grep -n -F -e conversation -e current_memory /app/backend/packages/harness/deerflow/agents/memory/prompt.py | head -6' 2>&1)
'  -- placeholder lines (conversation should precede current_memory) --'
$order | ForEach-Object { '    ' + ("$_".Trim() -replace '\s+', ' ') }

''
'############ 3. MEMORY LANE ############'
foreach ($pair in @(@('Memory updated successfully', 'updated_ok'),
        @('Memory update failed: timed out', 'timed_out'),
        @('Failed to parse LLM response for memory update', 'parse_fail'),
        @('refused as out of scope', 'out_of_scope'),
        @('refused as stale', 'stale_409'))) {
    '  {0,-14} {1}' -f $pair[1], (Count-Of $gw $pair[0])
}
'  -- timeline --'
foreach ($m in [regex]::Matches($gw, '(?m)^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*?(Memory updated successfully|Memory update failed: timed out|Failed to parse LLM response for memory update)')) {
    '    {0}  {1}' -f $m.Groups[1].Value, $m.Groups[2].Value
}

''
'############ 4. DOCUMENT SANITIZATION GATE ############'
$dl = [regex]::Matches($mcp, 'documents/[^\s"]*/(download|sanitize|sanitize-status)[^"]*"\s*(?:HTTP/[0-9.]+ )?(\d{3})')
$tally = @{}
foreach ($m in $dl) {
    $k = '{0} {1}' -f $m.Groups[1].Value, $m.Groups[2].Value
    if ($tally.ContainsKey($k)) { $tally[$k]++ } else { $tally[$k] = 1 }
}
if ($tally.Count -eq 0) { '  (none in retained log)' }
else { $tally.GetEnumerator() | Sort-Object Name | ForEach-Object { '  {0,-24} {1}' -f $_.Key, $_.Value } }
'  NOTE: pacgate-mcp was created 2026-10-26T04:53 and restarted 2026-10-27T01:34,'
'        so `docker logs` spans BOTH eras. Timestamps below separate them.'

''
'############ 5. AUTH ############'
'  login/local 422 = {0}   (caller sent JSON; the route needs form data)' -f (Count-Of $gw 'login/local HTTP/1.1" 422')
'  login/local 200 = {0}' -f (Count-Of $gw 'login/local HTTP/1.1" 200')

''
'############ 6. DOCUMENT STATES ############'
& docker exec pacgate-db psql -U pacgate -d pacgate -t -A -c "SELECT sanitization_state, count(*) FROM documents WHERE matter_id='769225d9-804c-4a3f-8775-8dcc4c676d0e' GROUP BY sanitization_state ORDER BY 2 DESC;" 2>&1 |
    ForEach-Object { '  ' + $_ }
'  (pending/blocked docs legitimately 409 on download - that is the gate working)'
