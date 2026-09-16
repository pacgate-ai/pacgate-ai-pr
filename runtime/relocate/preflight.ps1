$ErrorActionPreference = 'Continue'

# ============================================================================
# RELOCATION PREFLIGHT — safety net only. Non-destructive.
#
# This script does NOT move anything. It establishes:
#   1. the rollback anchor (exact commit/branch/state to return to)
#   2. .git backups for BOTH repos (cheap insurance)
#   3. a "before" runtime inventory for later comparison
#
# Everything here is safe to run whether or not the migration proceeds.
# ============================================================================

$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$outDir = Join-Path $repo 'runtime\relocate'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$report = New-Object System.Collections.Generic.List[string]
$report.Add('RELOCATION PREFLIGHT')
$report.Add("run at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add('')

# ---------------------------------------------------------------- 1. ANCHOR
$report.Add('=== 1. ROLLBACK ANCHOR ===')
$head   = & git -C $src rev-parse HEAD 2>$null
$branch = & git -C $src branch --show-current 2>$null
$count  = & git -C $src rev-list --count HEAD 2>$null
$report.Add("  source repo    : $src")
$report.Add("  HEAD           : $head")
$report.Add("  branch         : $branch")
$report.Add("  commit count   : $count")
$report.Add('  untracked/modified:')
$dirty = @(& git -C $src status --porcelain 2>$null)
foreach ($d in $dirty) { $report.Add("      $d") }
$report.Add("  (total dirty: $($dirty.Count))")
$report.Add('')

# target repo state
$hasHead = $false
& git -C $repo rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hasHead = $true }
$report.Add("  target repo    : $repo")
$report.Add("  has commits    : $hasHead")
$report.Add('')

# ---------------------------------------------------------------- 2. BACKUP
$report.Add('=== 2. .git BACKUPS ===')
$pairs = @(
    @{ S = "$src\.git";  D = 'C:\backup-pacgate-ai-pr-git' },
    @{ S = "$repo\.git"; D = 'C:\backup-pacgate-law-git' }
)
foreach ($p in $pairs) {
    if (-not (Test-Path -LiteralPath $p.S)) { $report.Add("  MISSING source: $($p.S)"); continue }
    if (Test-Path -LiteralPath $p.D) { Remove-Item -LiteralPath $p.D -Recurse -Force -ErrorAction SilentlyContinue }
    & robocopy $p.S $p.D /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $ok = Test-Path -LiteralPath $p.D
    $cnt = 0; $mb = 0
    if ($ok) {
        $f = @(Get-ChildItem -LiteralPath $p.D -Recurse -File -Force -ErrorAction SilentlyContinue)
        $cnt = $f.Count
        $mb = [math]::Round((($f | Measure-Object Length -Sum).Sum)/1MB, 1)
    }
    $report.Add(('  {0,-34} -> {1}' -f $p.S, $p.D))
    $report.Add(('      exists={0}  files={1}  size={2} MB' -f $ok, $cnt, $mb))
}
$report.Add('')

# ---------------------------------------------------------------- 3. INVENTORY
$report.Add('=== 3. RUNTIME INVENTORY (before) ===')
$inv = @{}
$inv['containers'] = @(& docker ps --format '{{.Names}}|{{.Status}}')
$inv['volumes']    = @(& docker volume ls --format '{{.Name}}')
$inv['images']     = @(& docker images --format '{{.Repository}}:{{.Tag}}')

$report.Add("  running containers : $($inv['containers'].Count)")
$report.Add("  volumes            : $($inv['volumes'].Count)")
$report.Add("  images             : $($inv['images'].Count)")
$report.Add('')
$report.Add('  --- containers ---')
foreach ($c in $inv['containers']) { $report.Add("      $c") }
$report.Add('')
$report.Add('  --- volumes ---')
foreach ($v in $inv['volumes']) { $report.Add("      $v") }

# machine-readable copy for later diffing
$invPath = Join-Path $outDir 'inventory-BEFORE.json'
$inv | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $invPath -Encoding UTF8
$report.Add('')
$report.Add("  wrote: $invPath")

# ---------------------------------------------------------------- 4. CAPACITY
$report.Add('')
$report.Add('=== 4. CAPACITY CHECK ===')
$drive = Get-PSDrive C
$freeGb = [math]::Round($drive.Free/1GB, 1)
$srcMb  = [math]::Round((((Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum)/1MB, 1)
$report.Add("  free space   : $freeGb GB")
$report.Add("  source size  : $srcMb MB")
$report.Add("  need (copy)  : ~$([math]::Round($srcMb/1024,1)) GB  -> $($freeGb -gt ($srcMb/1024 + 2))")

# ---------------------------------------------------------------- write
$anchorPath = Join-Path $outDir 'ROLLBACK-ANCHOR.txt'
[System.IO.File]::WriteAllText($anchorPath, ($report -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "PREFLIGHT COMPLETE"
Write-Output "  $anchorPath"
Write-Output "  $invPath"
