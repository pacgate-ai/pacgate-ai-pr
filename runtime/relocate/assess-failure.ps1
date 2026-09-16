$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\POST-FAILURE-ASSESS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'POST-FAILURE ASSESSMENT (Step 4 Move-Item permission error)'
A ('=' * 62)
A ''
A 'The move of pacgate-ai -> pacgate-ai-assets failed on pacgate-ai\.git.'
A 'Move-Item can fall back to copy-then-delete, so a PARTIAL move is possible.'
A 'Determine exactly what state we are in before attempting recovery.'
A ''

function Stat($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 'ABSENT' }
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
    return "files=$($f.Count) MB=$mb"
}

A '=== 1. Target locations ==='
foreach ($p in @('pacgate-ai', 'pacgate-ai-assets', 'pacgate-ai\assets', 'pacgate-ai\pacgate-ai',
                 'pacgate-ai\.git', 'pacgate-ai-assets\.git', 'pacgate-ai-assets\assets')) {
    A ("  {0,-32} {1}" -f $p, (Stat (Join-Path $repo $p)))
}

A "`n=== 2. Top-level of pacgate-ai (still present?) ==="
$pa = Join-Path $repo 'pacgate-ai'
if (Test-Path $pa) {
    Get-ChildItem $pa -Force | ForEach-Object { A ("    " + $_.Name) }
} else { A '  (absent)' }

A "`n=== 3. Stage (source for recovery) intact? ==="
$stage = 'C:\temp\pacgate-stage'
A ("  {0,-32} {1}" -f 'C:\temp\pacgate-stage', (Stat $stage))
if (Test-Path $stage) {
    A '  top-level:'
    Get-ChildItem $stage -Force | ForEach-Object { A ("    " + $_.Name) }
    A ("  Cargo.toml at root : " + (Test-Path (Join-Path $stage 'Cargo.toml')))
    A ("  credential tree    : " + (Test-Path (Join-Path $stage 'pacgate-ai-assets')))
    A ("  OPERATOR.md count  : " + @(Get-ChildItem $stage -Recurse -File -Force |
        Where-Object { $_.Name -eq 'OPERATOR.md' }).Count)
}

A "`n=== 4. SOURCE still intact? (C:\pacgate-ai-pr) ==="
$src = 'C:\pacgate-ai-pr'
A ("  exists : " + (Test-Path $src))
A ("  HEAD   : " + ((& git -C $src rev-parse --short HEAD 2>$null) -join ''))
A ("  tracked: " + (@(& git -C $src ls-files).Count))

A "`n=== 5. pacgate-law index state (did git rm --cached run?) ==="
A '  ls-files --stage:'
& git -C $repo ls-files --stage 2>&1 | ForEach-Object { A ("    " + $_) }
A ("  commits: " + ((& git -C $repo rev-list --all --count 2>$null) -join ''))

A "`n=== 6. Read-only attributes on the nested .git ==="
$gitDir = Join-Path $pa '.git'
if (Test-Path $gitDir) {
    $ro = @(Get-ChildItem $gitDir -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReadOnly })
    A ("  read-only entries under pacgate-ai\.git : {0}" -f $ro.Count)
    if ($ro.Count) { A ("  e.g. " + $ro[0].FullName) }
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
