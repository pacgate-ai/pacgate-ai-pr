# Is the memory timeout pre-existing or introduced by the 86a9feb adoption?
# deer-flow was recreated at 2026-10-26T15:34:36Z, so its log covers that window.
# Compare outcomes BEFORE the 01:34 restart with AFTER it.
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1) -join "`n"
$ErrorActionPreference = $prevEap

$cut = '2026-10-27 01:34:52'
$rows = [regex]::Matches($gw, '(?m)^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*?(Memory updated successfully|Memory update failed: timed out|Failed to parse LLM response for memory update|refused as out of scope)')

$before = @(); $after = @()
foreach ($m in $rows) {
    $r = '{0}  {1}' -f $m.Groups[1].Value, $m.Groups[2].Value
    if ($m.Groups[1].Value -lt $cut) { $before += $r } else { $after += $r }
}

'=== BEFORE the 01:34 restart (post-86a9feb, pre-restart) ==='
"  events=$($before.Count)"
$before | ForEach-Object { '  ' + $_ }
foreach ($k in @('updated successfully', 'timed out', 'Failed to parse', 'out of scope')) {
    '    {0,-22} {1}' -f $k, (@($before | Where-Object { $_ -match [regex]::Escape($k) }).Count)
}

''
'=== AFTER the 01:34 restart ==='
"  events=$($after.Count)"
$after | ForEach-Object { '  ' + $_ }
foreach ($k in @('updated successfully', 'timed out', 'Failed to parse', 'out of scope')) {
    '    {0,-22} {1}' -f $k, (@($after | Where-Object { $_ -match [regex]::Escape($k) }).Count)
}

''
'=== earliest line in the deer-flow log (bounds the comparison) ==='
$first = ($gw -split "`n")[0]
'  ' + $first.Substring(0, [Math]::Min(130, $first.Length))
