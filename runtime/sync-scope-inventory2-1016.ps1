$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "deer-flow ignored by wrapper?"
$ig = git check-ignore -v -- deer-flow 2>$null
Write-Output ("deer-flow: " + $(if ($ig) { $ig } else { "NOT IGNORED" }))
Write-Output ("deer-flow tracked files in wrapper: " + (git ls-files deer-flow | Measure-Object -Line).Lines)

Section "SKILLS location + deer-flow tracking"
$sk = "deer-flow/skills/public"
Get-ChildItem $sk -Directory | Select-Object -First 70 -ExpandProperty Name | ForEach-Object { Write-Output ("  " + $_) }

Section "SKILLS tracked in deer-flow repo"
Push-Location deer-flow
Write-Output ("deer-flow HEAD: " + (git rev-parse --short HEAD) + "  branch: " + (git rev-parse --abbrev-ref HEAD))
Write-Output ("skills/public tracked: " + (git ls-files skills/public | Measure-Object -Line).Lines)
Write-Output ("skills/public SKILL.md tracked: " + (git ls-files "skills/public/**/SKILL.md" | Measure-Object -Line).Lines)
Write-Output "--- remotes ---"
git remote -v
Write-Output "--- status (short) ---"
git status --short | Select-Object -First 25
Pop-Location

Section "PERSONAS real content"
$pe = "pacgate-ai/deploy/client-bundle/personas"
Get-ChildItem $pe -Recurse -Force | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"") + $(if($_.PSIsContainer){" [DIR]"}else{" ("+$_.Length+"b)"})) }

Section "Where else do personas/SOUL live?"
Get-ChildItem -Path . -Recurse -Filter "SOUL*.md" -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }

Section "UPSTREAM main state (JZKK720/pacgate-ai-pr)"
git fetch upstream --quiet 2>$null
Write-Output ("upstream/main: " + (git rev-parse --short upstream/main 2>$null))
Write-Output ("fork/main:     " + (git rev-parse --short fork/main 2>$null))
Write-Output "--- upstream tree: capability paths ---"
foreach ($p in @("deploy/client-bundle/workflows","deploy/client-bundle/patches","deploy/client-bundle/deer-flow-extensions-config.template.json","deploy/client-bundle/deer-flow-config.yaml","deploy/client-bundle/personas","skills")) {
  $n = (git ls-tree -r --name-only upstream/main -- $p 2>$null | Measure-Object -Line).Lines
  Write-Output ("  {0,-62} {1}" -f $p, $n)
}
