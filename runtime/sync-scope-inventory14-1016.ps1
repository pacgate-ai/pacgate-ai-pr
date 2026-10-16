$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "CI workflow: build-ghcr.yml"
$wf = "pacgate-ai/.github/workflows/build-ghcr.yml"
if (Test-Path $wf) {
  Write-Output ("  lines: " + (Get-Content $wf | Measure-Object -Line).Lines)
  Get-Content $wf -Encoding UTF8 | ForEach-Object { Write-Output ("  " + $_) }
} else { Write-Output "  MISSING" }

Section ".dockerignore at platform root"
$di = "pacgate-ai/.dockerignore"
if (Test-Path $di) { Get-Content $di -Encoding UTF8 | ForEach-Object { Write-Output ("  " + $_) } } else { Write-Output "  MISSING" }

Section "Where is the build context root for deer-flow-pacgate?"
Write-Output "  Dockerfile: deploy/deer-flow-pacgate/Dockerfile"
Write-Output "  COPY paths used:"
Select-String -Path "pacgate-ai/deploy/deer-flow-pacgate/Dockerfile" -Pattern "^COPY|^ADD" -Encoding UTF8 |
  ForEach-Object { Write-Output ("    " + $_.Line.Trim()) }
Write-Output "  => context must contain: pacgate-adapters/, deploy/deer-flow-pacgate/config.yaml"

Section "Does the repo have a skills dir at platform root?"
foreach ($p in @("pacgate-ai/skills","pacgate-ai/deploy/client-bundle/skills","pacgate-ai/deploy/skills")) {
  Write-Output ("  {0,-46} exists={1}" -f $p, (Test-Path $p))
}

Section "deer-flow repo: is it a submodule of pacgate-ai-pr?"
Write-Output ("  .gitmodules exists: " + (Test-Path "pacgate-ai/.gitmodules"))
if (Test-Path "pacgate-ai/.gitmodules") { Get-Content "pacgate-ai/.gitmodules" -Encoding UTF8 | ForEach-Object { Write-Output ("    " + $_) } }

Section "CI: does it have a checkout step for deer-flow?"
$wfRaw = Get-Content $wf -Raw -Encoding UTF8
Write-Output ("  mentions 'deer-flow' clone: " + ($wfRaw -match "deer-flow"))
Write-Output ("  mentions 'repository:' : " + ($wfRaw -match "repository:"))
Write-Output ("  mentions 'actions/checkout': " + ($wfRaw -match "actions/checkout"))

Section "UPSTREAM build-ghcr.yml — same?"
$upWf = git show upstream/main:.github/workflows/build-ghcr.yml 2>$null
if ($upWf) {
  Write-Output ("  upstream lines: " + $upWf.Count)
  $upWf | Select-String -Pattern "checkout|repository:|context:|file:|deer-flow|skills" |
    ForEach-Object { Write-Output ("    " + $_.Line.Trim()) }
}

Section "How does the frontend image get its source? (precedent for cross-repo)"
Select-String -Path "pacgate-ai/deploy/deer-flow-frontend-pacgate/Dockerfile" -Pattern "^COPY|^ADD|^FROM|^ARG" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
Write-Output "--- deploy/deer-flow-src present? ---"
Write-Output ("  deploy/deer-flow-src exists: " + (Test-Path "pacgate-ai/deploy/deer-flow-src"))
if (Test-Path "pacgate-ai/deploy/deer-flow-src") {
  Write-Output ("  tracked files: " + (git ls-files pacgate-ai/deploy/deer-flow-src | Measure-Object -Line).Lines)
  Write-Output ("  ignored: " + (git check-ignore -v -- pacgate-ai/deploy/deer-flow-src 2>$null))
}
