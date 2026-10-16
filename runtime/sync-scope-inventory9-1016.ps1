$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "pacgate-db: actual tables"
docker exec pacgate-db psql -U pacgate -d pacgate -c "\dt" 2>&1 | Out-String

Section "pacgate-api: how are workflows loaded?"
$apiSrc = "pacgate-ai/pacgate-ai/crates/pacgate-api/src"
Get-ChildItem $apiSrc -File | ForEach-Object { Write-Output ("  " + $_.Name + "  (" + $_.Length + "b)") }
Write-Output "--- workflows.rs: where does it read from? ---"
if (Test-Path "$apiSrc/workflows.rs") {
  Select-String -Path "$apiSrc/workflows.rs" -Pattern "include_str|from_str|read_to_string|PathBuf|WORKFLOW|const |fn " -Encoding UTF8 |
    Select-Object -First 30 | ForEach-Object { Write-Output ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
}

Section "Where are the 222 workflows stored on disk?"
Get-ChildItem -Path "pacgate-ai" -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "^workflows?$" -and $_.FullName -notmatch "node_modules|\\target\\" } |
  ForEach-Object {
    $c = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Output ("  {0}  files={1}" -f $_.FullName.Replace($root,""), $c)
  }

Section "pacgate-api container: where does it read workflows from?"
docker exec pacgate-api sh -c "ls -la /app 2>/dev/null; echo '---'; find / -maxdepth 4 -type d -name 'workflows' 2>/dev/null | head" 2>&1 | Out-String

Section "personas: search source"
Get-ChildItem -Path "pacgate-ai/pacgate-ai" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "persona" -and $_.FullName -notmatch "\\target\\" } |
  ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }
Write-Output "--- grep persona in Rust source ---"
Get-ChildItem -Path "pacgate-ai/pacgate-ai/crates" -Recurse -Filter "*.rs" -ErrorAction SilentlyContinue |
  Select-String -Pattern "persona" -Encoding UTF8 | Select-Object -First 15 |
  ForEach-Object { Write-Output ("  {0}:{1}: {2}" -f (Split-Path $_.Path -Leaf), $_.LineNumber, $_.Line.Trim()) }
