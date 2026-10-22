# Cleanup audit: inventory sizes, ages, git state, references - READ-ONLY
$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$out = "$root\runtime\cleanup-audit-1010.txt"
$env:Path += ";C:\Program Files\Git\cmd"
"=== CLEANUP AUDIT - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -Path $out -Encoding UTF8
function Add-Sec($t) { ("`n===== " + $t + " =====") | Add-Content -Path $out -Encoding UTF8 }
function Get-DirSize($path) {
  if (-not (Test-Path $path)) { return $null }
  $sum = [long]0; $cnt = 0
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($path, "*", [System.IO.SearchOption]::AllDirectories)) {
      try { $sum += ([System.IO.FileInfo]::new($f)).Length; $cnt++ } catch {}
    }
  } catch {}
  [pscustomobject]@{ MB = [math]::Round($sum/1MB,1); Files = $cnt }
}

Add-Sec "0. DISK FREE"
$d = Get-PSDrive C
("C: free {0:N1} GB / used {1:N1} GB" -f ($d.Free/1GB), ($d.Used/1GB)) | Add-Content $out -Encoding UTF8

Add-Sec "1. TOP-LEVEL items (nested repos measured separately)"
$skipRepos = @(".git","deer-flow","pacgate-ai","pacgate-ai-assets")
$rows = @()
Get-ChildItem $root -Force | Where-Object { $skipRepos -notcontains $_.Name } | ForEach-Object {
  if ($_.PSIsContainer) {
    $s = Get-DirSize $_.FullName
    $rows += [pscustomobject]@{ Name = $_.Name + "/"; MB = $s.MB; Files = $s.Files }
  } else {
    $rows += [pscustomobject]@{ Name = $_.Name; MB = [math]::Round($_.Length/1MB,2); Files = 1 }
  }
}
$rows | Sort-Object MB -Descending | ForEach-Object { ("  {0,-34} {1,10:N1} MB {2,7} files" -f $_.Name, $_.MB, $_.Files) } | Add-Content $out -Encoding UTF8

Add-Sec "1b. NESTED REPOS + heavy dirs (targeted)"
foreach ($p in @("$root\.git", "$root\deer-flow\frontend\node_modules", "$root\deer-flow\backend\.venv", "$root\deer-flow\backend\.deer-flow", "$root\pacgate-ai\deploy\client-bundle\data", "$root\pacgate-ai\pacgate-ai\target", "$root\pacgate-ai-assets")) {
  $s = Get-DirSize $p
  if ($s) { ("  {0,-55} {1,10:N1} MB {2,7} files" -f $p.Replace($root,""), $s.MB, $s.Files) | Add-Content $out -Encoding UTF8 }
  else { ("  {0,-55} absent" -f $p.Replace($root,"")) | Add-Content $out -Encoding UTF8 }
}

Add-Sec "2. RUNTIME/ by extension"
$rt = Get-ChildItem "$root\runtime" -Recurse -File
$rt | Group-Object Extension | ForEach-Object {
  $sum = ($_.Group | Measure-Object Length -Sum).Sum
  [pscustomobject]@{ Ext=$_.Name; Count=$_.Count; MB=[math]::Round($sum/1MB,2) }
} | Sort-Object MB -Descending | ForEach-Object { ("  {0,-10} {1,5} files {2,10:N2} MB" -f $_.Ext,$_.Count,$_.MB) } | Add-Content $out -Encoding UTF8
$rtTotal = ($rt | Measure-Object Length -Sum).Sum
("TOTAL runtime: {0} files, {1:N1} MB" -f $rt.Count, ($rtTotal/1MB)) | Add-Content $out -Encoding UTF8

Add-Sec "3. RUNTIME/ age buckets"
$now = Get-Date
$buckets = @(
  @{ Label="0-2d";  Days=2 }, @{ Label="3-7d"; Days=7 }, @{ Label="8-14d"; Days=14 },
  @{ Label="15-30d"; Days=30 }, @{ Label=">30d"; Days=99999 }
)
foreach ($b in $buckets) {
  $grp = $rt | Where-Object { ($now - $_.LastWriteTime).TotalDays -le $b.Days }
  $sz = ($grp | Measure-Object Length -Sum).Sum
  ("  {0,-8} {1,5} files {2,9:N2} MB" -f $b.Label, $grp.Count, ($sz/1MB)) | Add-Content $out -Encoding UTF8
  # prevent double counting: remove counted from further buckets
  $rt = $rt | Where-Object { ($now - $_.LastWriteTime).TotalDays -gt $b.Days }
}

Add-Sec "4. RUNTIME/ git state"
$trackedList = @(git -C $root ls-files runtime/)
$ignoredList = @(git -C $root ls-files --others --ignored --exclude-standard runtime/)
("tracked: {0}  ignored: {1}  untracked-nonignored: {2}" -f $trackedList.Count, $ignoredList.Count, ($rt.Count + $trackedList.Count + $ignoredList.Count - $rt.Count - $trackedList.Count - $ignoredList.Count)) | Add-Content $out -Encoding UTF8
("NOTE: total files on disk = tracked + ignored + untracked-nonignored") | Add-Content $out -Encoding UTF8
$allCount = (Get-ChildItem "$root\runtime" -Recurse -File).Count
("disk total: {0}  => untracked-nonignored = {1}" -f $allCount, ($allCount - $trackedList.Count - $ignoredList.Count)) | Add-Content $out -Encoding UTF8
"tracked files (committed + in mirror backup):" | Add-Content $out -Encoding UTF8
$trackedList | ForEach-Object { "  $_" } | Add-Content $out -Encoding UTF8

Add-Sec "5. RUNTIME/ largest 20 files"
Get-ChildItem "$root\runtime" -Recurse -File | Sort-Object Length -Descending | Select-Object -First 20 | ForEach-Object { ("  {0,10:N2} MB  {1}" -f ($_.Length/1MB), $_.FullName.Replace("$root\runtime\","")) } | Add-Content $out -Encoding UTF8

Add-Sec "6. ROOT loose files"
Get-ChildItem $root -File | ForEach-Object { ("  {0,10:N2} MB  {1}" -f ($_.Length/1MB), $_.Name) } | Add-Content $out -Encoding UTF8

Add-Sec "7. RUNTIME/ mentions in tracked docs (AGENTS.md + docs/**/*.md)"
$refText = ""
$refFiles = @("$root\AGENTS.md") + (Get-ChildItem "$root\docs" -Recurse -Filter *.md -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
foreach ($f in $refFiles) { try { $refText += [System.IO.File]::ReadAllText($f) } catch {} }
$mentions = [regex]::Matches($refText, 'runtime[/\\][\w\.\-\+\\]+') | ForEach-Object { $_.Value -replace '\\','/' } | Sort-Object -Unique
("unique runtime/ mentions: {0}" -f $mentions.Count) | Add-Content $out -Encoding UTF8
$mentions | Add-Content $out -Encoding UTF8

Add-Sec "8. RUNTIME/ subdirectories (with sizes)"
Get-ChildItem "$root\runtime" -Directory | ForEach-Object {
  $s = Get-DirSize $_.FullName
  ("  {0,-42} {1,10:N1} MB {2,7} files" -f $_.Name, $s.MB, $s.Files)
} | Add-Content $out -Encoding UTF8

Add-Sec "9. OLD-FILE FAMILIES (>14 days, grouped by name pattern)"
$old = Get-ChildItem "$root\runtime" -File | Where-Object { ($now - $_.LastWriteTime).TotalDays -gt 14 }
$old | Group-Object { ($_.BaseName -replace '\d+','') -replace '\-+$','' } | Sort-Object Count -Descending | ForEach-Object {
  $sz = ($_.Group | Measure-Object Length -Sum).Sum
  ("  {0,-28} {1,4} files {2,9:N2} MB" -f ($_.Name + "*"), $_.Count, ($sz/1MB))
} | Add-Content $out -Encoding UTF8

"DONE" | Add-Content $out -Encoding UTF8
Write-Output "audit written to $out"
