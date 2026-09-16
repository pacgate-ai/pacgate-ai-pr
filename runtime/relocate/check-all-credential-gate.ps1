$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$sub  = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\ALL-CREDENTIAL-GATE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'CREDENTIAL GATE -- ALL 4 EXPOSED FILES AT THEIR FUTURE PATH'
A ('=' * 62)
A ''
A 'Method: enumerate the real files on disk (so CJK names never appear as'
A '        literals in this script), map each to its future path under'
A '        pacgate-ai-assets\, and ask git whether it would be ignored.'
A '        A control file proves the test can tell the two apart.'

# --- find the 4 known carriers by ASCII-safe patterns -----------------------
$patterns = @('OPERATOR.md', '*.md', '*.docx')
$cand = @(Get-ChildItem $sub -Recurse -Force -File -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -match 'remote-handbook|MCP' })

A "`n=== Carriers found on disk: $($cand.Count) ==="

$fail = 0
$i = 0
foreach ($f in $cand) {
    $i++
    $rel  = $f.FullName.Substring($sub.Length).TrimStart('\').Replace('\', '/')
    $fut  = 'pacgate-ai-assets/' + $rel
    $r    = & git -C $repo check-ignore --no-index -v $fut 2>&1
    $isIgnored = [bool]$r
    if (-not $isIgnored) { $fail++ }

    $tag = if ($isIgnored) { 'IGNORED    ' } else { '!! NOT IGN' }
    A ("  [{0}] {1}" -f $tag, $fut)
    if ($isIgnored) { A ("             rule: " + ($r -join ' ; ')) }
}

# --- control: a harmless file that must NOT be ignored ---------------------
$ctl = 'pacgate-ai-assets/assets/some-ordinary-notes.txt'
$rc  = & git -C $repo check-ignore --no-index -v $ctl 2>&1
$ctlOk = -not [bool]$rc
A ("`n=== Control (must be NOT ignored): {0} ===" -f $(if ($ctlOk) { 'OK' } else { 'BROKEN' }))
if (-not $ctlOk) { $fail++ }

A "`n=== VERDICT ==="
if ($fail -eq 0) {
    A ("  SAFE -- all {0} credential carriers stay ignored after the move to" -f $cand.Count)
    A '  pacgate-ai-assets\, and the control confirms the test discriminates.'
    A '  Step 4 (git add -A pacgate-ai-assets) is safe to run.'
} else {
    A ("  RISK -- {0} carrier(s) would be STAGED by git add. Add anchored" -f $fail)
    A '  pacgate-ai-assets/ ignore rules BEFORE running Step 4.'
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
