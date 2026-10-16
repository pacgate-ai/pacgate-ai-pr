$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "SKILLS GAP VERIFICATION (JZKK720/deer-flow main)"
Push-Location deer-flow
foreach ($s in @("antitrust-compliance","arbitration","bankruptcy-restructuring","nda-review","ipo-legal-diligence")) {
  $inOrigin = (git ls-tree -r --name-only origin/main -- "skills/public/$s" 2>$null | Measure-Object -Line).Lines
  $inFork   = (git ls-tree -r --name-only fork/pacgate-layer -- "skills/public/$s" 2>$null | Measure-Object -Line).Lines
  $onDisk   = if (Test-Path "skills/public/$s") { (Get-ChildItem "skills/public/$s" -Recurse -File | Measure-Object).Count } else { 0 }
  Write-Output ("  {0,-28} origin/main={1,-4} fork/layer={2,-4} disk={3}" -f $s, $inOrigin, $inFork, $onDisk)
}
Write-Output "--- total skills/public file counts ---"
Write-Output ("  origin/main : " + (git ls-tree -r --name-only origin/main -- skills/public 2>$null | Measure-Object -Line).Lines)
Write-Output ("  fork/layer  : " + (git ls-tree -r --name-only fork/pacgate-layer -- skills/public 2>$null | Measure-Object -Line).Lines)
Write-Output ("  disk        : " + (Get-ChildItem skills/public -Recurse -File | Measure-Object).Count)
Pop-Location

Section "install.ps1 — how the extensions config is rendered"
$ip = "pacgate-ai/deploy/client-bundle/install.ps1"
Select-String -Path $ip -Pattern "extensions-config|mcpServers|template" -Encoding UTF8 |
  Select-Object -First 25 | ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "compose.bundle.yaml — skills mount?"
Select-String -Path "pacgate-ai/deploy/client-bundle/compose.bundle.yaml" -Pattern "skills|patches|extensions-config|deer-flow-config" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "UPSTREAM compose.bundle.yaml — same mounts?"
$upCompose = git show upstream/main:deploy/client-bundle/compose.bundle.yaml 2>$null
if ($upCompose) {
  $upCompose | Select-String -Pattern "skills|patches|extensions-config|deer-flow-config" |
    ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}

Section "VERSION PINS — local vs upstream"
Write-Output "--- local ---"
Select-String -Path "pacgate-ai/deploy/client-bundle/compose.bundle.yaml" -Pattern "image:\s*ghcr" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
Write-Output "--- upstream ---"
if ($upCompose) { $upCompose | Select-String -Pattern "image:\s*ghcr" | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) } }
