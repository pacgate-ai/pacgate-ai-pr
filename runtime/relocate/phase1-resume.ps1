$ErrorActionPreference = 'Continue'
$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$stage  = 'C:\temp\pacgate-stage'
$target = Join-Path $repo 'pacgate-ai'
$out    = Join-Path $repo 'runtime\relocate\PHASE1-RESUME.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }
function Step([string]$m) { Write-Host "`n>>> $m" -ForegroundColor Cyan; $L.Add(""); $L.Add(">>> $m") }

A 'PHASE 1 RESUME (Step 4b + 5 + 6 + verification)'
A ('=' * 62)
A 'The interrupted move is repaired (see RECOVERY.txt). Resuming the remaining work.'

# ============================== 4b. remove the gitlink =======================
Step '4b. Remove the pacgate-ai gitlink from the index'
$before = @(& git -C $repo ls-files --stage | Where-Object { $_ -match '\tpacgate-ai$' })
A ("  gitlink present before: {0}" -f $before.Count)
foreach ($b in $before) { A ("    " + $b) }

if ($before.Count -gt 0) {
    $r = & git -C $repo rm --cached -r pacgate-ai 2>&1
    foreach ($x in $r) { A ("    " + $x) }
}
$after = @(& git -C $repo ls-files --stage | Where-Object { $_ -match '\tpacgate-ai$' })
A ("  gitlink present after : {0}  (must be 0)" -f $after.Count)

# ============================== 5. place content =============================
Step '5. Place staged platform content at pacgate-ai\'
if (Test-Path -LiteralPath $target) {
    $n = @(Get-ChildItem $target -Recurse -Force -ErrorAction SilentlyContinue).Count
    A "  target exists with $n entries - removing (source copy is safe in pacgate-ai-assets)"
    if ($n -gt 0) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
& robocopy $stage $target /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
$rc = $LASTEXITCODE
$placed = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue).Count
A ("  robocopy exit={0}  placed {1} files" -f $rc, $placed)
if ($rc -ge 8) { A '  ABORT: robocopy failed'; [System.IO.File]::WriteAllLines($out,$L,(New-Object System.Text.UTF8Encoding($false))); exit 1 }
if ($placed -lt 400) { A '  ABORT: too few files'; [System.IO.File]::WriteAllLines($out,$L,(New-Object System.Text.UTF8Encoding($false))); exit 1 }

# ============================== 6. stage =====================================
Step '6. Drop the stale .gitmodules and stage everything'
$gm = Join-Path $repo '.gitmodules'
if (Test-Path -LiteralPath $gm) {
    Remove-Item -LiteralPath $gm -Force
    A '  removed stale .gitmodules (no real submodule remains)'
}
& git -C $repo add -A 2>&1 | Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object { A ("    " + $_) }

$staged = @(& git -C $repo diff --cached --name-only)
A ("  staged paths: {0}" -f $staged.Count)

A "`n  --- FATAL guards ---"
$leak = 0
foreach ($pat in @('OPERATOR\.md$', 'remote-handbook', 'MCP授权', 'V2\.docx')) {
    $h = @($staged | Where-Object { $_ -match $pat })
    if ($h.Count) { $leak += $h.Count; A ("  !!! CREDENTIAL ($pat): $($h.Count)"); foreach ($x in ($h|Select-Object -First 5)) { A ("      " + $x) } }
    else { A ("  OK  no credential match: $pat") }
}
foreach ($pat in @('(^|/)deer-flow(/|$)', '(^|/)target(/|$)', 'client-bundle/data/', '\.zip$', '^pacgate-ai-assets/')) {
    $h = @($staged | Where-Object { $_ -match $pat })
    if ($h.Count) { $leak += $h.Count; A ("  !!! BULK ($pat): $($h.Count)"); foreach ($x in ($h|Select-Object -First 5)) { A ("      " + $x) } }
    else { A ("  OK  no bulk match: $pat") }
}
if ($leak -gt 0) {
    & git -C $repo reset | Out-Null
    A "`n  ABORTED: $leak forbidden path(s) staged. Index reset."
    [System.IO.File]::WriteAllLines($out,$L,(New-Object System.Text.UTF8Encoding($false))); exit 1
}
A '  all guards passed'

# ============================== verification =================================
Step 'Verification'
$ok = $true
foreach ($probe in @('Cargo.toml','deploy\client-bundle\compose.bundle.yaml','deploy\qm-pacgate\compose.qm.yaml',
                     'pacgate-adapters','scope-assets','patches','docs')) {
    $e = Test-Path -LiteralPath (Join-Path $target $probe)
    if (-not $e) { $ok = $false }
    A ("  {0,-46} {1}" -f $probe, $(if ($e) { 'OK' } else { 'MISSING' }))
}

A ("  no target/ dir                : {0}" -f (-not (Test-Path (Join-Path $target 'target'))))
if (Test-Path (Join-Path $target 'target')) { $ok = $false }

$cred = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' -or $_.FullName -like '*MCP*' })
A ("  credential carriers in target : {0}  (must be 0)" -f $cred.Count)
if ($cred.Count) { $ok = $false; foreach ($c in $cred) { A ("      !!! " + $c.FullName) } }

# AUTHORITATIVE completeness: every tracked source file must exist at target
# (minus the credential tree intentionally excluded from the import).
$idxRaw = Join-Path $env:TEMP 'pg-idx2.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
$idxList = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($idxRaw)) -split "`0" |
             Where-Object { $_ -ne '' })
$excluded = @($idxList | Where-Object { $_ -match 'pacgate-ai-assets/' })
$expect   = @($idxList | Where-Object { $_ -notmatch 'pacgate-ai-assets/' })
$missing = 0
foreach ($x in $expect) {
    $rel = $x -replace '^pacgate-ai/', ''
    if (-not (Test-Path -LiteralPath (Join-Path $target ($rel -replace '/','\')))) { $missing++ }
}
A ("  index entries {0} | excluded(credential tree) {1} | expected {2}" -f $idxList.Count, $excluded.Count, $expect.Count)
A ("  MISSING at target: {0}  (must be 0)" -f $missing)
if ($missing -ne 0) { $ok = $false }
Remove-Item -LiteralPath $idxRaw -Force -ErrorAction SilentlyContinue

$nonAscii = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '[^\x00-\x7F]' }).Count
A ("  non-ASCII-named files         : {0}" -f $nonAscii)

A ''
if ($ok) { A 'PHASE 1 OK - source untouched, rollback is a no-op.' }
else     { A 'PHASE 1 INCOMPLETE - investigate before Phase 2.' }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "wrote $out"
