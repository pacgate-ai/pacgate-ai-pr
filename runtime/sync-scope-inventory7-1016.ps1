$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "RENDERED extensions-config: how are API keys stored?"
$ext = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
$raw = Get-Content $ext -Raw -Encoding UTF8
# Show structure of one connector WITHOUT printing secrets
$j = $raw | ConvertFrom-Json
foreach ($n in @("openviking","pacgate","firecrawl","yuandian-law","pkulaw-law-search","qcc-company","vaquill","ansvar","officecli")) {
  $s = $j.mcpServers.$n
  if ($s) {
    $keys = ($s.PSObject.Properties.Name -join ",")
    Write-Output ("  {0,-22} enabled={1,-6} fields=[{2}]" -f $n, $s.enabled, $keys)
  }
}
Write-Output ""
Write-Output "--- does the raw file contain literal secrets or placeholders? ---"
$lit = ([regex]::Matches($raw, '\$\{[A-Z_]+\}')).Count
Write-Output ("  `${{VAR}} placeholders in rendered file: " + $lit)
Write-Output ("  contains 'api_key' field: " + ($raw -match 'api_key'))
Write-Output ("  contains 'Authorization' field: " + ($raw -match 'Authorization'))

Section "TEMPLATE: what placeholders does it use?"
$tpl = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json"
$traw = Get-Content $tpl -Raw -Encoding UTF8
Write-Output $traw

Section "install.ps1 substitution logic (which vars get replaced)"
Select-String -Path "pacgate-ai/deploy/client-bundle/install.ps1" -Pattern '\.Replace\(' -Encoding UTF8 |
  ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

Section "Does the deer-flow IMAGE bake skills?"
docker exec deer-flow sh -c "ls /app/skills 2>/dev/null | head -20; echo '---count---'; ls /app/skills/public 2>/dev/null | wc -l" 2>$null

Section "What is actually mounted at /app/skills/public?"
docker inspect deer-flow | ConvertFrom-Json | ForEach-Object { $_.Mounts } |
  Where-Object { $_.Destination -match "skills" } |
  ForEach-Object { Write-Output ("  {0}  ->  {1}" -f $_.Source, $_.Destination) }

Section "PERSONAS: what does the README describe?"
Get-Content "pacgate-ai/deploy/client-bundle/personas/README.md" -Encoding UTF8 | Select-Object -First 40

Section "Where do personas get loaded from? (config)"
Select-String -Path "pacgate-ai/deploy/client-bundle/deer-flow-config.yaml" -Pattern "persona|agent" -Encoding UTF8 |
  Select-Object -First 20 | ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
