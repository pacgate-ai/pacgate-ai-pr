$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root

function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "WRAPPER REPO"
Write-Output ("HEAD: " + (git rev-parse --short HEAD))
Write-Output ("branch: " + (git rev-parse --abbrev-ref HEAD))
Write-Output ("tracked files: " + (git ls-files | Measure-Object -Line).Lines)

Section "CAPABILITY FILE TRACKING (wrapper)"
$paths = @(
  "pacgate-ai/deploy/client-bundle/workflows",
  "pacgate-ai/deploy/client-bundle/personas",
  "pacgate-ai/deploy/client-bundle/patches",
  "pacgate-ai/deploy/client-bundle/nginx",
  "pacgate-ai/deploy/client-bundle/deer-flow-config.yaml",
  "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json",
  "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json",
  "pacgate-ai/deploy/client-bundle/.env",
  "pacgate-ai/deploy/client-bundle/.env.example",
  "pacgate-ai/deploy/client-bundle/compose.bundle.yaml",
  "pacgate-ai/deploy/client-bundle/compose.prod.yaml",
  "pacgate-ai/deploy/client-bundle/ollama-models.txt",
  "pacgate-ai/deploy/client-bundle/install.ps1",
  "pacgate-ai/deploy/client-bundle/data",
  "pacgate-ai/deploy/client-bundle/openviking"
)
foreach ($p in $paths) {
  $n = (git ls-files -- $p | Measure-Object -Line).Lines
  $ig = (git check-ignore -v -- $p 2>$null)
  $igShort = if ($ig) { "IGNORED" } else { "-" }
  Write-Output ("{0,-70} tracked={1,-5} {2}" -f $p, $n, $igShort)
}

Section "SKILLS (deer-flow)"
$sk = "deer-flow/skills/public"
if (Test-Path $sk) {
  Write-Output ("skill dirs: " + (Get-ChildItem $sk -Directory | Measure-Object).Count)
  Write-Output ("SKILL.md files: " + (Get-ChildItem $sk -Recurse -Filter SKILL.md | Measure-Object).Count)
} else { Write-Output "MISSING: $sk" }
Write-Output ("deer-flow tracked skills: " + (git ls-files deer-flow/skills | Measure-Object -Line).Lines)

Section "MCP CONNECTORS (live rendered config)"
$ext = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
if (Test-Path $ext) {
  $j = Get-Content $ext -Raw -Encoding UTF8 | ConvertFrom-Json
  $srv = $j.mcpServers.PSObject.Properties
  Write-Output ("total mcpServers: " + ($srv | Measure-Object).Count)
  $en = ($srv | Where-Object { $_.Value.enabled -eq $true } | Measure-Object).Count
  $dis = ($srv | Where-Object { $_.Value.enabled -ne $true } | Measure-Object).Count
  Write-Output ("enabled: $en   disabled: $dis")
  Write-Output "--- names ---"
  $srv | ForEach-Object { Write-Output ("  {0,-28} enabled={1}" -f $_.Name, $_.Value.enabled) }
} else { Write-Output "MISSING: $ext" }

Section "TEMPLATE (what install.ps1 renders from)"
$tpl = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json"
if (Test-Path $tpl) {
  $j2 = Get-Content $tpl -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Output ("template mcpServers: " + ($j2.mcpServers.PSObject.Properties | Measure-Object).Count)
  $j2.mcpServers.PSObject.Properties | ForEach-Object { Write-Output ("  " + $_.Name) }
} else { Write-Output "MISSING: $tpl" }

Section "WORKFLOWS"
$wf = "pacgate-ai/deploy/client-bundle/workflows"
if (Test-Path $wf) {
  Write-Output ("workflow files: " + (Get-ChildItem $wf -Recurse -File | Measure-Object).Count)
  Get-ChildItem $wf | Select-Object -First 10 -ExpandProperty Name | ForEach-Object { Write-Output ("  " + $_) }
}

Section "PERSONAS"
$pe = "pacgate-ai/deploy/client-bundle/personas"
if (Test-Path $pe) {
  Get-ChildItem $pe -Recurse -File | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }
}

Section "PATCHES (bind-mounted overrides)"
$pa = "pacgate-ai/deploy/client-bundle/patches"
if (Test-Path $pa) {
  Get-ChildItem $pa -Recurse -File | ForEach-Object { Write-Output ("  " + $_.Name + "  (" + $_.Length + " bytes)") }
}
