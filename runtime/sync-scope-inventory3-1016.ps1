$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "PATCH DELTA: local vs upstream"
$local = git ls-files pacgate-ai/deploy/client-bundle/patches | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
$up = git ls-tree -r --name-only upstream/main -- deploy/client-bundle/patches | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
Write-Output "--- local only (missing upstream) ---"
Compare-Object $local $up | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }
Write-Output "--- upstream only ---"
Compare-Object $local $up | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }

Section "MCP TEMPLATE content (upstream + local)"
$tpl = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json"
Write-Output "--- local template servers ---"
(Get-Content $tpl -Raw -Encoding UTF8 | ConvertFrom-Json).mcpServers.PSObject.Properties.Name | ForEach-Object { Write-Output ("  " + $_) }
Write-Output "--- upstream template servers ---"
$upTpl = git show upstream/main:deploy/client-bundle/deer-flow-extensions-config.template.json 2>$null
if ($upTpl) {
  ($upTpl -join "`n" | ConvertFrom-Json).mcpServers.PSObject.Properties.Name | ForEach-Object { Write-Output ("  " + $_) }
}

Section "Any OTHER extensions-config template with more servers?"
Get-ChildItem -Path . -Recurse -Filter "*extensions-config*" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch "node_modules|\\data\\" } |
  ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"") + "  (" + $_.Length + "b)") }

Section "SKILLS in deer-flow fork"
Push-Location deer-flow
git fetch fork --quiet 2>$null
Write-Output ("fork/pacgate-layer: " + (git rev-parse --short fork/pacgate-layer 2>$null))
Write-Output ("local pacgate-layer: " + (git rev-parse --short HEAD))
Write-Output ("origin/main (JZKK720): " + (git rev-parse --short origin/main 2>$null))
Write-Output ("skills/public in fork/pacgate-layer: " + (git ls-tree -r --name-only fork/pacgate-layer -- skills/public 2>$null | Measure-Object -Line).Lines)
Write-Output ("skills/public in origin/main: " + (git ls-tree -r --name-only origin/main -- skills/public 2>$null | Measure-Object -Line).Lines)
Pop-Location

Section ".deer-flow gitignore status"
$ig = git check-ignore -v -- deer-flow/.deer-flow 2>$null
Write-Output ("deer-flow/.deer-flow: " + $(if($ig){$ig}else{"NOT IGNORED"}))
Push-Location deer-flow
$ig2 = git check-ignore -v -- .deer-flow 2>$null
Write-Output (".deer-flow (in deer-flow repo): " + $(if($ig2){$ig2}else{"NOT IGNORED"}))
Write-Output ("tracked .deer-flow files: " + (git ls-files .deer-flow | Measure-Object -Line).Lines)
Pop-Location

Section "SOUL files upstream?"
foreach ($p in @("deploy/ocr-agent/SOUL.md","deploy/sanitizer-agent/SOUL.md","deploy/client-bundle/personas/README.md")) {
  $n = (git ls-tree -r --name-only upstream/main -- $p 2>$null | Measure-Object -Line).Lines
  Write-Output ("  {0,-52} upstream={1}" -f $p, $n)
}

Section "WORKFLOWS: local vs upstream content diff"
$wfLocal = git ls-files pacgate-ai/deploy/client-bundle/workflows | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
$wfUp = git ls-tree -r --name-only upstream/main -- deploy/client-bundle/workflows | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
Compare-Object $wfLocal $wfUp | ForEach-Object { Write-Output ("  " + $_.SideIndicator + " " + $_.InputObject) }
Write-Output "(no output above = identical file sets)"
