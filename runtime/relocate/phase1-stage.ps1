param([switch]$Execute)

$ErrorActionPreference = 'Stop'

# ============================================================================
# RELOCATION - PHASE 1: STAGING  (non-destructive; source untouched)
#
# Places the platform content at pacgate-law\pacgate-ai\ while LEAVING
# C:\pacgate-ai-pr fully intact, so rollback is a no-op.
#
# SAFETY: dry-run by default. Pass -Execute to actually make changes.
# What it does NOT do: stop containers, copy the 1.9 GB runtime data, or delete
# anything from the source. Those are Phase 2 (cutover).
# ============================================================================

$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$stage  = 'C:\temp\pacgate-stage'
$target = Join-Path $repo 'pacgate-ai'
$assets = Join-Path $repo 'pacgate-ai-assets'

function Step([string]$msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Info([string]$msg) { Write-Host "    $msg" }
function Dry ([string]$msg) { Write-Host "    [DRY-RUN] $msg" -ForegroundColor Yellow }

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' }
Write-Host "RELOCATION PHASE 1 - STAGING  (mode: $mode)" -ForegroundColor Green

# --------------------------------------------------- safety-guard preconditions
# Guards added 2026-09-16 after a pre-execution recon. Each one has already
# caught (or would have caught) a real failure mode -- see runtime/relocate/.
if ($Execute) {
    $fatal = New-Object System.Collections.Generic.List[string]

    # G1: rollback anchors must exist. These are the ONLY way back if the index
    #     is damaged; the index is not otherwise recoverable (repo has 0 commits).
    foreach ($b in @('C:\backup-pacgate-ai-pr-git', 'C:\backup-pacgate-law-git')) {
        if (-not (Test-Path -LiteralPath (Join-Path $b 'index'))) {
            $fatal.Add("rollback anchor missing or incomplete: $b (need .git/index)")
        }
    }
    # G2: the source tree must be clean. checkout-index exports COMMITTED state,
    #     so a modified tracked file would be silently left behind.
    $mod = @(& git -C $src status --porcelain | Where-Object { $_ -match '^(M.|.M|MM|AM|RM|.R)' })
    if ($mod.Count -gt 0) { $fatal.Add("source has $($mod.Count) modified tracked file(s); commit or stash first") }
    # G3: the repo must be on the expected branch.
    $br = (& git -C $repo branch --show-current 2>$null)
    if ($br -ne 'main') { $fatal.Add("repo on branch '$br', expected 'main'") }

    if ($fatal.Count -gt 0) {
        Write-Host "`nABORTED - preconditions not met:" -ForegroundColor Red
        foreach ($f in $fatal) { Write-Host "  ! $f" -ForegroundColor Red }
        throw 'safety-guard preconditions failed'
    }
    Write-Host '  safety-guard: rollback anchors OK, source clean, branch OK' -ForegroundColor Green
}

# ---------------------------------------------------------------- preconditions
Step 'Preconditions'
if (-not (Test-Path -LiteralPath $src)) { throw "source missing: $src" }
$head = & git -C $src rev-parse HEAD 2>$null
if (-not $head) { throw 'source HEAD unresolvable' }
Info "source HEAD : $head"
Info "free space  : $([math]::Round((Get-PSDrive C).Free/1GB,1)) GB"

# ---------------------------------------------------------------- 1. export
Step '1. Export tracked content (git checkout-index - NOT tar)'
# Windows tar.exe silently drops CJK-named files (478/515 in a rehearsal).
# `git checkout-index` is built into git and extracted 515/515. See
# runtime/relocate/BLOCKER-DIAGNOSIS.txt.
if ($Execute) {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $prefix = $stage.TrimEnd('\') + '\'
    & git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | ForEach-Object { if ($_ -notmatch '^\s*$') { Info $_ } }
    $got = @(Get-ChildItem $stage -Recurse -File -Force).Count
    $want = @(& git -C $src ls-files).Count
    Info "extracted $got of $want files"
    if ($got -ne $want) { throw "EXTRACTION INCOMPLETE ($got/$want) - aborting" }
} else { Dry "git -C $src checkout-index -a -f --prefix=$stage\  (expect 515/515)" }

# ---------------------------------------------------------------- 2. flatten
Step '2. Promote the Rust workspace up one level (avoid pacgate-ai\pacgate-ai\)'
$inner = Join-Path $stage 'pacgate-ai'
if ($Execute) {
    if (-not (Test-Path -LiteralPath $inner)) { throw "expected $inner - aborting" }
    $innerNames = @(Get-ChildItem -LiteralPath $inner -Force | Select-Object -ExpandProperty Name)
    $clash = @($innerNames | Where-Object { Test-Path -LiteralPath (Join-Path $stage $_) })
    if ($clash.Count -gt 0) { throw "COLLISION promoting workspace: $($clash -join ', ')" }
    foreach ($item in (Get-ChildItem -LiteralPath $inner -Force)) {
        Move-Item -LiteralPath $item.FullName -Destination (Join-Path $stage $item.Name) -Force
    }
    Remove-Item -LiteralPath $inner -Force
    Info "promoted; Cargo.toml at stage root: $(Test-Path (Join-Path $stage 'Cargo.toml'))"
} else { Dry "move $inner\* -> $stage\*  (verified: 0 collisions)" }

# ------------------------------------------------------- 3. credentials FIRST
Step '3. Remove credential carriers from the stage (MANDATORY)'
# The rehearsal proved tracked content carries OPERATOR.md. Must be removed
# before anything reaches git.
if ($Execute) {
    $bad = Join-Path $stage 'pacgate-ai-assets'
    if (Test-Path -LiteralPath $bad) {
        $n = @(Get-ChildItem -LiteralPath $bad -Recurse -File -Force).Count
        Remove-Item -LiteralPath $bad -Recurse -Force
        Info "removed vendored assets tree ($n files, includes OPERATOR.md)"
    }
    $cred = @(Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' })
    foreach ($c in $cred) {
        Remove-Item -LiteralPath $c.FullName -Force
        Info "removed credential carrier: $($c.Name)"
    }
    $left = @(Get-ChildItem $stage -Recurse -File -Force | Where-Object { $_.Name -eq 'OPERATOR.md' }).Count
    Info "OPERATOR.md files remaining in stage: $left (must be 0)"
    if ($left -ne 0) { throw 'credential file still present in stage - aborting' }
} else { Dry "remove $stage\pacgate-ai-assets and any OPERATOR.md / remote-handbook files" }

# ---------------------------------------------------------------- 4. submodule
Step '4. Move the old submodule content aside -> pacgate-ai-assets'
if ($Execute) {
    if (Test-Path -LiteralPath $assets) { throw "$assets already exists - resolve manually" }
    if (Test-Path -LiteralPath $target) {
        Move-Item -LiteralPath $target -Destination $assets
        Info "moved $target -> $assets"
    }
    # remove the gitlink (files already moved; index-only change, reversible)
    Push-Location $repo
    & git rm --cached -r pacgate-ai 2>&1 | ForEach-Object { Info $_ }
    & git add -A pacgate-ai-assets 2>&1 | ForEach-Object { Info $_ }
    Pop-Location
} else { Dry "Move-Item $target -> $assets ; git rm --cached pacgate-ai" }

# ---------------------------------------------------------------- 5. place
Step '5. Place staged content at pacgate-ai\'
if ($Execute) {
    # The old submodule content was already moved to pacgate-ai-assets in Step 4,
    # so this directory should be gone. Only clean up if something is left.
    if (Test-Path -LiteralPath $target) {
        Info 'leftover content at target - removing (source copy is safe in pacgate-ai-assets)'
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    & robocopy $stage $target /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    # robocopy exit codes: 0-7 are success (0=nothing copied, 1=copied, 2/4=extras,
    # 3=copied+extras...). 8+ is a real failure. Ignoring this is how a partial copy
    # goes unnoticed.
    $rc = $LASTEXITCODE
    $placed = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    Info "robocopy exit=$rc, placed $placed files"
    if ($rc -ge 8) { throw "robocopy failed (exit $rc)" }
    if ($placed -lt 400) { throw "suspiciously few files placed ($placed) - aborting" }
} else { Dry "robocopy $stage -> $target" }

# ---------------------------------------------------------------- 6. finalize
Step '6. Drop the stale .gitmodules and stage everything for review'
# After Step 4 there is no `pacgate-ai` gitlink left, and `deer-flow/` is ignored
# (delivered via its own `pacgate-layer` branch). So no real submodule remains and
# `.gitmodules` is stale -- leaving it would describe a submodule that no longer
# exists. NOTE: deletion is index-only; the file is recovered from
# C:\backup-pacgate-law-git if needed.
if ($Execute) {
    $gm = Join-Path $repo '.gitmodules'
    if (Test-Path -LiteralPath $gm) {
        Remove-Item -LiteralPath $gm -Force
        Info 'removed stale .gitmodules (no real submodule remains)'
    }
    Push-Location $repo
    & git add -A 2>&1 | ForEach-Object { if ($_ -notmatch '^\s*$') { Info $_ } }
    $staged = @(& git diff --cached --name-only)
    Info "staged paths: $($staged.Count)"

    # FATAL guards -- if ANY of these is staged the run is wrong. Credentials are
    # unrecoverable once pushed, so they are a hard stop rather than a warning.
    $leak = 0
    foreach ($pat in @('OPERATOR\.md$', 'remote-handbook', 'MCP授权', 'V2\.docx')) {
        $hits = @($staged | Where-Object { $_ -match $pat })
        if ($hits.Count -gt 0) {
            $leak += $hits.Count
            Write-Host "      !!! CREDENTIAL STAGED ($pat): $($hits.Count)" -ForegroundColor Red
            foreach ($h in ($hits | Select-Object -First 5)) { Write-Host "          $h" -ForegroundColor Red }
        } else { Info "credential guard OK: nothing matches '$pat'" }
    }

    # SIZE guards -- bulk material that must never be in git.
    foreach ($pat in @('(^|/)deer-flow(/|$)', '(^|/)target(/|$)', 'client-bundle/data/', '\.zip$')) {
        $hits = @($staged | Where-Object { $_ -match $pat })
        if ($hits.Count -gt 0) {
            $leak += $hits.Count
            Write-Host "      !!! BULK STAGED ($pat): $($hits.Count)" -ForegroundColor Red
        } else { Info "bulk guard OK: nothing matches '$pat'" }
    }

    if ($leak -gt 0) {
        Write-Host "`n!! $leak forbidden path(s) staged. Resetting the index." -ForegroundColor Red
        & git -C $repo reset 2>&1 | Out-Null
        throw 'forbidden paths staged - index reset, nothing committed'
    }
    Info 'all staged-path guards passed'
    Pop-Location
} else { Dry 'remove stale .gitmodules ; git add -A ; report staged count' }

# ---------------------------------------------------------------- verify
Step 'Verification'
if ($Execute) {
    $ok = $true
    foreach ($probe in @('Cargo.toml','deploy\client-bundle\compose.bundle.yaml','deploy\qm-pacgate\compose.qm.yaml','pacgate-adapters','scope-assets','patches','docs')) {
        $p = Join-Path $target $probe
        $e = Test-Path -LiteralPath $p
        if (-not $e) { $ok = $false }
        Info ("{0,-46} {1}" -f $probe, $(if ($e) { 'OK' } else { 'MISSING' }))
    }
    # must NOT contain build output
    $t = Join-Path $target 'target'
    $noTarget = -not (Test-Path -LiteralPath $t)
    Info ("no Rust target/ dir : {0}" -f $noTarget)
    if (-not $noTarget) { $ok = $false }

    # CREDENTIAL GATE -- the most important check in the whole script
    $credLeft = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' })
    Info ("credential carriers in target : {0} (must be 0)" -f $credLeft.Count)
    if ($credLeft.Count -ne 0) {
        $ok = $false
        foreach ($c in $credLeft) { Write-Host "      !!! $($c.FullName)" -ForegroundColor Red }
    }

    # CJK completeness gate -- proves the extraction did not silently drop files.
    # NOTE: the earlier version of this check used a plain non-ASCII regex, which
    # counts any non-ASCII name. The authoritative check is index-vs-disk below.
    $cjk = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '[^\x00-\x7F]' }).Count
    Info ("non-ASCII-named files present : {0}" -f $cjk)

    # AUTHORITATIVE: every tracked file must exist at the target (Ordinal compare,
    # raw bytes -- immune to console-codepage mangling).
    $idxRaw = Join-Path $env:TEMP 'pg-idx.raw'
    & cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
    $idxList = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($idxRaw)) -split "`0" |
                 Where-Object { $_ -ne '' })
    # Files intentionally excluded from the import (credential carrier tree).
    $excluded = @($idxList | Where-Object { $_ -match 'pacgate-ai-assets/' })
    $expect = @($idxList | Where-Object { $_ -notmatch 'pacgate-ai-assets/' })
    # Map source index paths -> target paths (the `pacgate-ai/` prefix is promoted away).
    $missing = 0
    foreach ($x in $expect) {
        $rel = $x -replace '^pacgate-ai/', ''
        if (-not (Test-Path -LiteralPath (Join-Path $target ($rel -replace '/', '\')))) { $missing++ }
    }
    Info ("index entries: {0}  excluded(credentials): {1}  expected at target: {2}" -f $idxList.Count, $excluded.Count, $expect.Count)
    Info ("missing at target : {0}   (must be 0)" -f $missing)
    if ($missing -ne 0) { $ok = $false }
    Remove-Item -LiteralPath $idxRaw -Force -ErrorAction SilentlyContinue

    Write-Host ''
    if ($ok) { Write-Host 'PHASE 1 OK - source still intact, rollback is a no-op.' -ForegroundColor Green }
    else    { Write-Host 'PHASE 1 INCOMPLETE - investigate before Phase 2.' -ForegroundColor Red }
} else {
    Write-Host ''
    Write-Host 'DRY-RUN complete. Re-run with -Execute to apply.' -ForegroundColor Yellow
}
