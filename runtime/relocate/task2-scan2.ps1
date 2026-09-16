$ErrorActionPreference = 'Continue'
$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$new    = Join-Path $repo 'pacgate-ai'
$src    = 'C:\pacgate-ai-pr'
$out    = Join-Path $repo 'runtime\relocate\TASK2-SCAN2.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'TASK 2 -- searching ALL representations of the old path'
A ('=' * 62)
A ''
A 'First pass searched only for the literal `C:\pacgate-ai-pr`. The path can'
A 'appear in several other forms, so search each one.'

$patterns = @(
    'pacgate-ai-pr',            # any mention at all (broadest)
    'pacgate-ai-pr\',           # backslash path
    'pacgate-ai-pr/',           # forward-slash path
    'C:\pacgate-ai-pr',         # absolute backslash
    'C:/pacgate-ai-pr',         # absolute forward-slash
    '/pacgate-ai-pr',           # unix-style
    'PACAGATE_AI_PR',           # env var style
    'pacgate-ai-pr'             # (dedup)
) | Select-Object -Unique

foreach ($scope in @(@{n='NEW copy (pacgate-ai)'; p=$new}, @{n='SOURCE (C:\pacgate-ai-pr)'; p=$src})) {
    A "`n===== SCOPE: $($scope.n) ====="
    foreach ($pat in $patterns) {
        $hits = @(Get-ChildItem $scope.p -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' } |
                  Select-String -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue)
        A ("  {0,-20} -> {1,5} hit(s)" -f $pat, $hits.Count)
    }
}

A "`n===== What the broad 'pacgate-ai-pr' hits actually are (NEW copy) ====="
$broad = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' } |
           Select-String -Pattern 'pacgate-ai-pr' -SimpleMatch -ErrorAction SilentlyContinue)
$byFile = $broad | Group-Object Path | Sort-Object Count -Descending
foreach ($g in $byFile) {
    A ("`n  [{0,3}] {1}" -f $g.Count, $g.Name.Substring($new.Length))
    foreach ($h in ($g.Group | Select-Object -First 6)) {
        $t = $h.Line.Trim()
        if ($t.Length -gt 140) { $t = $t.Substring(0,140) + ' ...' }
        A ("        L{0,-5} {1}" -f $h.LineNumber, $t)
    }
}
A ("`n  files: {0}   total hits: {1}" -f $byFile.Count, $broad.Count)

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
