$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section ".env.example FULL content"
Get-Content "pacgate-ai/deploy/client-bundle/.env.example" -Encoding UTF8 | ForEach-Object { Write-Output ("  " + $_) }

Section "Are COURTLISTENER / FYOPEN used by ANY connector?"
$ext = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
$raw = Get-Content $ext -Raw -Encoding UTF8
foreach ($k in @("COURTLISTENER","FYOPEN","courtlistener","fyopen")) {
  Write-Output ("  {0,-16} in rendered config: {1}" -f $k, ($raw -match $k))
}
Write-Output "--- searched across deploy/ (non-data) ---"
Get-ChildItem "pacgate-ai/deploy" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch "\\data\\|node_modules" -and $_.Extension -in @(".json",".yaml",".yml",".ps1",".py",".md") } |
  Select-String -Pattern "COURTLISTENER_API_KEY|FYOPEN_API_KEY" -Encoding UTF8 -ErrorAction SilentlyContinue |
  Select-Object -First 12 | ForEach-Object { Write-Output ("  {0}:{1}" -f $_.Filename, $_.LineNumber) }

Section "install.ps1 render block TAIL (backup/compare/report)"
Get-Content "pacgate-ai/deploy/client-bundle/install.ps1" -Encoding UTF8 |
  Select-Object -Skip 488 -First 45 | ForEach-Object { Write-Output ("  " + $_) }

Section "Does install.ps1 read .env into a hashtable? (how keys reach it)"
Select-String -Path "pacgate-ai/deploy/client-bundle/install.ps1" -Pattern 'envVars' -Encoding UTF8 |
  Select-Object -First 12 | ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "UPSTREAM .env.example — same 14 keys?"
$upEnv = git show upstream/main:deploy/client-bundle/.env.example 2>$null
if ($upEnv) { $upEnv | ForEach-Object { Write-Output ("  " + $_) } }

Section "UPSTREAM install.ps1 — same render block?"
$upInst = git show upstream/main:deploy/client-bundle/install.ps1 2>$null
if ($upInst) {
  $upInst | Select-String -Pattern '\.Replace\(' | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}
