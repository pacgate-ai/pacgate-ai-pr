$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\FLATTEN-BREAKAGE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'FLATTEN-INDUCED PATH BREAKAGE SCAN'
A ('=' * 74)
A ''
A 'The import FLATTENED the Rust workspace: source `pacgate-ai/X` -> monorepo'
A '`pacgate-ai/X`. So any script/config that referenced the OLD internal layout'
A '(`<root>/pacgate-ai/...`) now points at a non-existent double-nested path.'
A ''
A 'Scan for references to the inner `pacgate-ai/` directory from inside the'
A 'platform, then test whether each target actually exists.'

# Patterns that would indicate a reference to the old inner directory.
$patterns = @(
    'pacgate-ai/Dockerfile',
    'pacgate-ai/Cargo.toml',
    'pacgate-ai/Cargo.lock',
    'pacgate-ai/crates',
    'pacgate-ai/wasm-crates',
    'pacgate-ai/migrations',
    'pacgate-ai/workflows',
    'pacgate-ai\Dockerfile',
    'pacgate-ai\Cargo.toml',
    'pacgate-ai\crates'
)

$hits = New-Object System.Collections.Generic.List[object]
foreach ($pat in $patterns) {
    $found = @(Get-ChildItem $pa -Recurse -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' -and
                              $_.Extension -match '^\.(ps1|psm1|py|sh|ya?ml|json|toml|md|ts|js|cmd|bat)$' } |
               Select-String -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue)
    foreach ($h in $found) {
        $hits.Add([pscustomobject]@{ Pattern = $pat; Path = $h.Path; Line = $h.LineNumber; Text = $h.Line.Trim() })
    }
}

A ("`n=== References to the old inner layout: {0} ===" -f $hits.Count)
$byFile = $hits | Group-Object Path
foreach ($g in $byFile) {
    A ("`n  {0}" -f $g.Name.Substring($pa.Length))
    foreach ($h in $g.Group) {
        $t = $h.Text; if ($t.Length -gt 120) { $t = $t.Substring(0,120) + ' ...' }
        A ("    L{0,-5} [{1}] {2}" -f $h.Line, $h.Pattern, $t)
    }
}

# ---- which of these are FUNCTIONAL (would break a build/run)? --------------
A "`n=== Classification ==="
$functional = @($hits | Where-Object { $_.Path -match '\.(ps1|psm1|py|sh|ya?ml|json|toml|cmd|bat)$' })
$docs       = @($hits | Where-Object { $_.Path -match '\.md$' })
A ("  functional (scripts/configs) : {0}" -f $functional.Count)
A ("  documentation                : {0}" -f $docs.Count)

A "`n=== Do the referenced targets exist? ==="
foreach ($t in @('Dockerfile','Cargo.toml','Cargo.lock','crates','wasm-crates','migrations','workflows')) {
    $p = Join-Path $pa $t
    A ("  {0,-16} at platform root: {1}" -f $t, $(if (Test-Path $p) { 'EXISTS' } else { 'MISSING' }))
}

A "`n=== VERDICT ==="
if ($functional.Count -eq 0) {
    A '  No functional breakage found.'
} else {
    A ("  {0} functional file(s) reference the old inner layout - each needs review." -f (@($functional.Path | Sort-Object -Unique).Count))
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"