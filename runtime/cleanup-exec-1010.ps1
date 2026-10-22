# Cleanup EXECUTION (reversible-only): zip-then-delete stale ASCII scratch files
# + move the 368MB archive zip out of the workspace. NO tracked changes, NO CJK files touched.
$ErrorActionPreference = "Stop"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$out = "$root\runtime\cleanup-exec-1010.txt"
"=== CLEANUP EXECUTION - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Log($m) { $m | Add-Content $out -Encoding UTF8 }

# --- 1. Load + filter delete list ---
$list = Get-Content "$root\runtime\cleanup-delete-list-1010.txt"
$real = @(); $phantom = @(); $skipped = @()
foreach ($d in $list) {
  if ($d -eq "runtime/apply-wf-fix.ps1") { $skipped += $d; continue }   # referenced by tracked doc
  # git quotepath octal-escapes CJK as \NNN and wraps special paths in quotes -
  # the escaped form is ASCII but NOT a real path. Exclude any of these.
  if ($d -match '\\\d{3}' -or $d -match '"') { $phantom += $d; continue }
  $p = Join-Path $root ($d -replace '/','\')
  if (Test-Path -LiteralPath $p) {
    if ((Get-Item -LiteralPath $p).PSIsContainer) { $skipped += "$d (dir)"; continue }
    $real += $d
  } else { $skipped += "$d (missing)" }
}
Log "list total: $($list.Count)"
Log "real ASCII deletable: $($real.Count)"
Log "CJK/escaped (UNTOUCHED, for user review): $($phantom.Count)"
Log "skipped (referenced/dir/missing): $($skipped.Count)"
$phantom | Select-Object -First 10 | ForEach-Object { Log "  CJK-KEEP: $_" }
$skipped | ForEach-Object { Log "  SKIP: $_" }

# --- 2. Zip the real deletable files (reversible insurance) ---
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = "$root\runtime\archive-scripts-pre-1010.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [System.IO.File]::Create($zipPath)
$za = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
$zipped = 0; $zipBytes = 0
foreach ($d in $real) {
  $p = Join-Path $root ($d -replace '/','\')
  try {
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $entry = $za.CreateEntry($d)
    $es = $entry.Open(); $es.Write($bytes, 0, $bytes.Length); $es.Close()
    $zipped++; $zipBytes += $bytes.Length
  } catch { Log "  ZIP-FAIL: $d -> $($_.Exception.Message)" }
}
$za.Dispose(); $fs.Close()
Log "zipped: $zipped files ($([math]::Round($zipBytes/1KB,0)) KB raw) -> archive-scripts-pre-1010.zip ($([math]::Round((Get-Item $zipPath).Length/1KB,0)) KB)"

# --- 3. Delete the originals ---
$deleted = 0; $delFail = 0
foreach ($d in $real) {
  $p = Join-Path $root ($d -replace '/','\')
  try { Remove-Item -LiteralPath $p -Force; $deleted++ } catch { $delFail++; Log "  DEL-FAIL: $d -> $($_.Exception.Message)" }
}
Log "deleted: $deleted  failed: $delFail"

# --- 4. Move the 368MB scratch archive out of the workspace (rename, reversible) ---
$bigZip = "$root\runtime\archive-scratch-2026-10-10.zip"
$destDir = "C:\archive-pacgate-scratch"
if (Test-Path $bigZip) {
  if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
  $dest = Join-Path $destDir "archive-scratch-2026-10-10.zip"
  if (Test-Path $dest) { Log "dest already exists - NOT overwriting; big zip left in place" }
  else {
    Move-Item -LiteralPath $bigZip -Destination $dest
    Log "moved 368MB zip -> $dest ($([math]::Round((Get-Item $dest).Length/1MB,1)) MB)"
  }
} else { Log "big zip not found at runtime/ (already moved?)" }

# --- 5. Verify ---
$env:Path += ";C:\Program Files\Git\cmd"
$after = @(git -C $root ls-files --others --exclude-standard runtime/)
Log "untracked runtime files AFTER: $($after.Count) (was 1499)"
$rtFiles = (Get-ChildItem "$root\runtime" -Recurse -File -ErrorAction SilentlyContinue).Count
$rtSize = ((Get-ChildItem "$root\runtime" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
Log "runtime/ on disk now: $rtFiles files, $([math]::Round($rtSize/1MB,1)) MB (was 1747 files, 405.2 MB)"
Log "DONE"
Get-Content $out -Encoding UTF8 | Out-Host
