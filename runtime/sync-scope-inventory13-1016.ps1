$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "deer-flow-pacgate Dockerfile — does it COPY skills?"
$df = "pacgate-ai/deploy/deer-flow-pacgate/Dockerfile"
if (Test-Path $df) {
  Get-Content $df -Encoding UTF8 | ForEach-Object { Write-Output ("  " + $_) }
} else { Write-Output "  MISSING: $df" }

Section "UPSTREAM Dockerfile — same?"
$upDf = git show upstream/main:deploy/deer-flow-pacgate/Dockerfile 2>$null
if ($upDf) { $upDf | ForEach-Object { Write-Output ("  " + $_) } }

Section "The 3 missing skills — PacGate-authored or upstream bytedance?"
Push-Location deer-flow
foreach ($s in @("antitrust-compliance","arbitration","bankruptcy-restructuring")) {
  Write-Output ("--- $s ---")
  $files = git ls-tree -r --name-only fork/pacgate-layer -- "skills/public/$s" 2>$null
  $files | ForEach-Object { Write-Output ("    " + $_) }
  # Is it in bytedance upstream?
  $inUp = (git ls-tree -r --name-only upstream/main -- "skills/public/$s" 2>$null | Measure-Object -Line).Lines
  Write-Output ("    in bytedance/upstream/main: " + $inUp)
}
Write-Output "--- when were they added to pacgate-layer? ---"
foreach ($s in @("antitrust-compliance","arbitration","bankruptcy-restructuring")) {
  $c = git log --oneline -1 -- "skills/public/$s" 2>$null
  Write-Output ("  {0,-28} {1}" -f $s, $c)
}
Pop-Location

Section "How many skills are PacGate-authored vs upstream?"
Push-Location deer-flow
$all = git ls-tree -r --name-only fork/pacgate-layer -- skills/public 2>$null |
  ForEach-Object { ($_ -split '/')[2] } | Sort-Object -Unique
$up = git ls-tree -r --name-only upstream/main -- skills/public 2>$null |
  ForEach-Object { ($_ -split '/')[2] } | Sort-Object -Unique
Write-Output ("  pacgate-layer skill dirs: " + $all.Count)
Write-Output ("  bytedance upstream dirs : " + $up.Count)
Write-Output "--- PacGate-only skills (not in bytedance) ---"
Compare-Object $all $up | Where-Object { $_.SideIndicator -eq "<=" } | ForEach-Object { Write-Output ("    " + $_.InputObject) }
Pop-Location

Section "UPSTREAM pacgate-ai-pr: is there a skills dir at all?"
Write-Output ("  upstream 'skills' path files: " + (git ls-tree -r --name-only upstream/main -- skills 2>$null | Measure-Object -Line).Lines)
Write-Output ("  upstream 'deer-flow' path files: " + (git ls-tree -r --name-only upstream/main -- deer-flow 2>$null | Measure-Object -Line).Lines)
