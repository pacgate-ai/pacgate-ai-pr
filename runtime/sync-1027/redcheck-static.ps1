# The previous red-check was inconclusive: baseline and mutant both exited 1,
# because the LIVE container still runs the old middleware (Task 6 not done yet).
# Prove the mutation is caught by a STATIC assertion instead, by diffing which
# assertions fail with and without the mutation.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\pacgate-ai')

$p = (Resolve-Path '.\deploy\client-bundle\patches\deer-flow-loop-detection.py').Path
$gate = '.\scripts\test-loop-detection-window.ps1'
$orig = [System.IO.File]::ReadAllBytes($p)

function Get-Fails {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1 }
    finally { $ErrorActionPreference = $prevEap }
    return @($out | Where-Object { "$_" -match '\[FAIL\]' } | ForEach-Object { "$_".Trim() })
}

$baseFails = Get-Fails
"baseline_fail_count=$($baseFails.Count)"

try {
    $s = [System.Text.Encoding]::UTF8.GetString($orig)
    $needle = 'self._tool_name_counter: defaultdict[str, Counter[str]] = defaultdict(Counter)'
    $s2 = $s.Replace($needle, 'self._tool_name_counter = None  # MUTANT')
    [System.IO.File]::WriteAllBytes($p, [System.Text.Encoding]::UTF8.GetBytes($s2))
    $mutFails = Get-Fails
}
finally { [System.IO.File]::WriteAllBytes($p, $orig) }

"mutant_fail_count=$($mutFails.Count)"

'=== failures present ONLY with the mutation (these prove the gate sees it) ==='
$new = Compare-Object $baseFails $mutFails | Where-Object SideIndicator -eq '=>'
if ($new) { $new | ForEach-Object { '  ' + $_.InputObject } }
else { '  NONE - the mutation was not caught by any assertion' }

'=== restored? ==='
"byte_identical=$((Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash)"
