$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
$out = "runtime\plan-inputs-1016.txt"
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "===== install.ps1 L405-500 (render block, exact) ====="
$i = 0
Get-Content "pacgate-ai/deploy/client-bundle/install.ps1" -Encoding UTF8 | ForEach-Object {
  $i++
  if ($i -ge 405 -and $i -le 500) { W ("{0,4}: {1}" -f $i, $_) }
}

W ""
W "===== compose.bundle.yaml L195-215 (skills mount, exact) ====="
$i = 0
Get-Content "pacgate-ai/deploy/client-bundle/compose.bundle.yaml" -Encoding UTF8 | ForEach-Object {
  $i++
  if ($i -ge 195 -and $i -le 215) { W ("{0,4}: {1}" -f $i, $_) }
}

W ""
W "===== .env.example tail (connector section, exact) ====="
$i = 0
Get-Content "pacgate-ai/deploy/client-bundle/.env.example" -Encoding UTF8 | ForEach-Object {
  $i++
  if ($i -ge 100) { W ("{0,4}: {1}" -f $i, $_) }
}

W ""
W "===== build-ghcr.yml (full) ====="
$wf = "pacgate-ai/.github/workflows/build-ghcr.yml"
if (Test-Path $wf) {
  $i = 0
  Get-Content $wf -Encoding UTF8 | ForEach-Object { $i++; W ("{0,4}: {1}" -f $i, $_) }
} else { W "MISSING: $wf" }

W ""
W "===== .dockerignore (full) ====="
$di = "pacgate-ai/.dockerignore"
if (Test-Path $di) {
  Get-Content $di -Encoding UTF8 | ForEach-Object { W ("  " + $_) }
} else { W "MISSING: $di" }

[System.IO.File]::WriteAllText((Join-Path $root $out), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("written: " + $out + "  (" + $sb.Length + " chars)")
