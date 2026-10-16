$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section ".env vs .env.example — which KEYS are local-only"
$envF = "pacgate-ai/deploy/client-bundle/.env"
$exF  = "pacgate-ai/deploy/client-bundle/.env.example"
function Keys($p) {
  if (-not (Test-Path $p)) { return @() }
  Get-Content $p -Encoding UTF8 | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=' } |
    ForEach-Object { ($_ -split '=')[0].Trim() } | Sort-Object -Unique
}
$kEnv = Keys $envF
$kEx  = Keys $exF
Write-Output ("live .env keys: " + $kEnv.Count + "   .env.example keys: " + $kEx.Count)
Write-Output "--- in .env but NOT in .env.example (local-only settings) ---"
Compare-Object $kEnv $kEx | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }
Write-Output "--- in .env.example but NOT in .env ---"
Compare-Object $kEnv $kEx | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }

Section "NON-SECRET settings in .env (values shown for non-secret keys)"
$secretPat = 'PASS|SECRET|TOKEN|KEY|PWD|CREDENTIAL|SALT'
Get-Content $envF -Encoding UTF8 | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=' } | ForEach-Object {
  $k = ($_ -split '=')[0].Trim()
  $v = ($_ -split '=',2)[1]
  if ($k -match $secretPat) { Write-Output ("  {0,-42} = <redacted len={1}>" -f $k, $v.Length) }
  else { Write-Output ("  {0,-42} = {1}" -f $k, $v) }
}

Section "AGENTS (provisioned) — where do they live?"
$agDir = "pacgate-ai/deploy/client-bundle/data/deer-flow/users"
if (Test-Path $agDir) {
  Get-ChildItem $agDir -Directory | ForEach-Object {
    $u = $_.Name
    $a = Join-Path $_.FullName "agents"
    if (Test-Path $a) {
      Get-ChildItem $a -Directory | ForEach-Object { Write-Output ("  user=$u agent=" + $_.Name) }
    }
  }
}
Write-Output "--- agent definitions tracked in repo? ---"
Get-ChildItem -Path "pacgate-ai/deploy" -Recurse -Filter "*.md" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "agent" -and $_.FullName -notmatch "\\data\\" } |
  ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }

Section "SKILLS: which 3 are in fork but not origin/main?"
Push-Location deer-flow
$f = git ls-tree -r --name-only fork/pacgate-layer -- skills/public 2>$null | Sort-Object
$o = git ls-tree -r --name-only origin/main -- skills/public 2>$null | Sort-Object
Compare-Object $f $o | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Write-Output ("  fork-only: " + $_.InputObject) }
Write-Output "--- deer-flow PRs on JZKK720 ---"
Pop-Location

Section "MATTERS — what is a 'matter' here?"
Write-Output "--- matter-related files in repo (non-data) ---"
Get-ChildItem -Path "pacgate-ai" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "matter" -and $_.FullName -notmatch "\\data\\|node_modules|\\target\\" } |
  Select-Object -First 25 | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }
Write-Output "--- live matters in DB ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(*) from matters;" 2>$null
Write-Output "--- live tenants/users ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select (select count(*) from tenants) as tenants, (select count(*) from users) as users;" 2>$null
