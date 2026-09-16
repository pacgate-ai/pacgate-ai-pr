$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\PHASE1-VERIFY.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'PHASE 1 VERIFICATION (post-commit)'
A ('=' * 62)

A "`n=== Commits ==="
& git -C $repo log --oneline | ForEach-Object { A ("  " + $_) }

# --- file count in the commit ----------------------------------------------
$raw = Join-Path $env:TEMP 'pg-tree.raw'
& cmd /c "git -c core.quotepath=false -C `"$repo`" ls-tree -r --name-only HEAD > `"$raw`""
$tree = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($raw)) -split "`r?`n" |
          Where-Object { $_ -ne '' })
$inPA = @($tree | Where-Object { $_ -like 'pacgate-ai/*' })
A ("`n=== Tracked files in HEAD ===")
A ("  total            : {0}" -f $tree.Count)
A ("  under pacgate-ai/: {0}" -f $inPA.Count)

# --- CJK names survived the commit? ----------------------------------------
$nonAscii = @($inPA | Where-Object { $_ -match '[^\x00-\x7F]' })
A ("`n=== Non-ASCII names committed: {0} ===" -f $nonAscii.Count)
foreach ($n in ($nonAscii | Select-Object -First 16)) { A ("  " + $n) }

A "`n=== Spot-check the CJK files named in the plan ==="
foreach ($probe in @('pacgate-ai/docs/progress-reportcard/',
                     'pacgate-ai/docs/assets/q&a/',
                     'pacgate-ai/scope-assets/')) {
    $h = @($inPA | Where-Object { $_ -like "$probe*" })
    A ("  {0,-48} {1} file(s)" -f $probe, $h.Count)
}

# --- exclusions actually excluded? -----------------------------------------
A "`n=== Exclusions confirmed ==="
foreach ($pat in @('pacgate-ai/target/', 'pacgate-ai/deploy/client-bundle/data/',
                   'pacgate-ai-assets/', 'deer-flow/', 'OPERATOR.md', 'remote-handbook')) {
    $n = @($tree | Where-Object { $_ -like "*$pat*" }).Count
    A ("  {0,-44} {1}  {2}" -f $pat, $n, $(if ($n -eq 0) { 'OK' } else { '!!! LEAKED' }))
}

# --- working tree clean? ---------------------------------------------------
A "`n=== Working tree status ==="
$st = @(& git -C $repo status --porcelain)
A ("  entries: {0}" -f $st.Count)
foreach ($s in ($st | Select-Object -First 15)) { A ("    " + $s) }

# --- source untouched? -----------------------------------------------------
A "`n=== Source repo (rollback) intact ==="
$src = 'C:\pacgate-ai-pr'
A ("  exists : {0}" -f (Test-Path $src))
A ("  HEAD   : {0}" -f ((& git -C $src rev-parse --short HEAD 2>$null) -join ''))
A ("  tracked: {0}" -f (@(& git -C $src ls-files).Count))
A ("  dirs   : deploy={0} pacgate-ai={1}" -f (Test-Path "$src\deploy"), (Test-Path "$src\pacgate-ai\crates"))

# --- containers still up? --------------------------------------------------
A "`n=== Running stack (must be untouched) ==="
$ps = @(docker ps -q)
A ("  containers running: {0}" -f $ps.Count)

Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
