# Did the agent RECOVER from each 409 (sanitize -> 200), or loop on it?
# This is the behavioural question the prompt guidance is supposed to control.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$mcp = (& docker logs pacgate-mcp 2>&1)
$ErrorActionPreference = $prevEap

'=== every document route call, in order, with timestamps ==='
$events = @()
for ($i = 0; $i -lt $mcp.Count; $i++) {
    $line = "$($mcp[$i])"
    if ($line -match 'documents/([^\s"]+)/(download|sanitize|sanitize-status)[^"]*"\s*(?:HTTP/[0-9.]+ )?(\d{3})') {
        # Capture FIRST: the backward scan below re-runs -match and would
        # overwrite $Matches, which silently produced empty Doc/Op/Code fields.
        $doc = $Matches[1]; $op = $Matches[2]; $code = $Matches[3]
        $ts = '?'
        for ($j = $i; $j -ge [Math]::Max(0, $i - 4); $j--) {
            if ("$($mcp[$j])" -match '(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $ts = $Matches[1]; break }
        }
        $events += [pscustomobject]@{ TS = $ts; Doc = $doc; Op = $op; Code = $code }
    }
}
"events=$($events.Count)"
$events | ForEach-Object { '  {0}  {1,-10} {2,-16} {3}' -f $_.TS, $_.Op, $_.Code, $_.Doc }

''
'=== per-document verdict ==='
$events | Group-Object Doc | ForEach-Object {
    $ops = ($_.Group | ForEach-Object { "$($_.Op):$($_.Code)" }) -join ' -> '
    $had409 = @($_.Group | Where-Object { $_.Code -eq '409' }).Count
    $ok = @($_.Group | Where-Object { $_.Code -eq '200' }).Count
    $verdict = if ($had409 -gt 0 -and $ok -gt 0) { 'RECOVERED' } elseif ($had409 -gt 0) { 'still refused' } else { 'ok' }
    '  {0,-40} {1,-12} {2}' -f $_.Name, $verdict, $ops
}
