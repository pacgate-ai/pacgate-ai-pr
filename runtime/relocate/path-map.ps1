$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\PATH-MAP.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'PATH MAP -- old vs new for every bind-mount the stack uses'
A ('=' * 78)
A ''

$oldCB = 'C:\pacgate-ai-pr\deploy\client-bundle'
$newCB = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$oldQM = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$newQM = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'

A "  OLD client-bundle : $oldCB"
A "  NEW client-bundle : $newCB"
A ''
A "  OLD qm-pacgate    : $oldQM"
A "  NEW qm-pacgate    : $newQM"

# ---------- 1. live bind mounts ---------------------------------------------
A "`n=== 1. LIVE bind mounts (what the running containers actually use) ==="
$names = @('pacgate-db','pacgate-api','deer-flow','deer-flow-frontend','pacgate-nginx',
           'pacgate-mcp','openviking','qm-pacgate-core-1')
foreach ($n in $names) {
    $exists = @(docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $n })
    if (-not $exists) { continue }
    $raw = docker inspect $n --format '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Destination}}{{"\n"}}{{end}}' 2>$null
    $binds = @($raw | Where-Object { $_ -match '^bind\|' })
    A ("`n  [{0}]  bind mounts: {1}" -f $n, $binds.Count)
    foreach ($b in $binds) {
        $p = $b -split '\|'
        $src = $p[1]
        $tag = if ($src -like '*pacgate-ai-pr*') { 'OLD' } elseif ($src -like '*pacgate-law*') { 'NEW' } else { 'other' }
        A ("    {0,-5} {1}" -f $tag, $src)
        A ("          -> {0}" -f $p[2])
    }
}

# ---------- 2. compose mount declarations (are they relative?) --------------
A "`n=== 2. How compose DECLARES them (relative vs absolute) ==="
foreach ($f in @(Join-Path $newCB 'compose.bundle.yaml', Join-Path $newQM 'compose.qm.yaml')) {
    if (-not (Test-Path $f)) { continue }
    A ("`n  --- {0} ---" -f $f.Substring($newCB.Length - 'deploy\client-bundle'.Length))
    $lines = [System.IO.File]::ReadAllLines($f)
    $abs = @()
    foreach ($ln in $lines) {
        if ($ln -match '^\s*-\s+[A-Za-z]:') { $abs += $ln.Trim() }   # drive-letter mount
    }
    A ("    absolute-path mounts: {0}   (0 means every mount resolves relative to the compose file)" -f $abs.Count)
    foreach ($a in $abs) { A ("      ! " + $a) }
}

# ---------- 3. runtime state that must be copied ----------------------------
A "`n=== 3. Runtime state that is NOT in git (must be copied) ==="
function Stat($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
    return @{ n = $f.Count; mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1) }
}
$items = @(
    @{ s = "$oldCB\data";                            d = "$newCB\data" },
    @{ s = "$oldCB\openviking";                      d = "$newCB\openviking" },
    @{ s = "$oldCB\.env";                            d = "$newCB\.env" },
    @{ s = "$oldCB\deer-flow-extensions-config.json"; d = "$newCB\deer-flow-extensions-config.json" },
    @{ s = "$oldQM\node_modules";                    d = "$newQM\node_modules" },
    @{ s = "$oldQM\.env";                            d = "$newQM\.env" }
)
$totalMB = 0
foreach ($i in $items) {
    $so = Stat $i.s; $dn = Stat $i.d
    if ($so) { $totalMB += $so.mb }
    A ("  {0,-40} old={1,-16} new={2}" -f (Split-Path -Leaf $i.s),
        $(if ($so) { "files=$($so.n) MB=$($so.mb)" } else { 'absent' }),
        $(if ($dn) { "files=$($dn.n) MB=$($dn.mb)" } else { 'ABSENT' }))
}
A ("`n  total runtime state at old path: {0} MB" -f $totalMB)

# ---------- 4. image pinning ------------------------------------------------
A "`n=== 4. Image pinning (how the runtime is version-locked) ==="
foreach ($f in @(Join-Path $newCB 'compose.bundle.yaml', Join-Path $newQM 'compose.qm.yaml')) {
    if (-not (Test-Path $f)) { continue }
    A ("`n  --- {0} ---" -f (Split-Path -Leaf $f))
    $imgs = @(Select-String -Path $f -Pattern '^\s*image:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
    foreach ($im in $imgs) {
        # digest-pinned if it contains @sha256
        $kind = if ($im -match '@sha256:') { 'DIGEST (immutable)' }
                elseif ($im -match ':latest$|:main$') { 'FLOATING (mutable!)' }
                elseif ($im -match ':[^/]+$') { 'TAG (mutable)' }
                else { 'UNTAGGED (=latest)' }
        A ("    {0,-58} {1}" -f $im, $kind)
    }
}

A "`n=== 5. ANSWER: the new path ==="
A ''
A "  Platform source (git-tracked, committed):"
A "    $repo\pacgate-ai\"
A ''
A "  Runtime / compose root (where you run docker compose from):"
A "    $newCB\"
A ''
A "  Compose entry points:"
A "    $newCB\compose.bundle.yaml     <- the file that started the live stack"
A "    $newCB\compose.prod.yaml       <- used by install.ps1"
A "    $newQM\compose.qm.yaml"
A ''
A "  Named volume that holds the database (NOT moved; it is a Docker volume):"
A "    pacgate-ai-bundle_pacgate-db-data"

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"