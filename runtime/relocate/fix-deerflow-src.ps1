$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$src  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\FIX-DEERFLOW-SRC.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'FIX: copy the missing generated deer-flow source'
A ('=' * 78)
A ''
A 'Gap found during the e2e audit: my cutover copied data/, openviking/, .env'
A 'and node_modules, but MISSED deploy/deer-flow-src (574 files / 31.3 MB).'
A 'It is gitignored + untracked, so Phase 1 correctly skipped it - but the'
A 'frontend build needs it, and the old repo had it from a previous build.'
A ''
A 'Copying it closes the gap without needing a network clone.'

$s = Join-Path $src 'deploy\deer-flow-src'
$d = Join-Path $pa  'deploy\deer-flow-src'

A ("`n  source: {0}" -f $s)
A ("  dest  : {0}" -f $d)
A ("  source present: {0}" -f (Test-Path $s))
A ("  dest present  : {0}" -f (Test-Path $d))

if (-not (Test-Path $s)) {
    A '  ABORT: source missing'
} elseif (Test-Path $d) {
    A '  dest already exists - nothing to do'
} else {
    $t0 = Get-Date
    & robocopy $s $d /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    $secs = [math]::Round(((Get-Date)-$t0).TotalSeconds, 1)
    $n = @(Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    A ("  robocopy exit={0}  files={1}  {2}s" -f $rc, $n, $secs)
    if ($rc -ge 8) { A '  FAILED' }
}

# ---- verify ----------------------------------------------------------------
A "`n=== Verify ==="
if (Test-Path $d) {
    $so = @(Get-ChildItem $s -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $dn = @(Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    A ("  source files: {0}" -f $so)
    A ("  dest files  : {0}" -f $dn)
    A ("  match       : {0}" -f ($dn -ge $so))
    A ("  frontend dir: {0}" -f (Test-Path (Join-Path $d 'frontend')))
    A ("  package.json: {0}" -f (Test-Path (Join-Path $d 'frontend\package.json')))
}

# ---- confirm it is still ignored (must NOT enter git) ----------------------
A "`n=== Confirm it stays out of git ==="
$r = & git -C $repo check-ignore --no-index -v 'pacgate-ai/deploy/deer-flow-src/frontend/package.json' 2>&1
A ("  ignored: {0}" -f $(if ($r) { ($r -join ' ; ') } else { 'NOT IGNORED - would be staged!' }))
$st = @(& git -C $repo status --porcelain)
A ("  uncommitted entries after copy: {0}  (0 = correctly ignored)" -f $st.Count)
foreach ($x in ($st | Select-Object -First 5)) { A ("    " + $x) }

A "`n=== Next step ==="
A '  The frontend can now build. The supported entry point is'
A '  deploy/build-frontend.ps1 (it also applies the PacGate frontend overrides).'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"