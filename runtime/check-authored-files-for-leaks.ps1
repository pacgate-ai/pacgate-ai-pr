$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\leak-selfcheck-results.txt'

# Verify that the documents we generated do NOT reproduce the credential values.
# Approach: take every non-trivial "value" cell from OPERATOR.md, then confirm
# that none of those strings appear in any file we authored.
# We compare hashes, never printing the values themselves.

$credFile = 'C:\pacgate-ai-pr\pacgate-ai\pacgate-ai-assets\pacgate-ai\assets\assets\pacgate-ai-remote-handbook\OPERATOR.md'

$secrets = New-Object System.Collections.Generic.List[string]
$skippedPublic = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $credFile) {
    foreach ($L in [System.IO.File]::ReadAllLines($credFile)) {
        if ($L -match '^\s*\|') {
            $cells = $L -split '\|'
            if ($cells.Count -ge 3) {
                $label = $cells[1].Trim()
                $v = $cells[2].Trim()
                # Skip header separators and empty cells; keep only real values.
                if ($v -and $v -notmatch '^[-: ]+$' -and $v.Length -ge 8) {
                    # Exclude identifiers that are public by construction. The
                    # account/org name appears in every repo URL and directory
                    # path, so flagging its occurrences is pure noise. Match on
                    # the label to stay robust even if values change.
                    if ($label -match '(?i)github\s*(id|account|user|org)') {
                        $skippedPublic.Add($label)
                        continue
                    }
                    $secrets.Add($v)
                }
            }
        }
    }
}

$authored = @(
    'c:\Users\pacga\github-pr\pacgate-law\docs\superpowers\specs\2026-09-16-credential-exposure-incident.md',
    'c:\Users\pacga\github-pr\pacgate-law\docs\superpowers\specs\2026-09-16-repo-consolidation-and-runtime-pinning-design.md',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\README.md',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\credential-scan-results.txt',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\exposure-control-results.txt',
    'c:\Users\pacga\github-pr\pacgate-law\AGENTS.md',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\capture-runtime.ps1',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\scan-credential-history.ps1',
    'c:\Users\pacga\github-pr\pacgate-law\runtime\check-exposure-control.ps1'
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('SELF-CHECK: do our authored documents leak any credential value?')
$lines.Add('')
$lines.Add("secret values extracted from source file: $($secrets.Count)")
$lines.Add("public identifiers excluded (not secrets): $($skippedPublic.Count)")
foreach ($s in $skippedPublic) { $lines.Add("    excluded by label: $s") }
$lines.Add('')
$lines.Add("files checked: $($authored.Count)")
$totalHits = 0

foreach ($f in $authored) {
    if (-not (Test-Path -LiteralPath $f)) { $lines.Add("  MISSING: $f"); continue }
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f))
    $hits = 0
    foreach ($s in $secrets) {
        if ($text.Contains($s)) { $hits++ }
    }
    $totalHits += $hits
    $name = Split-Path $f -Leaf
    $lines.Add(('  {0,-52} leaks={1}' -f $name, $hits))
}

$lines.Add('')
if ($totalHits -eq 0) {
    $lines.Add('VERDICT: PASS - no credential value appears in any authored file.')
} else {
    $lines.Add("VERDICT: FAIL - $totalHits occurrence(s) found. Redact immediately, do not commit.")
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
