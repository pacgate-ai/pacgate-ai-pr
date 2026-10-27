# Task 4 Step 4: prove the FIXED gate is not blind. Break the windowed counter and
# confirm the gate rejects it, then restore byte-identically.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\pacgate-ai')

$p = (Resolve-Path '.\deploy\client-bundle\patches\deer-flow-loop-detection.py').Path
$gate = '.\scripts\test-loop-detection-window.ps1'

$orig = [System.IO.File]::ReadAllBytes($p)
$origHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash

function Run-Gate {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prevEap }
}

$baseline = Run-Gate
"baseline_exit=$baseline  (expected 1: live container still runs the OLD middleware)"

try {
    $s = [System.Text.Encoding]::UTF8.GetString($orig)
    $needle = 'self._tool_name_counter: defaultdict[str, Counter[str]] = defaultdict(Counter)'
    if (-not $s.Contains($needle)) { throw 'mutation anchor not found' }
    $s2 = $s.Replace($needle, 'self._tool_name_counter = None  # MUTANT: counter removed')
    if ($s2 -eq $s) { throw 'mutation did not change the file' }
    [System.IO.File]::WriteAllBytes($p, [System.Text.Encoding]::UTF8.GetBytes($s2))

    $mutant = Run-Gate
    "mutant_exit=$mutant"
    if ($mutant -eq 0) { throw 'BLIND GATE: passed with the counter removed' }
    'OK: gate rejects the mutated patch'
}
finally {
    [System.IO.File]::WriteAllBytes($p, $orig)
}

$restoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
"byte_identical=$($restoredHash -eq $origHash)"
$after = Run-Gate
"after_restore_exit=$after  (must equal baseline $baseline)"
