$ErrorActionPreference = 'Continue'
$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$new    = Join-Path $repo 'pacgate-ai'
$out    = Join-Path $repo 'runtime\relocate\TASK2-SCAN.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'TASK 2 -- hardcoded C:\pacgate-ai-pr references in the NEW copy'
A ('=' * 62)
A ''
A 'Scope: files inside pacgate-ai\ only (the old location is left untouched as'
A 'the rollback, and editing it would defeat that purpose).'
A ''
A 'Includes a live pin that MUST NOT be rewritten to a local path: the compose'
A 'files reference the GHCR image name ghcr.io/pacgate-ai/... which happens to'
A 'contain "pacgate-ai" but is a registry reference, not a filesystem path.'

$hits = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\\.git\\' } |
          Select-String -Pattern 'C:\\pacgate-ai-pr' -SimpleMatch -ErrorAction SilentlyContinue)

A "`n=== Matches: $($hits.Count) ==="
$byFile = $hits | Group-Object Path | Sort-Object Count -Descending
foreach ($g in $byFile) {
    $rel = $g.Name.Substring($new.Length)
    A ("`n  [{0,3}] {1}" -f $g.Count, $rel)
    foreach ($h in ($g.Group | Select-Object -First 8)) {
        $line = $h.Line.Trim()
        if ($line.Length -gt 150) { $line = $line.Substring(0,150) + ' ...' }
        A ("        L{0,-5} {1}" -f $h.LineNumber, $line)
    }
}

A "`n=== Classification ==="
$category = @{}
foreach ($h in $hits) {
    $rel = $h.Path.Substring($new.Length)
    $c = switch -Regex ($rel) {
        '\\compose\.'           { 'compose file' }
        '\\\.env'               { 'env file (rendered)' }
        '\.ps1$'                { 'PowerShell script' }
        '\.psm1$'               { 'PowerShell module' }
        '\.py$'                 { 'Python' }
        '\.md$'                 { 'documentation' }
        '\.ya?ml$'              { 'yaml config' }
        '\.json$'               { 'json config' }
        '\.sh$'                 { 'shell script' }
        '\.toml$'               { 'cargo/config' }
        '\.rs$'                 { 'rust source' }
        '\.ts$|\.js$'           { 'web source' }
        default                 { 'other' }
    }
    if (-not $category.ContainsKey($c)) { $category[$c] = 0 }
    $category[$c]++
}
foreach ($k in ($category.Keys | Sort-Object)) { A ("  {0,-20} {1,4}" -f $k, $category[$k]) }

A "`n=== Functional vs documentation ==="
A '  Functional (must be rewritten):  compose, scripts, configs'
A '  Historical (leave as written):    docs/, plans/, handbooks, evidence files'
A '  A blind find-replace across .md would corrupt historical records.'

# Explicitly separate them so the rewrite can be targeted.
$func = @($hits | Where-Object { $_.Path -notmatch '\\docs\\|\\plans\\|\.md$|HANDBOOK|CONTINUE-FROM|_converted' })
$doc  = @($hits | Where-Object { $_.Path -match   '\\docs\\|\\plans\\|\.md$|HANDBOOK|CONTINUE-FROM|_converted' })
A ("`n  functional matches : {0}  (in {1} files)" -f $func.Count, (@($func.Path | Sort-Object -Unique).Count))
A ("  documentation hits : {0}  (in {1} files)" -f $doc.Count,  (@($doc.Path  | Sort-Object -Unique).Count))

A "`n=== Functional files needing a rewrite ==="
foreach ($p in (@($func.Path | Sort-Object -Unique))) { A ("  " + $p.Substring($new.Length)) }

A "`n=== Registry references that must NOT be rewritten ==="
$ghcr = @($hits | Where-Object { $_.Line -match 'ghcr\.io' })
A ("  lines mentioning ghcr.io: {0}" -f $ghcr.Count)

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
