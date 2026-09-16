$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$old  = 'C:\pacgate-ai-pr\deploy\client-bundle'
$new  = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$out  = Join-Path $repo 'runtime\relocate\RUNTIME-STATE-GAP.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RUNTIME STATE GAP -- untracked files the stack needs but git does not carry'
A ('=' * 62)
A ''
A 'Phase 1 imported only git-TRACKED content. The stack also needs per-machine'
A 'runtime state that is gitignored. Compare old vs new for each.'

function Stat($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 'ABSENT' }
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = [math]::Round(($f | Measure-Object Length -Sum).Sum / 1MB, 1)
    return "files=$($f.Count) MB=$mb"
}

$items = @(
    'data',
    'openviking',
    '.env',
    'deer-flow-extensions-config.json',
    'deer-flow-config.yaml',
    'workflows',
    'patches',
    'nginx'
)

A "`n{0,-38} {1,-26} {2}" -f 'ITEM', 'OLD (C:\pacgate-ai-pr)', 'NEW (pacgate-ai)'
A ('-' * 100)
foreach ($i in $items) {
    $o = Stat (Join-Path $old $i)
    $n = Stat (Join-Path $new $i)
    $flag = if ($o -ne 'ABSENT' -and $n -eq 'ABSENT') { '  <-- MISSING AT NEW' } else { '' }
    A ("{0,-38} {1,-26} {2}{3}" -f $i, $o, $n, $flag)
}

A "`n=== qm-pacgate runtime state ==="
$qo = 'C:\pacgate-ai-pr\deploy\qm-pacgate'
$qn = Join-Path $repo 'pacgate-ai\deploy\qm-pacgate'
foreach ($i in @('tasks', 'node_modules', '.env', 'qm.config.jsonc')) {
    $o = Stat (Join-Path $qo $i)
    $n = Stat (Join-Path $qn $i)
    $flag = if ($o -ne 'ABSENT' -and $n -eq 'ABSENT') { '  <-- MISSING AT NEW' } else { '' }
    A ("{0,-38} {1,-26} {2}{3}" -f $i, $o, $n, $flag)
}

A "`n=== Total size that must be copied ==="
$need = @()
foreach ($i in @('data', 'openviking', '.env', 'deer-flow-extensions-config.json')) {
    $p = Join-Path $old $i
    if ((Test-Path $p) -and -not (Test-Path (Join-Path $new $i))) { $need += $i }
}
A ("  items missing at new: {0}" -f ($need -join ', '))
$tot = 0
foreach ($i in $need) {
    $p = Join-Path $old $i
    if (Test-Path $p -PathType Container) {
        $tot += (@(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum
    } elseif (Test-Path $p) { $tot += (Get-Item $p).Length }
}
A ("  total to copy: {0} MB" -f [math]::Round($tot/1MB,1))

A "`n=== Free space ==="
A ("  C: free = {0} GB" -f [math]::Round((Get-PSDrive C).Free/1GB,1))

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
