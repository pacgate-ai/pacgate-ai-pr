$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$new  = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\TASK2-HITS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'TASK 2 -- every absolute-path reference in the NEW copy'
A ('=' * 62)
A ''
A 'NOTE: the first scan reported 0 because it searched for a single-quoted'
A "      'C:\\pacgate-ai-pr' -- in a single-quoted PowerShell string that is a"
A '      LITERAL two backslashes, which does not occur in the files. The real'
A '      pattern is a single backslash.'

$hits = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' } |
          Select-String -Pattern 'C:\pacgate-ai-pr' -SimpleMatch -ErrorAction SilentlyContinue)

A "`n=== absolute-path hits: $($hits.Count) ==="

$byFile = $hits | Group-Object Path | Sort-Object Count -Descending
foreach ($g in $byFile) {
    $rel = $g.Name.Substring($new.Length)
    A ("`n[{0,3}] {1}" -f $g.Count, $rel)
    foreach ($h in $g.Group) {
        $t = $h.Line.Trim()
        if ($t.Length -gt 130) { $t = $t.Substring(0,130) + ' ...' }
        A ("      L{0,-5} {1}" -f $h.LineNumber, $t)
    }
}

# Classify for targeting
A "`n=== Classification of files ==="
foreach ($g in $byFile) {
    $rel = $g.Name.Substring($new.Length)
    $c = switch -Regex ($rel) {
        '\\compose\.[a-z0-9-]*\.ya?ml$' { 'COMPOSE' }
        '\.ps1$'                        { 'PS1' }
        '\.ya?ml$'                      { 'YAML' }
        '\.json$'                       { 'JSON' }
        '\.py$'                         { 'PY' }
        '\.sh$'                         { 'SH' }
        '\.md$'                         { 'MD (likely historical)' }
        '\.rs$'                         { 'RUST' }
        '\.sql$'                        { 'SQL' }
        default                         { 'OTHER' }
    }
    A ("  {0,-22} {1}" -f $c, $rel)
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"
