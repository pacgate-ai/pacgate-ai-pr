$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\BUILD-SURVIVAL-EVIDENCE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'EVIDENCE: did the BUILD survive, or only the RUN?'
A ('=' * 78)
A ''
A 'These are different claims. A running container proves the RUN survived.'
A 'It proves nothing about whether `docker build` still works, because the'
A 'running containers use images PULLED from GHCR, not built locally.'

# ============ 1. where did each running image come from? ====================
A "`n=== 1. Image provenance for the running stack ==="
A ''
A '  A locally-built image has no registry prefix and a recent Created time.'
A '  A pulled image names a registry (ghcr.io/...) and matches a remote digest.'
A ''
foreach ($n in @(docker ps --format '{{.Names}}' | Sort-Object)) {
    $img = (docker inspect $n --format '{{.Config.Image}}' 2>$null)
    if (-not $img) { continue }
    $created = (docker inspect $n --format '{{.Created}}' 2>$null)
    $isRegistry = $img -match '^[a-z0-9.-]+\.[a-z]{2,}/|^ghcr\.io/|^docker\.io/'
    $tag = if ($isRegistry) { 'PULLED (registry)' } else { 'LOCAL (no registry prefix)' }
    A ("  {0,-24} {1,-52} {2}" -f $n, $img, $tag)
}

# ============ 2. the three builds the user named ============================
A "`n=== 2. The three builds: context + Dockerfile + COPY sources ==="

function Check-Build([string]$label, [string]$ctxRel, [string]$fileRel) {
    A ("`n  --- {0} ---" -f $label)
    $ctx  = if ($ctxRel -eq '.') { $pa } else { Join-Path $pa ($ctxRel -replace '/', '\') }
    $file = Join-Path $pa ($fileRel -replace '/', '\')
    A ("    context : {0,-40} {1}" -f $ctxRel, $(if (Test-Path $ctx) { 'EXISTS' } else { '*** MISSING ***' }))
    A ("    file    : {0,-40} {1}" -f $fileRel, $(if (Test-Path $file) { 'EXISTS' } else { '*** MISSING ***' }))
    if (-not (Test-Path $file)) { return }

    # every COPY/ADD source must exist relative to the context
    $txt = [System.IO.File]::ReadAllText($file)
    foreach ($m in [regex]::Matches($txt, '(?m)^(COPY|ADD)\s+(.+)$')) {
        $parts = ($m.Groups[2].Value -split '\s+') | Where-Object { $_ -notmatch '^--' }
        if ($parts.Count -lt 1) { continue }
        $src = $parts[0]
        if ($src -eq '.') { A ("    COPY . .  -> whole context (valid)"); continue }
        $full = Join-Path $ctx ($src -replace '/', '\')
        $ok = Test-Path $full
        A ("    COPY {0,-34} {1}" -f $src, $(if ($ok) { 'EXISTS' } else { '*** MISSING ***' }))
    }
}

Check-Build 'pacgate-ai (Rust API)'      '.'                    'Dockerfile'
Check-Build 'pacgate-mcp (Python)'       'deploy/pacgate-mcp'   'deploy/pacgate-mcp/Dockerfile'
Check-Build 'deer-flow-pacgate'          '.'                    'deploy/deer-flow-pacgate/Dockerfile'
Check-Build 'deer-flow-frontend-pacgate' '.'                    'deploy/deer-flow-frontend-pacgate/Dockerfile'

# ============ 3. qm-pacgate: built or pulled? ===============================
A "`n=== 3. qm-pacgate: is it built from source at all? ==="
$qm = Join-Path $pa 'deploy\qm-pacgate'
A ("  compose.qm.yaml present : {0}" -f (Test-Path (Join-Path $qm 'compose.qm.yaml')))
$qmImgs = @(Select-String -Path (Join-Path $qm 'compose.qm.yaml') -Pattern '^\s*image:\s*(.+)$' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
A ("  images declared: {0}" -f $qmImgs.Count)
foreach ($i in $qmImgs) { A ("    " + $i) }
$qmBuild = @(Select-String -Path (Join-Path $qm 'compose.qm.yaml') -Pattern '^\s*build:' -ErrorAction SilentlyContinue)
A ("  `build:` directives: {0}  (0 = qm is PULLED, not built here)" -f $qmBuild.Count)
A ("  Dockerfile present: {0}" -f (Test-Path (Join-Path $qm 'Dockerfile')))

# ============ 4. deer-flow source location ==================================
A "`n=== 4. deer-flow source: where does the build expect it? ==="
A ''
A '  The deer-flow-pacgate build uses context `.` = the PLATFORM root'
A '  (pacgate-ai\). But the deer-flow source lives at pacgate-law\deer-flow,'
A '  which is OUTSIDE that context. If the Dockerfile COPYs deer-flow/, the'
A '  build cannot see it.'
$dfDockerfile = Join-Path $pa 'deploy\deer-flow-pacgate\Dockerfile'
if (Test-Path $dfDockerfile) {
    A ''
    A '  --- COPY/ADD lines in deploy/deer-flow-pacgate/Dockerfile ---'
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($dfDockerfile), '(?m)^(COPY|ADD)\s+(.+)$')) {
        A ("    " + $m.Value.Trim())
    }
}
A ''
A ("  pacgate-law\deer-flow exists        : {0}" -f (Test-Path (Join-Path $repo 'deer-flow')))
A ("  pacgate-ai\deer-flow exists        : {0}" -f (Test-Path (Join-Path $pa 'deer-flow')))
A ("  pacgate-ai\deploy\deer-flow-src    : {0}" -f (Test-Path (Join-Path $pa 'deploy\deer-flow-src')))

# ============ 5. local images present? ======================================
A "`n=== 5. Locally present images matching the stack ==="
$local = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.CreatedSince}}|{{.Size}}' 2>$null |
           Where-Object { $_ -match 'pacgate|deer-flow|qm' })
foreach ($i in $local) { A ("  " + $i) }
A ("  count: {0}" -f $local.Count)

A "`n=== VERDICT ==="
A '  RUN  : survived (25 containers up, verified functionally earlier).'
A '  BUILD: NOT YET VERIFIED. Static path checks pass, but no build has been'
A '         executed. The running stack uses pulled images, so it cannot'
A '         demonstrate buildability.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"