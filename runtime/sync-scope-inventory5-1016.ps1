$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

# Get PAT from Windows Credential Manager (never print it)
$pat = $null
try {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = "credential fill"
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.WriteLine("protocol=https")
  $p.StandardInput.WriteLine("host=github.com")
  $p.StandardInput.WriteLine("")
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^password=(.+)$') { $pat = $Matches[1].Trim() }
  }
} catch { }
Write-Output ("PAT acquired: " + $(if ($pat) { "YES (len=" + $pat.Length + ")" } else { "NO" }))

if ($pat) {
  $h = @{ Authorization = "Bearer $pat"; Accept = "application/vnd.github+json"; "User-Agent" = "pacgate-audit" }

  Section "REPO VISIBILITY"
  foreach ($r in @("JZKK720/pacgate-ai-pr","pacgate-ai/pacgate-ai-pr","JZKK720/deer-flow","pacgate-ai/deer-flow")) {
    try {
      $j = Invoke-RestMethod -Uri "https://api.github.com/repos/$r" -Headers $h -Method Get
      Write-Output ("  {0,-32} private={1,-6} default={2,-8} pushed={3}" -f $r, $j.private, $j.default_branch, $j.pushed_at)
    } catch { Write-Output ("  {0,-32} ERROR {1}" -f $r, $_.Exception.Message) }
  }

  Section "OPEN PRs — pacgate-ai-pr"
  try {
    $prs = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr/pulls?state=open" -Headers $h
    if ($prs.Count -eq 0) { Write-Output "  (none)" }
    foreach ($pr in $prs) { Write-Output ("  #{0} {1}  head={2}  mergeable={3}" -f $pr.number, $pr.title, $pr.head.ref, $pr.mergeable_state) }
  } catch { Write-Output ("  ERROR " + $_.Exception.Message) }

  Section "OPEN PRs — deer-flow"
  try {
    $prs2 = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/deer-flow/pulls?state=open" -Headers $h
    if ($prs2.Count -eq 0) { Write-Output "  (none)" }
    foreach ($pr in $prs2) { Write-Output ("  #{0} {1}  head={2}  mergeable={3}" -f $pr.number, $pr.title, $pr.head.ref, $pr.mergeable_state) }
  } catch { Write-Output ("  ERROR " + $_.Exception.Message) }

  Section "BRANCHES on JZKK720/pacgate-ai-pr"
  try {
    $br = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr/branches?per_page=100" -Headers $h
    $br | ForEach-Object { Write-Output ("  " + $_.name) }
  } catch { Write-Output ("  ERROR " + $_.Exception.Message) }

  Section "TAGS on JZKK720/pacgate-ai-pr"
  try {
    $tg = Invoke-RestMethod -Uri "https://api.github.com/repos/JZKK720/pacgate-ai-pr/tags?per_page=100" -Headers $h
    $tg | Select-Object -First 15 | ForEach-Object { Write-Output ("  " + $_.name) }
  } catch { Write-Output ("  ERROR " + $_.Exception.Message) }

  Section "GHCR packages (jzkk720)"
  try {
    $pk = Invoke-RestMethod -Uri "https://api.github.com/orgs/jzkk720/packages?package_type=container&per_page=100" -Headers $h
    $pk | ForEach-Object { Write-Output ("  {0,-34} visibility={1}" -f $_.name, $_.visibility) }
  } catch { Write-Output ("  ERROR " + $_.Exception.Message) }
}
