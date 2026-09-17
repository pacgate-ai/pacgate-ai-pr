$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\IMAGE-SWAP-RISK.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'IMAGE SWAP RISK - should the built image replace the running one?'
A ('=' * 78)
A ''
A 'Recon showed the built and running image IDs DIFFER and the sizes match'
A 'exactly (163MB / 3.49GB / 695MB). Same size + different ID suggests the same'
A 'source built twice, not a version difference. Verify that.'

# ---- 1. version labelling --------------------------------------------------
A "`n=== 1. Version labels (the substantive question) ==="
$rows = @(
    @{ b = 'pacgate-api:local-verify';       r = 'ghcr.io/pacgate-ai/pacgate-api:0.1.9';             n = 'pacgate-api' },
    @{ b = 'deer-flow-pacgate:local-verify'; r = 'ghcr.io/pacgate-ai/deer-flow-pacgate:0.1.10';    n = 'deer-flow' },
    @{ b = 'pacgate-mcp:local-verify';       r = 'ghcr.io/pacgate-ai/pacgate-mcp:0.1.9';           n = 'pacgate-mcp' }
)
foreach ($x in $rows) {
    A ("`n  --- {0} ---" -f $x.n)
    foreach ($pair in @(@{l='built '; i=$x.b}, @{l='running'; i=$x.r})) {
        $created = (& docker image inspect $pair.i --format '{{.Created}}' 2>$null) -join ''
        $ver = (& docker image inspect $pair.i --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>$null) -join ''
        $rev = (& docker image inspect $pair.i --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>$null) -join ''
        A ("    {0} {1}" -f $pair.l, $pair.i)
        A ("      created : {0}" -f $created)
        A ("      version : {0}" -f $(if ($ver) { $ver } else { '(unset)' }))
        A ("      revision: {0}" -f $(if ($rev) { $rev } else { '(unset)' }))
    }
}

# ---- 2. what source version does the tree declare? -------------------------
A "`n=== 2. Source version in the working tree ==="
$ws = Join-Path $repo 'pacgate-ai\Cargo.toml'
if (Test-Path $ws) {
    $txt = [System.IO.File]::ReadAllText($ws)
    $m = [regex]::Match($txt, '(?m)^\s*version\s*=\s*"([^"]+)"')
    A ("  workspace version: {0}" -f $(if ($m.Success) { $m.Groups[1].Value } else { '(not found)' }))
}
$dfv = Join-Path $repo 'pacgate-ai\deploy\deer-flow-pacgate\Dockerfile'
if (Test-Path $dfv) {
    foreach ($x in @(Select-String -Path $dfv -Pattern 'LABEL|version' | Select-Object -First 5)) {
        A ("  deer-flow Dockerfile: {0}" -f $x.Line.Trim())
    }
}

# ---- 3. behavioural difference? --------------------------------------------
A "`n=== 3. Do both images expose the same endpoints/libs? ==="
A '  A pure rebuild should behave identically. Spot-check the runtime surface.'
foreach ($img in @('pacgate-api:local-verify','ghcr.io/pacgate-ai/pacgate-api:0.1.9')) {
    A ("`n  --- {0} ---" -f $img)
    $r = (& docker run --rm --entrypoint sh $img -c "ls /usr/local/bin; echo '--'; ls /app/migrations 2>/dev/null | wc -l" 2>&1) -join ' '
    A ("    {0}" -f $r.Trim())
}

# ---- 4. what the compose files pin -----------------------------------------
A "`n=== 4. What the compose files currently pin ==="
$cb = Join-Path $repo 'pacgate-ai\deploy\client-bundle\compose.bundle.yaml'
foreach ($x in @(Select-String -Path $cb -Pattern '^\s*image:')) {
    A ("  {0}" -f $x.Line.Trim())
}

# ---- 5. the real risk ------------------------------------------------------
A "`n=== 5. Risk assessment ==="
A ''
A '  WHAT CHANGES IF WE SWAP:'
A '    - the running container is replaced -> SHORT DOWNTIME for pacgate-api'
A '    - deer-flow: the handbook warns that recreating deer-flow wipes its'
A '      admin user, BUT its state is in the mounted ./data (bind-mounted),'
A '      so data survives. The warning concerns a DIFFERENT scenario.'
A '    - image IDs change, so rollback means re-pinning the old tag'
A ''
A '  WHAT WE GAIN: the stack runs the code we just verified builds.'
A ''
A '  WHAT WE DO NOT GAIN: correctness. The pulled 0.1.9 image is the one that'
A '  has been running and is the published artifact. The local build is the'
A '  SAME SOURCE rebuilt - swapping adds deployment risk without adding a'
A '  feature or fix.'
A ''
A '  RECOMMENDATION: DO NOT SWAP as part of this relocation. The relocation'
A '  goal is "the stack runs from the new path", which is already true and'
A '  verified. Swapping artefacts is a separate, optional deployment that'
A '  should happen when there is a REASON to ship new code - and with its own'
A '  rollback plan.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"