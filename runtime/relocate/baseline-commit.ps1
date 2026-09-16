$ErrorActionPreference = 'Stop'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\BASELINE-COMMIT.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'BASELINE COMMIT (pre-relocation checkpoint)'
A ('=' * 62)
A ''

# ---- already committed? ----------------------------------------------------
# NOTE: with 0 commits `git rev-list --count HEAD` writes "fatal: ambiguous
# argument 'HEAD'" to stderr. PowerShell surfaces native stderr as an error and
# $ErrorActionPreference='Stop' would abort the script, so measure the commit
# count a way that is well-defined on an empty repo instead.
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$count = (& git -C $repo rev-list --all --count 2>$null) -join ''
$ErrorActionPreference = $old
$hasCommit = ($count -match '^\d+$') -and ([int]$count -gt 0)

if ($hasCommit) {
    A "  repo already has $count commit(s); nothing to do (idempotent)"
    [System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
    exit 0
}
A '  repo has 0 commits - creating the baseline'

# ---- identity --------------------------------------------------------------
$name = & git -C $repo config user.name
if (-not $name) {
    & git -C $repo config user.name  'PacGate Migration'
    & git -C $repo config user.email 'migration@pacgate.local'
    A '  set local git identity (PacGate Migration)'
} else {
    A "  git identity already set: $name"
}

# ---- stage -----------------------------------------------------------------
& git -C $repo add -A
$staged = @(& git -C $repo diff --cached --name-only)
A "`n  staged paths: $($staged.Count)"

# ---- guards (same rules as the platform import) ----------------------------
A "`n  --- guard scan ---"
$bad = 0
foreach ($pat in @('OPERATOR\.md$', 'remote-handbook', 'MCP授权', 'V2\.docx')) {
    $h = @($staged | Where-Object { $_ -match $pat })
    if ($h.Count) { $bad += $h.Count; A ("  !!! CREDENTIAL: $pat -> $($h.Count)") }
    else { A ("  OK  no credential match '$pat'") }
}
foreach ($pat in @('(^|/)deer-flow(/|$)', '(^|/)target(/|$)', 'client-bundle/data/', '\.zip$')) {
    $h = @($staged | Where-Object { $_ -match $pat })
    if ($h.Count) { $bad += $h.Count; A ("  !!! BULK: $pat -> $($h.Count)") }
    else { A ("  OK  no bulk match '$pat'") }
}
if ($bad -gt 0) {
    & git -C $repo reset | Out-Null
    A "`nABORTED: $bad forbidden path(s) staged. Index reset."
    [System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
    throw 'baseline commit guards failed'
}

# ---- commit ----------------------------------------------------------------
A "`n  --- committed paths ---"
$staged | ForEach-Object { A ("    " + $_) }

& git -C $repo commit -q -m "chore: baseline local monorepo before pacgate-ai-pr relocation

Checkpoint of the pre-existing local content (AGENTS.md, docs/, runtime/,
DEER-FLOW-INTEGRATION.md) so the incoming platform import appears as a
reviewable diff rather than hundreds of untracked files.

The pacgate-ai gitlink is intentionally retained in this commit; it is
removed by the staging step that follows."

A "`n  HEAD: " 
A ("    " + (& git -C $repo log --oneline -1))

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
