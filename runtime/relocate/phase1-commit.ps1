$ErrorActionPreference = 'Stop'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\PHASE1-COMMIT.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'PHASE 1 -- COMMIT THE STAGED PLATFORM'
A ('=' * 62)

# --- final gate before writing history --------------------------------------
$staged = @(& git -C $repo diff --cached --name-only)
A ("  staged paths total: {0}" -f $staged.Count)

$cred = @($staged | Where-Object { $_ -match 'OPERATOR\.md$|remote-handbook|[\\/]MCP授权[\\/]|V2\.docx' })
A ("  credential paths staged: {0}  (must be 0)" -f $cred.Count)
foreach ($c in $cred) { A ("    !!! " + $c) }

$bulk = @($staged | Where-Object { $_ -match '^(deer-flow|pacgate-ai-assets)/|/target/|client-bundle/data/|\.zip$' })
A ("  bulk paths staged     : {0}  (must be 0)" -f $bulk.Count)
foreach ($b in $bulk) { A ("    !!! " + $b) }

if ($cred.Count -gt 0 -or $bulk.Count -gt 0) {
    A "`nABORTED -- forbidden paths staged."
    [System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
    throw 'pre-commit gate failed'
}
A '  pre-commit gate PASSED'

# --- summary by top-level destination ---------------------------------------
A "`n  --- staged, by destination ---"
$b = @{}
foreach ($s in $staged) {
    $t = ($s -split '/')[0]
    if (-not $b.ContainsKey($t)) { $b[$t] = 0 }
    $b[$t]++
}
foreach ($k in ($b.Keys | Sort-Object)) { A ("    {0,-24} {1,6}" -f $k, $b[$k]) }

# --- commit -----------------------------------------------------------------
$msg = @"
feat(monorepo): import PacGate platform from C:\pacgate-ai-pr

Consolidates the standalone platform repo into this monorepo under
pacgate-ai/, so this becomes the single local home for all services,
codebases and runtimes and C:\pacgate-ai-pr can be retired.

Imported (456 tracked source paths, 23.8 MB):
  pacgate-ai/         Rust workspace (crates/, wasm-crates/, Cargo.toml)
  pacgate-ai/deploy/  compose files, client-bundle, qm-pacgate, handbooks
  pacgate-ai/patches/ pacgate-adapters/ scope-assets/ plans/ scripts/

Deliberately NOT imported:
  - 59 files from the vendored assets tree (contains a live credential file)
  - the 4.5 GB Rust target/ and 1.9 GB client-bundle data/ (per-machine)
  - deer-flow/ and pacgate-ai-assets/ (own repos, ignored not embedded)

Method notes (both were failure modes caught during rehearsal):
  - exported with `git checkout-index`, NOT `git archive`+tar: Windows tar.exe
    silently drops every non-ASCII filename
  - credentials removed during staging; verified 0 carriers in the result

Bind-mount cutover to the new paths is a separate step and requires a
maintenance window; the original location is untouched and remains the
rollback.
"@

Push-Location $repo
try {
    # Write the message to a UTF-8 file and use -F (PowerShell has no heredoc).
    $msgFile = Join-Path $env:TEMP 'pg-commit-msg.txt'
    [System.IO.File]::WriteAllText($msgFile, $msg, (New-Object System.Text.UTF8Encoding($false)))
    & git commit -q -F $msgFile
    Remove-Item -LiteralPath $msgFile -Force -ErrorAction SilentlyContinue
    A "`n  committed:"
    A ("    " + (& git log --oneline -1))
} finally { Pop-Location }

$count = (& git -C $repo rev-list --all --count) -join ''
A ("  total commits: {0}" -f $count)

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
