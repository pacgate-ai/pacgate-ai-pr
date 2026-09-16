$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\gitignore-gap-check.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('GITIGNORE GAP CHECK for the nested layout (pacgate-ai/...)')
$r.Add('=' * 62)
$r.Add('')

# After the move, the platform lives under pacgate-ai/, so every ignore rule that
# previously matched at the ROOT of pacgate-ai-pr must now match under pacgate-ai/.
# If the rules do not follow, `git add -A` would stage 1.9 GB of client data.
$r.Add('Source .gitignore rules (from C:\pacgate-ai-pr):')
$r.Add('')
$srcGi = [System.IO.File]::ReadAllLines('C:\pacgate-ai-pr\.gitignore')
$i = 0
foreach ($l in $srcGi) {
    $i++
    if ([string]::IsNullOrWhiteSpace($l) -or $l.TrimStart().StartsWith('#')) { continue }
    $r.Add("  L{0,-4} {1}" -f $i, $l)
}
$r.Add('')

$r.Add('Critical paths that MUST stay ignored after the move:')
$r.Add('')
$must = @(
    'pacgate-ai/deploy/client-bundle/data/deer-flow/checkpoints.db',
    'pacgate-ai/deploy/client-bundle/data/deer-flow/data/deerflow.db',
    'pacgate-ai/deploy/client-bundle/.env',
    'pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json',
    'pacgate-ai/deploy/client-bundle/openviking/workspace/x',
    'pacgate-ai/deploy/qm-pacgate/tasks/x',
    'pacgate-ai/pacgate-ai/target/x',
    'pacgate-ai/target/x'
)

$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$r.Add('Current state (does the EXISTING repo .gitignore cover these?):')
$r.Add('')
$uncovered = 0
foreach ($p in $must) {
    $res = & git -C $repo check-ignore -v $p 2>$null
    if ($res) {
        $r.Add("  [IGNORED]   $p")
        $r.Add("              -> $res")
    } else {
        $uncovered++
        $r.Add("  [!! NOT IGNORED !!] $p")
    }
}
$r.Add('')
$r.Add("uncovered critical paths: $uncovered")
$r.Add('')

# Also check: would the legacy root-level rules still work if the tree landed at root?
$r.Add('Note: the existing repo .gitignore contains these relevant entries:')
$repoGi = @()
if (Test-Path -LiteralPath "$repo\.gitignore") { $repoGi = [System.IO.File]::ReadAllLines("$repo\.gitignore") }
foreach ($l in $repoGi) { if ($l -match 'data|target|env|OPERATOR|MCP') { $r.Add("      $l") } }

$r.Add('')
$r.Add('CRITICAL EXPLANATION:')
$r.Add('  Git ignore patterns are ANCHORED to the .gitignore location unless they')
$r.Add('  contain a slash in the middle. After nesting the platform under')
$r.Add('  pacgate-ai/, patterns written for the old root may no longer match.')
$r.Add('  => The source .gitignore must be RELOCATED to pacgate-ai/.gitignore')
$r.Add('     (not merged into the repo-root one) for its relative rules to apply.')

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"