$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root

$src = "pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json"
$txt = [System.IO.File]::ReadAllText((Join-Path $root $src), [System.Text.Encoding]::UTF8)

# TEXT-LEVEL substitution: preserves formatting, key order, and CJK exactly.
# Each entry: literal secret -> placeholder. Longest first to avoid partial hits.
$subs = [ordered]@{
  # OpenViking root key (already a placeholder in the current template)
  '17cb371236735c7469b933643d10ea6a' = '${OPENVIKING_ROOT_API_KEY}'
  # vaquill: key is embedded in the URL path
  'https://mcp.vaquill.ai/s/vq_key_8uNHEHBpJ7rLl24ZX69Dl-mrrjgsnL_7' = 'https://mcp.vaquill.ai/s/${VAQUILL_API_KEY}'
}

# Family-based Bearer replacement: find every "Bearer <token>" and map by the
# enclosing server name. Do it by locating each server block.
$lines = $txt -split "`n"
$current = $null
$outLines = New-Object System.Collections.Generic.List[string]

function VarFor($name) {
  switch -Regex ($name) {
    '^yuandian-' { return 'YUANDIAN_API_KEY' }
    '^pkulaw-'   { return 'PKULAW_API_KEY' }
    '^qcc-'      { return 'QCC_API_KEY' }
    '^ansvar'    { return 'ANSVAR_API_KEY' }
    '^firecrawl' { return 'FIRECRAWL_API_KEY' }
    '^vaquill'   { return 'VAQUILL_API_KEY' }
    default      { return $null }
  }
}

foreach ($line in $lines) {
  # Detect a server key: 4-space indent, quoted name, colon, opening brace
  if ($line -match '^    "([^"]+)":\s*\{') { $current = $Matches[1] }
  $v = if ($current) { VarFor $current } else { $null }

  if ($v) {
    # "Authorization": "Bearer <token>"  ->  "Bearer ${VAR}"
    $line = $line -replace '("Authorization"\s*:\s*)"Bearer [^"]*"', ('$1"Bearer ${' + $v + '}"')
    # "QCC_DOCUMENT_AUTHORIZATION": "Bearer <token>"
    $line = $line -replace '("QCC_DOCUMENT_AUTHORIZATION"\s*:\s*)"Bearer [^"]*"', ('$1"Bearer ${' + $v + '}"')
    # "FIRECRAWL_API_KEY": "<token>"  (bare, no Bearer)
    if ($current -eq 'firecrawl') {
      $line = $line -replace '("FIRECRAWL_API_KEY"\s*:\s*)"[^"]*"', '$1"${FIRECRAWL_API_KEY}"'
    }
  }
  $outLines.Add($line)
}

$out = ($outLines -join "`n")
foreach ($k in $subs.Keys) { $out = $out.Replace($k, $subs[$k]) }

$dst = "runtime\generated-template-1016.json"
[System.IO.File]::WriteAllText((Join-Path $root $dst), $out, (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("written: " + $dst)
Write-Output ""
Write-Output "=== LEAK CHECK (must be 0) ==="
$leak = 0
foreach ($pat in @('sk_','fc-6b9','M8N','632','vq_key_8uN','17cb3712','Bearer sk','Bearer M8N','Bearer 632','Bearer fc-')) {
  $c = ([regex]::Matches($out, [regex]::Escape($pat))).Count
  if ($c -gt 0) { Write-Output ("  LEAK: '$pat' x$c"); $leak += $c }
}
if ($leak -eq 0) { Write-Output "  CLEAN - no literal secrets" }
Write-Output ""
Write-Output "=== placeholders ==="
[regex]::Matches($out, '\$\{[A-Z_]+\}') | ForEach-Object { $_.Value } | Group-Object | Sort-Object Name | ForEach-Object {
  Write-Output ("  {0,-32} x{1}" -f $_.Name, $_.Count)
}
Write-Output ""
Write-Output "=== CJK preserved? ==="
$cjk = ([regex]::Matches($out, '[\u4e00-\u9fff]')).Count
Write-Output ("  CJK chars: " + $cjk)
Write-Output ("  contains escaped \\u: " + ($out -match '\\u[0-9a-f]{4}'))
Write-Output ""
Write-Output "=== server count ==="
Write-Output ("  " + ([regex]::Matches($out, '(?m)^    "[^"]+":\s*\{')).Count)
Write-Output ""
Write-Output "=== valid JSON? ==="
try { $null = $out | ConvertFrom-Json; Write-Output "  YES" } catch { Write-Output ("  NO: " + $_.Exception.Message) }
