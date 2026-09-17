$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\FINAL-TASKS-RECON.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RECON FOR THE FOUR REMAINING TASKS (data-loss check first)'
A ('=' * 78)

# ============ 1. pacgate-ai-assets: is anything UNPUSHED? ====================
A "`n=== 1. pacgate-ai-assets - is there unpushed work? ==="
A ''
A '  BEFORE deleting its .git we must know whether any commit exists only here.'
$as = Join-Path $repo 'pacgate-ai-assets'
if (-not (Test-Path $as)) { A '  ABSENT' } else {
    $br = (& git -C $as branch --show-current 2>$null) -join ''
    A ("  branch : {0}" -f $br)
    A ("  HEAD   : {0}" -f ((& git -C $as rev-parse --short HEAD 2>$null) -join ''))
    A ("  commits: {0}" -f ((& git -C $as rev-list --all --count 2>$null) -join ''))

    # unpushed vs each remote
    foreach ($r in @('fork','origin')) {
        $has = (& git -C $as remote 2>$null) -contains $r
        if (-not $has) { continue }
        $ahead = & git -C $as rev-list --count "$r/$br..$br" 2>$null
        $behind = & git -C $as rev-list --count "$br..$r/$br" 2>$null
        A ("  vs {0,-7} ahead={1,-4} behind={2}" -f $r, ($ahead -join ''), ($behind -join ''))
    }

    # uncommitted / untracked
    $st = @(& git -C $as status --porcelain 2>$null)
    A ("  uncommitted entries: {0}" -f $st.Count)
    foreach ($x in ($st | Select-Object -First 10)) { A ("    " + $x) }

    # what would be LOST by deleting .git
    A ''
    A '  If ahead=0 vs fork, every commit is already on the remote and deleting'
    A '  .git loses nothing historically. Uncommitted entries are the risk.'
}

# ============ 2. image equivalence ==========================================
A "`n=== 2. Are the built images equivalent to the running ones? ==="
A ''
A '  Swapping local builds into a running stack is a real deployment. Check'
A '  whether the built image differs from the pulled one it would replace.'
$pairs = @(
    @{ built = 'pacgate-api:local-verify';              running = 'ghcr.io/pacgate-ai/pacgate-api:0.1.9' },
    @{ built = 'deer-flow-pacgate:local-verify';        running = 'ghcr.io/pacgate-ai/deer-flow-pacgate:0.1.10' },
    @{ built = 'pacgate-mcp:local-verify';              running = 'ghcr.io/pacgate-ai/pacgate-mcp:0.1.9' }
)
foreach ($p in $pairs) {
    $b = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.CreatedSince}}|{{.Size}}' |
           Where-Object { $_ -like "$($p.built)*" })
    $r = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.CreatedSince}}|{{.Size}}' |
           Where-Object { $_ -like "$($p.running)*" })
    A ("`n  built   : {0}" -f $(if ($b) { ($b -join '') } else { '(absent)' }))
    A ("  running : {0}" -f $(if ($r) { ($r -join '') } else { '(absent)' }))
    if ($b -and $r) {
        $bid = ($b[0] -split '\|')[1]; $rid = ($r[0] -split '\|')[1]
        A ("  same image ID: {0}" -f ($bid -eq $rid))
    }
}

# what source version is in the built image vs the tree?
A "`n  source version in the working tree:"
$cv = Join-Path $pa 'crates\pacgate-api\Cargo.toml'
if (Test-Path $cv) {
    @(Select-String -Path $cv -Pattern '^version' | Select-Object -First 1) | ForEach-Object { A ("    pacgate-api Cargo.toml: " + $_.Line.Trim()) }
}

# ============ 3. does anything still use the OLD path? ======================
A "`n=== 3. Is C:\pacgate-ai-pr still needed? (archive safety) ==="
$oldRefs = New-Object System.Collections.Generic.List[string]
foreach ($n in @(docker ps --format '{{.Names}}')) {
    $j = docker inspect $n --format '{{json .Mounts}}' 2>$null
    if (-not $j) { continue }
    try { $m = $j | ConvertFrom-Json } catch { continue }
    foreach ($x in $m) { if ($x.Source -like '*pacgate-ai-pr*') { $oldRefs.Add("$n : $($x.Source)") } }
}
A ("  container mounts under the OLD path : {0}   (0 = safe to archive)" -f $oldRefs.Count)
foreach ($x in $oldRefs) { A ("    " + $x) }

$composeOld = @(docker ps -a --format '{{.Names}}' | ForEach-Object {
    docker inspect $_ --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>$null
} | Where-Object { $_ -like '*pacgate-ai-pr*' })
A ("  compose projects using the OLD path  : {0}" -f $composeOld.Count)

# ============ 4. frontend build readiness ===================================
A "`n=== 4. Frontend build readiness ==="
$dfs = Join-Path $pa 'deploy\deer-flow-src\frontend'
A ("  deer-flow-src/frontend present : {0}" -f (Test-Path $dfs))
A ("  package.json                   : {0}" -f (Test-Path (Join-Path $dfs 'package.json')))
$bf = Join-Path $pa 'deploy\build-frontend.ps1'
A ("  build-frontend.ps1 present     : {0}" -f (Test-Path $bf))

# ============ 5. disk space for archiving ===================================
A "`n=== 5. Disk space (archiving needs room if we COPY rather than MOVE) ==="
$sz = [math]::Round((Get-ChildItem 'C:\pacgate-ai-pr' -Recurse -File -Force -ErrorAction SilentlyContinue |
      Measure-Object Length -Sum).Sum / 1GB, 2)
A ("  C:\pacgate-ai-pr size : {0} GB" -f $sz)
A ("  C: free               : {0} GB" -f [math]::Round((Get-PSDrive C).Free/1GB,1))

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"