$ErrorActionPreference = 'Continue'

# ============================================================================
# RELOCATION DRY RUN — validates every precondition. Changes NOTHING.
#
# Run this before the real migration. It answers "would the move succeed?"
# by checking each failure mode discovered during planning.
# ============================================================================

$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$outDir = Join-Path $repo 'runtime\relocate'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$r = New-Object System.Collections.Generic.List[string]
$fail = 0; $warn = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
    $tag = if ($ok) { 'PASS' } else { 'FAIL' }
    if (-not $ok) { $script:fail++ }
    $script:r.Add(("[{0}] {1}" -f $tag, $name))
    if ($detail) { $script:r.Add("        $detail") }
}
function Warn([string]$name, [string]$detail) {
    $script:warn++
    $script:r.Add(("[WARN] $name"))
    if ($detail) { $script:r.Add("        $detail") }
}

$r.Add('RELOCATION DRY RUN')
$r.Add("run at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$r.Add('')
$r.Add('=== A. SOURCE INTEGRITY ===')

# A1 source exists and is a git repo
Check 'source exists' (Test-Path -LiteralPath $src) $src
Check 'source is a git repo' (Test-Path -LiteralPath "$src\.git") ''

# A2 HEAD reachable
$head = & git -C $src rev-parse HEAD 2>$null
Check 'source HEAD resolvable' ([bool]$head) "HEAD=$head"

# A3 no uncommitted modifications to TRACKED files (untracked scratch is fine)
$mod = @(& git -C $src status --porcelain 2>$null | Where-Object { $_ -notmatch '^\?\?' })
Check 'no modified tracked files' ($mod.Count -eq 0) "modified tracked: $($mod.Count)"

# A4 archive is producible
$r.Add('')
$r.Add('=== B. EXPORT FEASIBILITY ===')
$tmpTar = Join-Path $env:TEMP 'pacgate-dryrun.tar'
if (Test-Path -LiteralPath $tmpTar) { Remove-Item -LiteralPath $tmpTar -Force -ErrorAction SilentlyContinue }
& git -C $src archive --format=tar HEAD -o $tmpTar 2>$null
$tarOk = (Test-Path -LiteralPath $tmpTar) -and ((Get-Item -LiteralPath $tmpTar).Length -gt 1000)
$tarMb = if ($tarOk) { [math]::Round((Get-Item -LiteralPath $tmpTar).Length/1MB,2) } else { 0 }
Check 'git archive produces output' $tarOk "tar size: $tarMb MB"
if (Test-Path -LiteralPath $tmpTar) { Remove-Item -LiteralPath $tmpTar -Force -ErrorAction SilentlyContinue }

# B2 archive must NOT contain target/ or client data
$r.Add('  (listing archive to verify exclusions)')
$list = @(& git -C $src archive --format=tar HEAD --prefix='' 2>$null)   # not usable; use ls-tree instead
$tracked = @(& git -C $src -c core.quotepath=false ls-files 2>$null)
$hasTarget = @($tracked | Where-Object { $_ -like 'pacgate-ai/target/*' }).Count
$hasData   = @($tracked | Where-Object { $_ -like '*client-bundle/data/*' }).Count
Check 'archive excludes build output' ($hasTarget -eq 0) "target/ entries tracked: $hasTarget"
Check 'archive excludes client data' ($hasData -eq 0) "client data entries tracked: $hasData"
$r.Add("        tracked file count: $($tracked.Count)")

$r.Add('')
$r.Add('=== C. TARGET READINESS ===')

# C1 target repo exists
Check 'target repo exists' (Test-Path -LiteralPath $repo) $repo

# C2 the pacgate-ai collision
$gitlink = @(& git -C $repo ls-files -s pacgate-ai 2>$null)
$isSubmodule = ($gitlink.Count -gt 0) -and ($gitlink[0] -match '^160000')
Warn 'target pacgate-ai is a SUBMODULE gitlink' "must be removed before real files can land there" 
$r.Add("        gitlink: $($gitlink -join '')")

# C3 .gitmodules URL sanity
$gm = Join-Path $repo '.gitmodules'
if (Test-Path -LiteralPath $gm) {
    $url = ([System.IO.File]::ReadAllLines($gm) | Where-Object { $_ -match 'url\s*=' }) -join ';'
    Warn '.gitmodules points at the ASSETS repo' "$url -- not the Rust workspace; resolve before import"
}

# C4 duplicate asset trees
$vendored = Join-Path $src 'pacgate-ai\pacgate-ai-assets\pacgate-ai'
$subAssets = Join-Path $repo 'pacgate-ai\assets'
if ((Test-Path -LiteralPath $vendored) -and (Test-Path -LiteralPath $subAssets)) {
    $vf = @(Get-ChildItem -LiteralPath $vendored -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $sf = @(Get-ChildItem -LiteralPath $subAssets -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    Warn 'asset tree exists in BOTH places' "vendored=$vf files, submodule=$sf files -- keep ONE"
}

$r.Add('')
$r.Add('=== D. DATA SAFETY ===')

# D1 the two live databases exist in the source
foreach ($pair in @(
    @{ N = 'deerflow.db';   P = "$src\deploy\client-bundle\data\deer-flow\data\deerflow.db";   Min = 0.5 },
    @{ N = 'checkpoints.db';P = "$src\deploy\client-bundle\data\deer-flow\checkpoints.db";      Min = 1000 }
)) {
    $ok = Test-Path -LiteralPath $pair.P
    $mb = if ($ok) { [math]::Round((Get-Item -LiteralPath $pair.P).Length/1MB,2) } else { 0 }
    Check "$($pair.N) present in source" ($ok -and $mb -ge $pair.Min) "$mb MB"
}

# D2 named volumes still healthy
$r.Add('')
$r.Add('=== E. DOCKER STATE ===')
$running = @(& docker ps --format '{{.Names}}' 2>$null)
Check 'expected container count' ($running.Count -eq 25) "running: $($running.Count)"

$vols = @(& docker volume ls --format '{{.Name}}' 2>$null)
Check 'both pacgate-db-data generations still present' (($vols -contains 'pacgate-ai-bundle_pacgate-db-data') -and ($vols -contains 'client-bundle_pacgate-db-data')) "volumes: $($vols.Count)"

# D3 which volume is live
$liveVol = (& docker inspect pacgate-db --format '{{range .Mounts}}{{.Name}}{{end}}' 2>$null)
Check 'live DB volume identified' ([bool]$liveVol) "pacgate-db -> $liveVol"

# D4 the bind-mount dependency count
$mountHits = 0
foreach ($n in $running) {
    $j = & docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $j) { continue }
    foreach ($m in @($j[0].Mounts)) { if ("$($m.Source)" -like '*pacgate-ai-pr*') { $mountHits++ } }
}
Warn "running containers bind-mount $mountHits path(s) under the source" 'these MUST be re-pointed; the stack must be stopped and restarted'

# D5 compose project-name trap
$r.Add('')
$r.Add('=== F. COMPOSE PROJECT-NAME TRAP ===')
$prodName = ''
$prodFile = "$src\deploy\client-bundle\compose.prod.yaml"
if (Test-Path -LiteralPath $prodFile) {
    $prodName = ([System.IO.File]::ReadAllLines($prodFile) | Where-Object { $_ -match '^name:\s*(.+)$' } | Select-Object -First 1)
}
Check 'compose.prod.yaml declares name:' ([bool]$prodName) "found: '$prodName'  (empty = derives from DIR NAME -> new empty volume risk)"

$r.Add('')
$r.Add('=== G. CAPACITY ===')
$freeGb = [math]::Round((Get-PSDrive C).Free/1GB,1)
$srcMb  = [math]::Round((((Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum)/1MB,1)
Check 'enough free space for copy-then-cutover' ($freeGb -gt (($srcMb/1024) + 2)) "free=$freeGb GB, source=$srcMb MB"

$r.Add('')
$r.Add('=== H. BACKUPS PRESENT ===')
foreach ($b in @('C:\backup-pacgate-ai-pr-git','C:\backup-pacgate-law-git')) {
    $ok = Test-Path -LiteralPath $b
    Check "backup $([System.IO.Path]::GetFileName($b))" $ok $b
}

# ---------------------------------------------------------------- summary
$r.Add('')
$r.Add('=' * 60)
$r.Add("SUMMARY: $fail FAIL, $warn WARN")
$r.Add('=' * 60)
if ($fail -gt 0) {
    $r.Add('')
    $r.Add('DO NOT PROCEED until every FAIL is resolved.')
} else {
    $r.Add('')
    $r.Add('All hard checks pass. WARN items need a human decision, not a fix.')
}

$path = Join-Path $outDir 'DRY-RUN-RESULT.txt'
[System.IO.File]::WriteAllText($path, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "DRY RUN COMPLETE: $fail FAIL, $warn WARN"
Write-Output "  $path"