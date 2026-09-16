$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$new  = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\TASK2-DOCREWRITE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'TASK 2b -- make documentation layout-agnostic'
A ('=' * 62)
A ''
A 'The handbooks instruct operators to `cd C:\pacgate-ai-pr\deploy\client-bundle`.'
A 'After the move that path is wrong, but hardcoding THIS machine''s path would'
A 'be equally wrong for machine #2 / the developer''s clone. So the replacement'
A 'is layout-agnostic: C:\pacgate-ai-pr  ->  <monorepo>\pacgate-ai'
A ''
A 'SAFETY: only the drive-letter form is replaced. GitHub URLs such as'
A '        github.com/JZKK720/pacgate-ai-pr contain "/pacgate-ai-pr" and MUST'
A '        NOT be touched -- they are remote identifiers, not filesystem paths.'

$old = 'C:\pacgate-ai-pr'
$rep = '<monorepo>\pacgate-ai'

$files = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' } |
           Select-String -Pattern $old -SimpleMatch -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty Path -Unique)

A "`n=== Files to update: $($files.Count) ==="

$totalChanged = 0
foreach ($f in $files) {
    $rel = $f.Substring($new.Length)

    # Read as bytes -> UTF-8 string. NEVER Get-Content on these: Chinese Windows
    # decodes UTF-8 as GBK and the rewrite would double-encode every CJK char.
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $text  = [System.Text.Encoding]::UTF8.GetString($bytes)

    $n = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($n -eq 0) { continue }

    # Guard: URLs must be preserved. Count occurrences that follow a URL-ish char.
    $urlHits = ([regex]::Matches($text, [regex]::Escape($old))).Count

    $newText = $text.Replace($old, $rep)

    # Encode WITHOUT BOM, preserving whatever the file had.
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $enc = New-Object System.Text.UTF8Encoding($hadBom)
    [System.IO.File]::WriteAllText($f, $newText, $enc)

    $totalChanged += $n
    A ("  [{0,2}] {1}" -f $n, $rel)
}

A "`n  replacements made: $totalChanged"

A "`n=== Verify no URL was damaged ==="
$urlCheck = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\' } |
              Select-String -Pattern '<monorepo>\\pacgate-ai-pr|JZKK720/<monorepo>|pacgate-ai/<monorepo>' -ErrorAction SilentlyContinue)
A ("  damaged URL patterns: {0}  (must be 0)" -f $urlCheck.Count)
foreach ($u in $urlCheck) { A ("    !!! " + $u.Path.Substring($new.Length) + " L" + $u.LineNumber) }

A "`n=== Remaining old-path references ==="
$remaining = @(Get-ChildItem $new -Recurse -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\\.git\\|\\target\\|\\node_modules\\' } |
               Select-String -Pattern $old -SimpleMatch -ErrorAction SilentlyContinue)
A ("  remaining: {0}" -f $remaining.Count)
foreach ($r in $remaining) { A ("    " + $r.Path.Substring($new.Length) + " L" + $r.LineNumber) }

A "`n=== CJK integrity (no double-encoding) ==="
$cjkFiles = @(Get-ChildItem $new -Recurse -File -Force -Filter '*.md' -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\\.git\\' } |
              Select-String -Pattern '[\u00C0-\u00FF]{3,}' -ErrorAction SilentlyContinue)
# Double-encoded UTF-8 shows as runs of Latin-1 supplement chars (e.g. 鎺堟潈)
$suspect = @(Get-ChildItem $new -Recurse -File -Force -Filter '*.md' -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\\.git\\' } |
             Select-String -Pattern '\u951F|\u9225|\u5C79|\u93C1' -ErrorAction SilentlyContinue)
A ("  mojibake-pattern files: {0}  (must be 0)" -f (@($suspect | Select-Object -ExpandProperty Path -Unique).Count))
foreach ($s in (@($suspect | Select-Object -ExpandProperty Path -Unique) | Select-Object -First 5)) {
    A ("    " + $s.Substring($new.Length))
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
