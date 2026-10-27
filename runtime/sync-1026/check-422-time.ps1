# When did the 21 login 422s happen, and from where?
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1)
$ErrorActionPreference = $prevEap

$last = '?'
$found = @()
foreach ($l in $gw) {
    $s = "$l"
    if ($s -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $last = $Matches[1] }
    if ($s -match 'login/local.*422') {
        # capture client ip too
        $ip = if ($s -match '(''\d+\.\d+\.\d+\.\d+'')|(\d+\.\d+\.\d+\.\d+):\d+') { $Matches[0] } else { '?' }
        $found += [pscustomobject]@{ TS = $last; IP = $ip; Line = $s.Substring(0, [Math]::Min(110, $s.Length)) }
    }
}

"count=$($found.Count)"
'=== first 5 ==='
$found | Select-Object -First 5 | ForEach-Object { '  {0}  {1}' -f $_.TS, $_.Line }
'=== last 5 ==='
$found | Select-Object -Last 5 | ForEach-Object { '  {0}  {1}' -f $_.TS, $_.Line }
'=== distinct timestamps ==='
$found | Group-Object TS | Sort-Object Name | ForEach-Object { '  {0}  x{1}' -f $_.Name, $_.Count }
