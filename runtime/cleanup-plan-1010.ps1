# Cleanup PLAN (dry-run): classify 1497 untracked runtime files into keep/delete
# NO DELETION - produces candidate list only
$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$out = "$root\runtime\cleanup-plan-1010.txt"
$env:Path += ";C:\Program Files\Git\cmd"
"=== CLEANUP PLAN (DRY RUN) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8

$untracked = @(git -C $root ls-files --others --exclude-standard runtime/)

# --- KEEP rules ---
$today = Get-Date "2026-10-10 00:00"
$keepExact = @(
  "runtime/README.md",
  "runtime/deerflow-provision-user.py",
  "runtime/HANDOFF-AIPC-0.1.17.upstream.md",
  "runtime/AIPC1-DIAGNOSIS-REPORT-1010.md",
  "runtime/CLEANUP-REPORT-2026-10-10.md",
  "runtime/BENCHMARK-REPORT-2026-10-10-v0.1.25.md",
  "runtime/ANALYSIS-summ-1010.md",
  "runtime/ROOT-CAUSE-1010-e2e-errors.md",
  "runtime/REGRESSION-AUDIT-1010.md",
  "runtime/archive-scratch-2026-10-10.zip"
)
$keepPatterns = @(
  '^runtime/diag[0-9]', '^runtime/e2e-(fallback|warm)-1010', '^runtime/validate-config-1010',
  '^runtime/cleanup-(audit|zip-inspect|plan)-1010', '^runtime/debug-1009/',
  '^runtime/relocate/', '^runtime/backup-', '^runtime/RUNTIME-INVENTORY',
  '^runtime/runtime-inventory', '^runtime/capture-runtime'
)
$keep = @(); $del = @()
foreach ($u in $untracked) {
  $hit = $false
  foreach ($k in $keepExact) { if ($u -eq $k) { $hit = $true; break } }
  if (-not $hit) { foreach ($p in $keepPatterns) { if ($u -match $p) { $hit = $true; break } } }
  if ($hit) { $keep += $u } else { $del += $u }
}
# age check on delete candidates: anything modified TODAY is kept regardless
$delFinal = @(); $delToday = @()
foreach ($d in $del) {
  $p = Join-Path $root ($d -replace '/','\')
  if (Test-Path -LiteralPath $p) {
    $item = Get-Item -LiteralPath $p
    if ($item.LastWriteTime -ge $today) { $delToday += $d } else { $delFinal += $d }
  } else { $delFinal += $d }  # gone already
}
$sz = 0; foreach ($d in $delFinal) { $p = Join-Path $root ($d -replace '/','\'); if (Test-Path -LiteralPath $p) { $sz += (Get-Item -LiteralPath $p).Length } }
$szK = 0; foreach ($d in $keep) { $p = Join-Path $root ($d -replace '/','\'); if (Test-Path -LiteralPath $p) { $szK += (Get-Item -LiteralPath $p).Length } }

"untracked total: $($untracked.Count)" | Add-Content $out -Encoding UTF8
"KEEP: $($keep.Count) files ($([math]::Round($szK/1MB,1)) MB)" | Add-Content $out -Encoding UTF8
"DELETE candidates: $($delFinal.Count) files ($([math]::Round($sz/1MB,1)) MB)" | Add-Content $out -Encoding UTF8
"kept-because-modified-today (reclassified): $($delToday.Count)" | Add-Content $out -Encoding UTF8
$delToday | ForEach-Object { "  TODAY-KEEP: $_" } | Add-Content $out -Encoding UTF8

"`n===== DELETE CANDIDATES by family =====" | Add-Content $out -Encoding UTF8
$delFinal | Group-Object { ($_.BaseName -replace '\d+','') -replace '\-+$','' } | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object {
  ("  {0,4}x {1}" -f $_.Count, ($_.Name + "*")) | Add-Content $out -Encoding UTF8
}

"`n===== DELETE CANDIDATES by age =====" | Add-Content $out -Encoding UTF8
$now = Get-Date
$delFinal | ForEach-Object { $p = Join-Path $root ($_ -replace '/','\'); if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).LastWriteTime } } | Group-Object { $_.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
  ("  $($_.Name)  $($_.Count) files") | Add-Content $out -Encoding UTF8
}

"`n===== FULL DELETE LIST (first 80) =====" | Add-Content $out -Encoding UTF8
$delFinal | Select-Object -First 80 | ForEach-Object { "  $_" } | Add-Content $out -Encoding UTF8
$delFinal | Set-Content "$root\runtime\cleanup-delete-list-1010.txt" -Encoding UTF8
"full list saved: runtime/cleanup-delete-list-1010.txt ($($delFinal.Count) lines)" | Add-Content $out -Encoding UTF8
Get-Content $out -Encoding UTF8 | Select-Object -First 60 | Out-Host
