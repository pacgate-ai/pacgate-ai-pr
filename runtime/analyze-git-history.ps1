$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\git-history-options.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('GIT HISTORY: what happens to the 158 commits on relocation?')
$lines.Add('=' * 70)
$lines.Add('')

$SRC = 'C:\pacgate-ai-pr'
$DST = 'c:\Users\pacga\github-pr\pacgate-law'

# ---------- source repo ----------
$lines.Add('=== SOURCE repo (' + $SRC + ') ===')
$lines.Add("  commits    : $(& git -C $SRC rev-list --count HEAD 2>$null)")
$lines.Add("  branch     : $(& git -C $SRC branch --show-current 2>$null)")
$lines.Add("  HEAD       : $(& git -C $SRC rev-parse --short HEAD 2>$null)")
$lines.Add("  .git size  : $([math]::Round((Get-ChildItem "$SRC\.git" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,1)) MB")
$lines.Add('  remotes:')
foreach ($r in @(& git -C $SRC remote -v 2>$null)) { $lines.Add("      $r") }
$lines.Add("  dirty files: $(@(& git -C $SRC status --porcelain 2>$null).Count)")
$lines.Add('')

# ---------- target repo ----------
$lines.Add('=== TARGET repo (' + $DST + ') ===')
$hasHead = $false
& git -C $DST rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hasHead = $true }
$lines.Add("  has commits : $hasHead  (known: 0 commits, git init only)")
$lines.Add("  .git size   : $([math]::Round((Get-ChildItem "$DST\.git" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,1)) MB")
$lines.Add('  remotes:')
$r = @(& git -C $DST remote -v 2>$null)
if ($r.Count -eq 0) { $lines.Add('      (none)') } else { foreach ($x in $r) { $lines.Add("      $x") } }
$lines.Add("  staged files: $(@(& git -C $DST status --porcelain 2>$null).Count)")
$lines.Add('')

# ---------- tracked paths: would they stay valid? ----------
$lines.Add('=== KEY QUESTION: if source CONTENT lands at the target ROOT, do tracked paths stay valid? ===')
$tracked = @(& git -C $SRC -c core.quotepath=false ls-files 2>$null)
$lines.Add("  source tracks $($tracked.Count) files, all relative to the source root.")
$lines.Add("  If those files land at pacgate-law\ with the SAME relative layout,")
$lines.Add("  then every tracked path stays identical and history applies cleanly.")
$lines.Add("")
$lines.Add("  If they land at pacgate-law\pacgate-ai\ instead, EVERY tracked path")
$lines.Add("  gains a 'pacgate-ai/' prefix -> requires a history rewrite to stay")
$lines.Add("  consistent, or the history must be abandoned.")
$lines.Add('')

# ---------- collision with existing staged content ----------
$lines.Add('=== Overlap between source tracked files and target staged files ===')
$dstStaged = @(& git -C $DST -c core.quotepath=false status --porcelain 2>$null | ForEach-Object { ($_ -replace '^...','').Trim() } | Where-Object { $_ -notlike '*deer-flow*' })
$lines.Add("  target staged entries: $($dstStaged.Count)")
foreach ($s in $dstStaged) { $lines.Add("      $s") }
$lines.Add('')
$lines.Add('  Note: target stages "pacgate-ai" as a SUBMODULE gitlink, which will')
$lines.Add('  conflict with real files placed at that path.')

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
