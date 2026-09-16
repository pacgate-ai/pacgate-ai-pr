$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$src  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\MERGE-COMPLETENESS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'IS pacgate-law FULLY MERGED WITH pacgate-ai-pr?'
A ('=' * 74)
A ''
A 'Adversarial test: try to find something in pacgate-ai-pr that is NOT'
A 'represented in pacgate-law. If anything is missing, the answer is NO.'

# ============ 1. tracked files ==============================================
A "`n=== 1. Git-TRACKED content ==="
$srcRaw = Join-Path $env:TEMP 'mc-src.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$srcRaw`""
$srcFiles = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($srcRaw)) -split "`0" |
              Where-Object { $_ -ne '' })
A ("  pacgate-ai-pr tracked files : {0}" -f $srcFiles.Count)

$repoRaw = Join-Path $env:TEMP 'mc-repo.raw'
& cmd /c "git -c core.quotepath=false -C `"$repo`" ls-files > `"$repoRaw`""
$repoFiles = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($repoRaw)) -split "`r?`n" |
               Where-Object { $_ -ne '' })
$repoPA = @($repoFiles | Where-Object { $_ -like 'pacgate-ai/*' } |
            ForEach-Object { $_ -replace '^pacgate-ai/', '' })
A ("  pacgate-law tracked under pacgate-ai/ : {0}" -f $repoPA.Count)

# which source files are NOT in the monorepo?
# IMPORTANT: the import FLATTENED the Rust workspace -- source `pacgate-ai/X`
# became monorepo `pacgate-ai/X` (the outer dir), i.e. the inner `pacgate-ai/`
# prefix was promoted away. So the prefix must be stripped from BOTH sides.
# Stripping it from only one side made all 84 Rust/workflow files look missing.
$srcNorm = @($srcFiles | ForEach-Object { $_ -replace '^pacgate-ai/', '' })
$set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($f in $repoPA) { [void]$set.Add($f) }
$notIn = @($srcNorm | Where-Object { -not $set.Contains($_) })
A ("  source files NOT in the monorepo : {0}" -f $notIn.Count)

# classify each missing one
$cred = 0; $ignored = 0; $unexplained = New-Object System.Collections.Generic.List[string]
foreach ($f in $notIn) {
    if ($f -match 'pacgate-ai-assets/') { $cred++; continue }
    $r = & git -C $repo check-ignore --no-index ('pacgate-ai/' + $f) 2>&1
    if ($r) { $ignored++ } else { $unexplained.Add($f) }
}
A ("    excluded as credential tree : {0}" -f $cred)
A ("    excluded by .gitignore      : {0}" -f $ignored)
A ("    UNEXPLAINED                 : {0}" -f $unexplained.Count)
foreach ($u in $unexplained) { A ("      !!! " + $u) }
A ("  reconciliation: {0} imported + {1} ignored + {2} credential = {3}  (source {4})" -f `
    $repoPA.Count, $ignored, $cred, ($repoPA.Count + $ignored + $cred), $srcFiles.Count)

# ============ 2. untracked runtime state ====================================
A "`n=== 2. UNTRACKED runtime state (gitignored, per-machine) ==="
$pairs = @(
    @{ s = "$src\deploy\client-bundle\data";                             d = "$repo\pacgate-ai\deploy\client-bundle\data" },
    @{ s = "$src\deploy\client-bundle\openviking";                       d = "$repo\pacgate-ai\deploy\client-bundle\openviking" },
    @{ s = "$src\deploy\client-bundle\.env";                             d = "$repo\pacgate-ai\deploy\client-bundle\.env" },
    @{ s = "$src\deploy\client-bundle\deer-flow-extensions-config.json"; d = "$repo\pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.json" },
    @{ s = "$src\deploy\qm-pacgate\node_modules";                        d = "$repo\pacgate-ai\deploy\qm-pacgate\node_modules" },
    @{ s = "$src\deploy\qm-pacgate\.env";                                d = "$repo\pacgate-ai\deploy\qm-pacgate\.env" }
)
foreach ($p in $pairs) {
    $so = if (Test-Path $p.s) { if (Test-Path $p.s -PathType Container) { @(Get-ChildItem $p.s -Recurse -File -Force -EA SilentlyContinue).Count } else { 1 } } else { 'absent' }
    $dn = if (Test-Path $p.d) { if (Test-Path $p.d -PathType Container) { @(Get-ChildItem $p.d -Recurse -File -Force -EA SilentlyContinue).Count } else { 1 } } else { 'ABSENT' }
    $ok = if ($so -eq 'absent') { 'n/a' } elseif ($dn -eq 'ABSENT') { 'MISSING' } elseif ([int]$dn -ge [int]$so) { 'OK' } else { 'PARTIAL' }
    A ("  {0,-34} src={1,-8} dst={2,-8} {3}" -f (Split-Path -Leaf $p.s), $so, $dn, $ok)
}

# ============ 3. what is deliberately NOT merged ============================
A "`n=== 3. Deliberately NOT merged (and why) ==="
$excl = @(
    @{ n = 'pacgate-ai-assets/';        why = 'own git repo; committing needs deleting its .git (severs JZKK720/pacgate-ai link). DEFERRED.' },
    @{ n = 'deer-flow/';                why = 'own git repo (122k files); ships via its pacgate-layer branch.' },
    @{ n = 'pacgate-ai/target/';        why = '4.5 GB Rust build output; regenerable.' },
    @{ n = 'client-bundle/data/';       why = '1.9 GB client data; per-machine, never in git.' },
    @{ n = 'git HISTORY';               why = 'import was a SQUASH. pacgate-ai-pr has 158 commits; the monorepo has none of them.' },
    @{ n = 'REMOTES';                   why = 'pacgate-law has NO remote. pacgate-ai-pr has origin + fork.' }
)
foreach ($e in $excl) { A ("  {0,-26} {1}" -f $e.n, $e.why) }

# ============ 4. history + remote ===========================================
A "`n=== 4. History and remotes ==="
A ("  pacgate-ai-pr commits : {0}" -f ((& git -C $src rev-list --all --count 2>$null) -join ''))
A ("  pacgate-law commits   : {0}" -f ((& git -C $repo rev-list --all --count 2>$null) -join ''))
A "  pacgate-ai-pr remotes :"
& git -C $src remote -v 2>$null | ForEach-Object { A ("    " + $_) }
$rr = @(& git -C $repo remote -v 2>$null)
A ("  pacgate-law remotes   : {0}" -f $(if ($rr.Count) { '' } else { 'NONE' }))
foreach ($x in $rr) { A ("    " + $x) }

# ============ 5. working tree ===============================================
A "`n=== 5. Working tree state ==="
$st = @(& git -C $repo status --porcelain)
A ("  uncommitted entries: {0}" -f $st.Count)
foreach ($s in ($st | Select-Object -First 10)) { A ("    " + $s) }

# ============ 6. scratch files left behind ==================================
A "`n=== 6. Untracked scratch files in the source (not migrated) ==="
$scratch = @(& git -C $src status --porcelain | Where-Object { $_ -match '^\?\?' })
A ("  count: {0}" -f $scratch.Count)
foreach ($s in $scratch) { A ("    " + $s) }

# ============ VERDICT =======================================================
A "`n=== VERDICT ==="
$fullyMerged = ($unexplained.Count -eq 0)
if ($fullyMerged) {
    A '  CONTENT: yes - every tracked file is either imported or excluded for a'
    A '           documented reason (credential tree / gitignore).'
} else {
    A ("  CONTENT: NO - {0} file(s) unaccounted for." -f $unexplained.Count)
}
A '  HISTORY: no - the import was a squash; the 158 source commits are not here.'
A '  REMOTE : no - pacgate-law has no remote, so nothing is backed up off-machine.'
A ''
A '  => "Fully merged" is TRUE for working content, FALSE for history and remote.'

Remove-Item -LiteralPath $srcRaw,$repoRaw -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"