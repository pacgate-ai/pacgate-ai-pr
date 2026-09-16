$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\credential-scan-results.txt'

# ============================================================================
# !! THIS SCRIPT IS NOT AUTHORITATIVE FOR CJK FILENAMES !!
#
# It compares paths as PowerShell STRINGS. On Chinese Windows, PowerShell 5.1
# decodes git's UTF-8 output using the GBK console codepage, so any CJK filename
# becomes mojibake and string comparison silently fails. This produced a FALSE
# NEGATIVE: 3 of the 4 credential files are Chinese-named and were reported as
# "not tracked" when they ARE tracked and ARE publicly readable.
#
# It remains useful for the ASCII-named OPERATOR.md and for the ASCII marker
# search, and it is retained because the incident report cites its output.
#
# FOR ANY CJK PATH, USE INSTEAD:
#     AUTHORITATIVE-credential-check.ps1   (byte-level, codepage-proof)
# ============================================================================

$repos = @(
    @{ Name = 'pacgate-ai-pr';    Path = 'C:\pacgate-ai-pr' },
    @{ Name = 'deer-flow';        Path = 'c:\Users\pacga\github-pr\pacgate-law\deer-flow' },
    @{ Name = 'pacgate-ai (sub)'; Path = 'c:\Users\pacga\github-pr\pacgate-law\pacgate-ai' }
)

$lines = New-Object System.Collections.Generic.List[string]
foreach ($r in $repos) {
    $lines.Add("================ $($r.Name) ================")
    $p = $r.Path

    $headOk = $false
    & git -C $p cat-file -e 'HEAD:assets/pacgate-ai-remote-handbook/OPERATOR.md' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $headOk = $true }
    $lines.Add("  OPERATOR.md in HEAD (assets path): $headOk")

    $m1 = @(& git -C $p log --all --oneline -S 'Real PacGate GitHub credentials' 2>$null)
    $lines.Add("  history hits for credential marker: $($m1.Count)")
    foreach ($h in $m1) { $lines.Add("      $h") }

    $paths = @(& git -C $p log --all --pretty=format: --name-only --diff-filter=A 2>$null |
               Where-Object { $_ -match 'OPERATOR' } | Sort-Object -Unique)
    $lines.Add("  OPERATOR paths ever added: $($paths.Count)")
    foreach ($pp in $paths) { $lines.Add("      $pp") }

    # Sanity check: prove that -S searching actually functions in this repo.
    $sanity = @(& git -C $p log --all --oneline -S 'pacgate' 2>$null)
    $lines.Add("  SANITY (-S 'pacgate' hits): $($sanity.Count)")
    $lines.Add("")
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
