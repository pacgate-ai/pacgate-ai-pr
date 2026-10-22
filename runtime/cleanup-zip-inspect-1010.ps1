# Inspect the scratch archive zip + cross-reference untracked files
$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$out = "$root\runtime\cleanup-zip-inspect-1010.txt"
"=== ZIP INSPECT - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }

$zip = "$root\runtime\archive-scratch-2026-10-10.zip"
Add-Sec "1. ZIP metadata"
$f = Get-Item $zip
"size=$([math]::Round($f.Length/1MB,1))MB created=$($f.CreationTime) modified=$($f.LastWriteTime)" | Add-Content $out -Encoding UTF8

Add-Sec "2. ZIP contents (entry count + top-level breakdown)"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$za = [System.IO.Compression.ZipFile]::OpenRead($zip)
"entries: $($za.Entries.Count)" | Add-Content $out -Encoding UTF8
$za.Entries | Group-Object { ($_.FullName -split '/')[0..1] -join '/' } | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object {
  $sz = ($_.Group | Measure-Object Length -Sum).Sum
  ("  {0,5} entries {1,10:N1} MB  {2}" -f $_.Count, ($sz/1MB), $_.Name) | Add-Content $out -Encoding UTF8
}
$za.Entries | Group-Object { ($_.FullName -split '/')[0] } | ForEach-Object {
  $sz = ($_.Group | Measure-Object Length -Sum).Sum
  ("TOP {0,-30} {1,6} entries {2,10:N1} MB" -f $_.Name, $_.Count, ($sz/1MB)) | Add-Content $out -Encoding UTF8
}
$za.Dispose()

Add-Sec "3. Do the 1494 untracked runtime files still exist on disk?"
$env:Path += ";C:\Program Files\Git\cmd"
$untracked = @(git -C $root ls-files --others --exclude-standard runtime/ | Select-Object -First 5)
"sample untracked (first 5): $($untracked.Count)" | Add-Content $out -Encoding UTF8
$untracked | ForEach-Object { "  $_" } | Add-Content $out -Encoding UTF8
$untrackedAll = @(git -C $root ls-files --others --exclude-standard runtime/)
"total untracked-nonignored in runtime: $($untrackedAll.Count)" | Add-Content $out -Encoding UTF8
$szUntracked = 0
foreach ($u in $untrackedAll) { $p = Join-Path $root $u; if (Test-Path $p) { $szUntracked += (Get-Item $p).Length } }
"untracked total size on disk: {0:N1} MB" -f ($szUntracked/1MB) | Add-Content $out -Encoding UTF8

Add-Sec "4. Overlap: how many untracked files are INSIDE the zip?"
$za2 = [System.IO.Compression.ZipFile]::OpenRead($zip)
$zipNames = @{}
foreach ($e in $za2.Entries) { $zipNames[$e.FullName.ToLower()] = $true }
$za2.Dispose()
$inZip = 0; $notInZip = 0; $notInZipSample = @()
foreach ($u in $untrackedAll) {
  $rel = $u -replace '^runtime/',''
  $cands = @($rel, "runtime/$rel", $u) | ForEach-Object { $_.ToLower() }
  $hit = $false
  foreach ($c in $cands) { if ($zipNames.ContainsKey($c)) { $hit = $true; break } }
  if ($hit) { $inZip++ } else { $notInZip++; if ($notInZipSample.Count -lt 15) { $notInZipSample += $u } }
}
"untracked files found inside zip: $inZip" | Add-Content $out -Encoding UTF8
"untracked files NOT in zip: $notInZip" | Add-Content $out -Encoding UTF8
$notInZipSample | ForEach-Object { "  NOT-IN-ZIP: $_" } | Add-Content $out -Encoding UTF8

Add-Sec "5. Root loose stale files (mcp_verify etc.)"
foreach ($n in @("mcp_verify.txt","mcp_final_verify.txt","verify_mcp.txt","containers.txt")) {
  $p = Join-Path $root $n
  if (Test-Path $p) { $i = Get-Item $p; "  $n  $([math]::Round($i.Length/1KB,1))KB  modified=$($i.LastWriteTime)" | Add-Content $out -Encoding UTF8 }
}
$env:Path += ";C:\Program Files\Git\cmd"
$rootTracked = @(git -C $root ls-files --error-unmatch mcp_verify.txt mcp_final_verify.txt verify_mcp.txt containers.txt 2>$null)
"tracked among them: $($rootTracked.Count)" | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Out-Host
