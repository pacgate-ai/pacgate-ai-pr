$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "deer-flow-config.yaml — skills path setting"
Select-String -Path "pacgate-ai/deploy/client-bundle/deer-flow-config.yaml" -Pattern "skill" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "compose.bundle.yaml — the skills mount block (L198-212)"
Get-Content "pacgate-ai/deploy/client-bundle/compose.bundle.yaml" -Encoding UTF8 |
  Select-Object -Skip 195 -First 20 | ForEach-Object { Write-Output ("  " + $_) }

Section "compose.prod.yaml — skills mount?"
Select-String -Path "pacgate-ai/deploy/client-bundle/compose.prod.yaml" -Pattern "skills" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "UPSTREAM compose.prod.yaml — skills mount?"
$upProd = git show upstream/main:deploy/client-bundle/compose.prod.yaml 2>$null
if ($upProd) { $upProd | Select-String -Pattern "skills" | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) } }

Section "deer-flow repo: skills/public top-level structure"
Push-Location deer-flow
Write-Output ("  HEAD: " + (git rev-parse --short HEAD))
Write-Output ("  skills/ dirs: " + ((Get-ChildItem skills -Directory).Name -join ", "))
Write-Output ("  skills/public dirs: " + (Get-ChildItem skills/public -Directory | Measure-Object).Count)
Write-Output ("  total size of skills/public: " + [math]::Round(((Get-ChildItem skills/public -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 2) + " MB")
Write-Output ("  total files: " + (Get-ChildItem skills/public -Recurse -File | Measure-Object).Count)
Pop-Location

Section "Is JZKK720/deer-flow main reachable for CI clone? (public)"
Write-Output "  (verified earlier: private=False for JZKK720/deer-flow)"

Section "What SHA would CI pin? fork/pacgate-layer vs origin/main"
Push-Location deer-flow
Write-Output ("  origin/main (JZKK720): " + (git rev-parse origin/main))
Write-Output ("  fork/pacgate-layer:    " + (git rev-parse fork/pacgate-layer))
Write-Output ("  local pacgate-layer:   " + (git rev-parse HEAD))
Write-Output ("  origin/main skills files: " + (git ls-tree -r --name-only origin/main -- skills/public | Measure-Object -Line).Lines)
Write-Output ("  fork/layer skills files:  " + (git ls-tree -r --name-only fork/pacgate-layer -- skills/public | Measure-Object -Line).Lines)
Pop-Location
