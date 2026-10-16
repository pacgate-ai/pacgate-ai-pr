$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

$ext = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
$j = Get-Content $ext -Raw -Encoding UTF8 | ConvertFrom-Json

Section "ALL 30 CONNECTORS — shape with secrets redacted"
foreach ($p in $j.mcpServers.PSObject.Properties) {
  $n = $p.Name; $s = $p.Value
  Write-Output ("--- $n  (enabled=$($s.enabled), type=$($s.type)) ---")
  if ($s.url) { Write-Output ("    url: " + $s.url) }
  if ($s.command) { Write-Output ("    command: " + $s.command + " " + ($s.args -join " ")) }
  if ($s.headers) {
    foreach ($h in $s.headers.PSObject.Properties) {
      $v = [string]$h.Value
      $shown = if ($v.Length -gt 24) { $v.Substring(0,10) + "...<len=" + $v.Length + ">" } else { $v }
      Write-Output ("    header {0}: {1}" -f $h.Name, $shown)
    }
  }
  if ($s.env) {
    foreach ($e in $s.env.PSObject.Properties) {
      $v = [string]$e.Value
      $shown = if ($v.Length -gt 24) { $v.Substring(0,10) + "...<len=" + $v.Length + ">" } else { $v }
      Write-Output ("    env {0}: {1}" -f $e.Name, $shown)
    }
  }
}

Section "DISTINCT header names used across connectors"
$j.mcpServers.PSObject.Properties | ForEach-Object {
  if ($_.Value.headers) { $_.Value.headers.PSObject.Properties.Name }
} | Sort-Object -Unique | ForEach-Object { Write-Output ("  " + $_) }

Section "DISTINCT env var names used across connectors"
$j.mcpServers.PSObject.Properties | ForEach-Object {
  if ($_.Value.env) { $_.Value.env.PSObject.Properties.Name }
} | Sort-Object -Unique | ForEach-Object { Write-Output ("  " + $_) }

Section "DISTINCT url hosts"
$j.mcpServers.PSObject.Properties | ForEach-Object {
  if ($_.Value.url) { ([uri]$_.Value.url).Host }
} | Sort-Object -Unique | ForEach-Object { Write-Output ("  " + $_) }

Section "install.ps1 — the extensions-config render block (L390-490)"
Get-Content "pacgate-ai/deploy/client-bundle/install.ps1" -Encoding UTF8 |
  Select-Object -Skip 388 -First 100 | ForEach-Object { Write-Output ("  " + $_) }
