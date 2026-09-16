$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$sub  = Join-Path $repo 'pacgate-ai'
$out  = Join-Path $repo 'runtime\relocate\ASSETS-CREDENTIAL-RISK.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'ASSETS CREDENTIAL RISK CHECK'
A ('=' * 62)
A ''
A 'Question: Step 4 moves the submodule dir to pacgate-ai-assets\ and then runs'
A '          `git add -A pacgate-ai-assets`. Do the repo .gitignore credential'
A '          rules still match at that NEW path?'
A '          (Rules are anchored to pacgate-ai/assets/... )'

A "`n=== A. Credential-like files present on disk under pacgate-ai\ ==="
# ASCII-safe globs only (a CJK literal in a BOM-less .ps1 is corrupted by the
# GBK read before execution -- learned the hard way this session).
foreach ($p in @('OPERATOR.md', '*MCP*.md', '*V2.docx', '*remote-handbook*', '*credential*')) {
    $hits = @(Get-ChildItem $sub -Recurse -Force -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like $p })
    A ("  {0,-18} -> {1} hit(s)" -f $p, $hits.Count)
    foreach ($h in $hits) { A ("        " + $h.FullName.Substring($sub.Length)) }
}

A "`n=== B. Ignore status at CURRENT path (asked from inside the submodule) ==="
$cur = 'assets/pacgate-ai-remote-handbook/OPERATOR.md'
$r1 = & git -C $sub check-ignore --no-index -v $cur 2>&1
if ($r1) { A ("  IGNORED     : " + ($r1 -join ' ; ')) }
else     { A ("  NOT IGNORED : $cur") }

A "`n=== C. Ignore status at FUTURE path (asked from the outer repo) ==="
$fut = 'pacgate-ai-assets/assets/pacgate-ai-remote-handbook/OPERATOR.md'
$r2 = & git -C $repo check-ignore --no-index -v $fut 2>&1
if ($r2) { A ("  IGNORED     : " + ($r2 -join ' ; ')) }
else     { A ("  NOT IGNORED : $fut") }

A "`n=== D. Control (proves check-ignore is working at all) ==="
$ctl = 'pacgate-ai-assets/assets/definitely-a-normal-file.txt'
$r3 = & git -C $repo check-ignore --no-index -v $ctl 2>&1
if ($r3) { A ("  control unexpectedly ignored: " + ($r3 -join ' ; ')) }
else     { A "  control NOT ignored (correct - proves the test can distinguish) OK" }

A "`n=== VERDICT ==="
if ($r1 -and -not $r2) {
    A '  RISK CONFIRMED: the file is ignored at the current path but NOT at the'
    A '  future path. `git add -A pacgate-ai-assets` would stage a live credential'
    A '  file. The plan MUST add pacgate-ai-assets/ patterns before Step 4.'
} elseif (-not $r1 -and -not $r2) {
    A '  RISK: not ignored at either path. Investigate.'
} else {
    A '  No risk: ignored at the future path too.'
}

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
