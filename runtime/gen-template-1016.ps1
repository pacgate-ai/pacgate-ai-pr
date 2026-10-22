$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root

$src = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
$raw = [System.IO.File]::ReadAllText((Join-Path $root $src), [System.Text.Encoding]::UTF8)

# Replace every secret with its ${VAR} placeholder.
# Order matters: longest/most-specific first.
$map = [ordered]@{
  # vaquill embeds the key in the URL path
  'https://mcp.vaquill.ai/s/vq_key_8uNHEHBpJ7rLl24ZX69Dl-mrrjgsnL_7' = 'https://mcp.vaquill.ai/s/${VAQUILL_API_KEY}'
}
# Generic: any "Bearer <token>" -> "Bearer ${VAR}" per connector family.
# Do these by scanning each server block instead of blind regex.

$j = $raw | ConvertFrom-Json

# Family -> env var name
function VarFor($name) {
  switch -Regex ($name) {
    '^yuandian-'   { return 'YUANDIAN_API_KEY' }
    '^pkulaw-'     { return 'PKULAW_API_KEY' }
    '^qcc-'        { return 'QCC_API_KEY' }
    '^ansvar'      { return 'ANSVAR_API_KEY' }
    '^firecrawl'   { return 'FIRECRAWL_API_KEY' }
    '^vaquill'     { return 'VAQUILL_API_KEY' }
    default        { return $null }
  }
}

foreach ($p in $j.mcpServers.PSObject.Properties) {
  $n = $p.Name; $s = $p.Value
  $v = VarFor $n
  if (-not $v) { continue }
  if ($s.headers -and $s.headers.Authorization) {
    $s.headers.Authorization = 'Bearer ${' + $v + '}'
  }
  if ($s.env) {
    foreach ($e in @($s.env.PSObject.Properties)) {
      if ($e.Name -match 'AUTHORIZATION|API_KEY') {
        $s.env.($e.Name) = 'Bearer ${' + $v + '}'
      }
    }
  }
  if ($s.url -and $s.url -match 'vq_key_') {
    $s.url = 'https://mcp.vaquill.ai/s/${VAQUILL_API_KEY}'
  }
}
# firecrawl env is a bare key, not "Bearer ..."
if ($j.mcpServers.firecrawl.env.FIRECRAWL_API_KEY) {
  $j.mcpServers.firecrawl.env.FIRECRAWL_API_KEY = '${FIRECRAWL_API_KEY}'
}
# qcc-document-mcp env
if ($j.mcpServers.'qcc-document-mcp'.env.QCC_DOCUMENT_AUTHORIZATION) {
  $j.mcpServers.'qcc-document-mcp'.env.QCC_DOCUMENT_AUTHORIZATION = 'Bearer ${QCC_API_KEY}'
}

$out = $j | ConvertTo-Json -Depth 12
$dst = "runtime\generated-template-1016.json"
[System.IO.File]::WriteAllText((Join-Path $root $dst), $out, (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("written: " + $dst)
Write-Output ("servers: " + ($j.mcpServers.PSObject.Properties | Measure-Object).Count)
Write-Output ""
Write-Output "=== leftover literal secrets? (should be 0) ==="
$leak = 0
foreach ($pat in @('sk_','fc-','M8N','632','vq_key_8uN','17cb3712')) {
  $c = ([regex]::Matches($out, [regex]::Escape($pat))).Count
  if ($c -gt 0) { Write-Output ("  LEAK: '$pat' x$c"); $leak += $c }
}
if ($leak -eq 0) { Write-Output "  none - clean" }
Write-Output ""
Write-Output "=== placeholders present ==="
[regex]::Matches($out, '\$\{[A-Z_]+\}') | ForEach-Object { $_.Value } | Group-Object | ForEach-Object {
  Write-Output ("  {0,-32} x{1}" -f $_.Name, $_.Count)
}
