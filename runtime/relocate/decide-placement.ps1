$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\placement-decision.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('PLACEMENT DECISION: root vs pacgate-ai/ subfolder')
$r.Add('=' * 66)
$r.Add('')

$src = 'C:\pacgate-ai-pr'

# ---------------------------------------------------------------------------
# KEY QUESTION: does the placement choice actually cost us history?
# ---------------------------------------------------------------------------
$r.Add('=== Does the placement change the history cost? ===')
$r.Add('')
$r.Add('  History can only be carried if tracked paths keep their EXACT relative')
$r.Add('  layout. Landing at the repo root preserves it; nesting under pacgate-ai/')
$r.Add('  shifts every path and would need a filter-repo rewrite.')
$r.Add('')
$r.Add('  BUT: the source history contains 4 publicly-exposed credential files')
$r.Add('  (commit 01a4644 among others). Carrying the history would re-import them.')
$r.Add('  The recommended import is therefore a SQUASH -> no history is carried.')
$r.Add('')
$r.Add('  => If we squash, the placement choice costs NOTHING for history,')
$r.Add('     because there is no history to misalign.')
$r.Add('')

# ---------------------------------------------------------------------------
# The nesting problem and how to flatten it
# ---------------------------------------------------------------------------
$r.Add('=== The nesting problem (and the fix) ===')
$r.Add('')
$r.Add('  Source layout:')
$r.Add('      C:\pacgate-ai-pr\Cargo.toml            <-- NO (Cargo.toml is inside pacgate-ai\)')
$r.Add('      C:\pacgate-ai-pr\pacgate-ai\Cargo.toml <-- the Rust workspace')
$r.Add('      C:\pacgate-ai-pr\deploy\')
$r.Add('')
$r.Add('  Naive copy to pacgate-ai\ would produce:')
$r.Add('      pacgate-law\pacgate-ai\pacgate-ai\Cargo.toml     <-- double nest')
$r.Add('')
$r.Add('  FIX: promote the Rust workspace contents up one level and merge:')
$r.Add('      move pacgate-ai\pacgate-ai\*  ->  pacgate-ai\*')
$r.Add('')
$r.Add('  Collision check for that promotion (does anything at pacgate-ai\')
$r.Add('  already use these names?):')
$r.Add('')

$inner = @(Get-ChildItem -LiteralPath (Join-Path $src 'pacgate-ai') -Force | Select-Object -ExpandProperty Name)
$outer = @(Get-ChildItem -LiteralPath $src -Force | Where-Object { $_.Name -ne 'pacgate-ai' } | Select-Object -ExpandProperty Name)
$clash = @($inner | Where-Object { $outer -contains $_ })
$r.Add("      inner (Rust workspace): $($inner.Count) entries")
$r.Add("      outer (platform root) : $($outer.Count) entries")
$r.Add("      COLLISIONS           : $($clash.Count)")
foreach ($c in $clash) { $r.Add("          *** $c  (needs manual merge)") }
if ($clash.Count -eq 0) { $r.Add('          none -> promotion is a clean move') }
$r.Add('')

$r.Add('=== Resulting tree (flattened, content under pacgate-ai/) ===')
$r.Add('')
$r.Add('  pacgate-law\')
$r.Add('  |- pacgate-ai\')
$r.Add('  |    |- Cargo.toml  crates\  wasm-crates\  migrations\  workflows\')
$r.Add('  |    |- Dockerfile  Cargo.lock')
$r.Add('  |    |- deploy\           (compose, client-bundle, qm-pacgate, handbooks)')
$r.Add('  |    |- pacgate-adapters\  scope-assets\  patches\  plans\')
$r.Add('  |    |- nginx\  auth-gate\  scripts\  docs\')
$r.Add('  |    |- pacgate-ai-assets\   (or assets\, per the keep-one decision)')
$r.Add('  |- deer-flow\        (submodule, unchanged)')
$r.Add('  |- runtime\          (inventory + tooling)')
$r.Add('  |- docs\             (specs, plans)')
$r.Add('  |- AGENTS.md  README.md')
$r.Add('')

$r.Add('=== What this means operationally ===')
$r.Add('')
$r.Add('  The bind mounts change from:')
$r.Add('      C:\pacgate-ai-pr\deploy\client-bundle\...')
$r.Add('  to:')
$r.Add('      C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\...')
$r.Add('')
$r.Add('  So there is exactly ONE path substitution to make in the compose/scripts,')
$r.Add('  and the stack must be recreated (bind mounts resolve at container start).')

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"