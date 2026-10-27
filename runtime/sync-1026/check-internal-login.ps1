# 13 x 422 on /api/v1/auth/login/local at 02:16:47 from 127.0.0.1 - i.e. from
# INSIDE the deer-flow container. What calls it, and with what body?
# 127.0.0.1 rules out the browser (which would arrive via nginx on the LAN IP).
$ErrorActionPreference = 'Stop'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1)
$ErrorActionPreference = $prevEap

'=== all lines at 2026-10-27 02:16:4x (the whole second, all services) ==='
foreach ($l in $gw) {
    $s = "$l"
    if ($s -match '2026-10-27 02:16:4') {
        '  ' + $s.Substring(0, [Math]::Min(190, $s.Length))
    }
}

''
'=== does anything in the tree call login/local with a JSON body? ==='
$root = 'C:\Users\pacga\github-pr\pacgate-law'
$hits = Get-ChildItem -Recurse -File -Include *.py,*.ts,*.tsx,*.ps1 -Path `
    (Join-Path $root 'pacgate-ai\deploy'), (Join-Path $root 'deer-flow\frontend\src'), (Join-Path $root 'deer-flow\backend') -ErrorAction SilentlyContinue |
Select-String -Pattern 'login/local'
$hits | ForEach-Object { '  {0}:{1}: {2}' -f $_.Path.Replace($root, ''), $_.LineNumber, $_.Line.Trim() } |
    Select-Object -First 12
