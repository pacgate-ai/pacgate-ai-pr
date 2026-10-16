$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "pacgate-persona crate exists?"
Get-ChildItem "pacgate-ai/pacgate-ai/crates" -Directory | ForEach-Object { Write-Output ("  " + $_.Name) }
Write-Output "--- persona crate files ---"
if (Test-Path "pacgate-ai/pacgate-ai/crates/pacgate-persona") {
  Get-ChildItem "pacgate-ai/pacgate-ai/crates/pacgate-persona" -Recurse -File | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"") + "  (" + $_.Length + "b)") }
} else { Write-Output "  MISSING" }

Section "Is /app/workflows a MOUNT or BAKED?"
docker inspect pacgate-api | ConvertFrom-Json | ForEach-Object { $_.Mounts } |
  ForEach-Object { Write-Output ("  {0}  ->  {1}" -f $_.Source, $_.Destination) }
Write-Output "--- workflow count in container ---"
docker exec pacgate-api sh -c "ls /app/workflows | wc -l; echo '--- sample ---'; ls /app/workflows | head -8" 2>&1 | Out-String

Section "Local workflows dir: 15 files but 222 workflows?"
Write-Output "--- pacgate-ai/pacgate-ai/workflows ---"
Get-ChildItem "pacgate-ai/pacgate-ai/workflows" -File | ForEach-Object { Write-Output ("  " + $_.Name + "  (" + $_.Length + "b)") }
Write-Output "--- how many workflow DEFINITIONS inside one YAML? ---"
$sample = Get-Content "pacgate-ai/pacgate-ai/workflows/ma_due_diligence.yaml" -Raw -Encoding UTF8
Write-Output ("  ma_due_diligence.yaml: " + ([regex]::Matches($sample, '(?m)^\s*-\s*id:')).Count + " id: entries")
Write-Output ("  top-level keys: " + (($sample -split "`n" | Where-Object { $_ -match '^[a-z_]+:' }) -join ", "))

Section "UPSTREAM: does it have the persona crate + workflows?"
foreach ($p in @("pacgate-ai/crates/pacgate-persona","pacgate-ai/workflows","pacgate-ai/crates/pacgate-workflow")) {
  $n = (git ls-tree -r --name-only upstream/main -- $p 2>$null | Measure-Object -Line).Lines
  Write-Output ("  {0,-46} upstream files={1}" -f $p, $n)
}

Section "UPSTREAM workflows content vs local"
$upWf = git ls-tree -r --name-only upstream/main -- pacgate-ai/workflows 2>$null | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
$loWf = Get-ChildItem "pacgate-ai/pacgate-ai/workflows" -File | ForEach-Object { $_.Name } | Sort-Object
Write-Output "--- local-only ---"
Compare-Object $loWf $upWf | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }
Write-Output "--- upstream-only ---"
Compare-Object $loWf $upWf | Where-Object { $_.SideIndicator -eq "=>" } | ForEach-Object { Write-Output ("  " + $_.InputObject) }

Section "Are the 2 workflow dirs identical? (client-bundle vs pacgate-ai/workflows)"
$a = Get-ChildItem "pacgate-ai/deploy/client-bundle/workflows" -File | ForEach-Object { $_.Name } | Sort-Object
$b = Get-ChildItem "pacgate-ai/pacgate-ai/workflows" -File | ForEach-Object { $_.Name } | Sort-Object
Compare-Object $a $b | ForEach-Object { Write-Output ("  " + $_.SideIndicator + " " + $_.InputObject) }
Write-Output "(empty = identical names)"
Write-Output "--- content hash compare ---"
foreach ($f in $a) {
  $h1 = (Get-FileHash "pacgate-ai/deploy/client-bundle/workflows/$f" -Algorithm SHA256).Hash.Substring(0,12)
  $h2 = if (Test-Path "pacgate-ai/pacgate-ai/workflows/$f") { (Get-FileHash "pacgate-ai/pacgate-ai/workflows/$f" -Algorithm SHA256).Hash.Substring(0,12) } else { "MISSING" }
  $same = if ($h1 -eq $h2) { "SAME" } else { "DIFF" }
  Write-Output ("  {0,-34} {1}  {2} vs {3}" -f $f, $same, $h1, $h2)
}
