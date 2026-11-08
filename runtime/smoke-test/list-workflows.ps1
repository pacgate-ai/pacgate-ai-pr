# Smoke-test: what does the workflow API actually serve?
$ErrorActionPreference = 'Stop'
$env:HTTPS_PROXY = ''; $env:HTTP_PROXY = ''; $env:https_proxy = ''; $env:http_proxy = ''

$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$base = 'http://127.0.0.1:8089/pacgate'
$token = (Get-Content (Join-Path $repo 'runtime\smoke-test\.token') -Raw).Trim()
$H = @{ Authorization = "Bearer $token" }

$list = Invoke-RestMethod -Uri "$base/api/workflows" -Headers $H -TimeoutSec 30
$arr = if ($list.workflows) { $list.workflows } else { $list }
Write-Output "WORKFLOWS_SERVED=$(@($arr).Count)"

$byCat = $arr | Group-Object category | Sort-Object Count -Descending
Write-Output "CATEGORIES=$($byCat.Count)"
Write-Output ''
Write-Output '--- top categories ---'
$byCat | Select-Object -First 8 | ForEach-Object { Write-Output ("  {0,-28} {1}" -f $_.Name, $_.Count) }

Write-Output ''
Write-Output '--- steps per workflow: distribution ---'
$steps = $arr | ForEach-Object { [int]$_.step_count }
$zero = @($steps | Where-Object { $_ -eq 0 }).Count
Write-Output "  min=$($steps | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum)  max=$($steps | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)  total=$(($steps | Measure-Object -Sum).Sum)  zero-step=$zero"

Write-Output ''
Write-Output '--- the categories endpoint ---'
$cats = Invoke-RestMethod -Uri "$base/api/workflows/categories" -Headers $H -TimeoutSec 30
$carr = if ($cats.categories) { $cats.categories } else { $cats }
Write-Output "CATEGORIES_ENDPOINT=$(@($carr).Count)"

# Persist for later comparison
$arr | Select-Object id, name, category, step_count | ConvertTo-Json -Depth 4 |
    Set-Content (Join-Path $repo 'runtime\smoke-test\workflows-served.json') -Encoding UTF8
Write-Output 'SAVED'
