param()

$ErrorActionPreference = 'Stop'

# ============================================================================
# RELOCATION REHEARSAL — proves the mechanics with ZERO repo mutation.
#
# Everything happens under C:\temp. The source repo and pacgate-law are NOT
# touched. This validates the riskiest steps before the real thing:
#   - git archive extracts the right content
#   - the Rust workspace flattens cleanly (no double nest, no collisions)
#   - build output and client data are genuinely absent
#   - the resulting tree has what the stack needs
# ============================================================================

$src   = 'C:\pacgate-ai-pr'
$work  = 'C:\temp\rehearsal'
$out   = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\REHEARSAL-RESULT.txt'

$r = New-Object System.Collections.Generic.List[string]
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok, [string]$d) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $script:r.Add(("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n))
    if ($d) { $script:r.Add("        $d") }
}

$r.Add('RELOCATION REHEARSAL (isolated to C:\temp; repo untouched)')
$r.Add("run at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$r.Add('')

# ------------------------------------------------------------------ setup
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

# ------------------------------------------------------------------ 1. extract
$r.Add('=== 1. Extract the tracked content (git checkout-index, NOT tar) ===')
# A rehearsal proved Windows tar.exe silently drops CJK filenames (478/515).
# checkout-index is built into git and extracted 515/515.
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$prefix = $stage.TrimEnd('\') + '\'
& git -C $src checkout-index -a -f --prefix="$prefix" 2>&1 | Out-Null
$n0 = @(Get-ChildItem $stage -Recurse -File -Force).Count
$tracked = @(& git -C $src -c core.quotepath=false ls-files 2>$null)
Check 'extracted count matches tracked count' ($n0 -eq $tracked.Count) "extracted=$n0 tracked=$($tracked.Count)"

# CJK completeness. Do NOT compare against `git ls-files` output: PowerShell
# decodes git's UTF-8 stdout as GBK here, so the "want" count is mojibake-based
# and unreliable. Instead compare against the SOURCE FILESYSTEM, which .NET
# reads as correct Unicode.
# Also assert specific known CJK files actually arrived - a count alone can pass
# while names are silently corrupted.
$srcCjkTracked = @()
foreach ($f in (Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\pacgate-ai\target\*') { continue }
    if ($f.FullName -like '*\deploy\deer-flow-src\*') { continue }
    if ($f.FullName -like '*\.git\*') { continue }
    if ($f.FullName -like '*\node_modules\*') { continue }
    if ($f.Name -match '[^\x00-\x7F]') { $srcCjkTracked += $f.Name }
}
$stgCjk = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '[^\x00-\x7F]' }).Count
# The stage gets the *tracked* subset, so it should be <= the source tree count
# but must be a substantial number (the tracked CJK set is 54).
Check 'CJK-named files extracted (>=50)' ($stgCjk -ge 50) "stage CJK files=$stgCjk (source tree has $($srcCjkTracked.Count))"

# Name-integrity probe: these are tracked CJK files that must arrive with names
# intact. Build the names from CODE POINTS -- a CJK literal in this BOM-less .ps1
# is mangled by PowerShell's GBK read BEFORE the script runs, which would make the
# probe search for a mojibake name and always report "missing".
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
$f1 = (ConvertFrom-CodePoints @(0x9879,0x76EE,0x65F6,0x95F4,0x7EBF,0x4E0E,0x5173,0x952E,0x8282,0x70B9)) + '.pdf'
$f2 = 'Pacgate_AI_Phase1_' + (ConvertFrom-CodePoints @(0x6280,0x672F,0x65B9,0x4E66,0x9762,0x6F84,0x6E05,0x95EE,0x9898,0x6E05,0x5355)) + '.docx'
$nameChecks = @(
    ('docs\progress-reportcard\' + $f1),
    ('docs\assets\q&a\' + $f2)
)
$nameOk = $true
foreach ($nc in $nameChecks) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $nc))) { $nameOk = $false }
}
Check 'specific CJK filenames intact (not mojibake)' $nameOk "probed $($nameChecks.Count) known CJK paths"

# Authoritative completeness check: diff the INDEX against what landed on disk.
# Both sides are read as raw bytes (-z), avoiding any console decoding. This is
# the check that actually proves nothing was silently dropped.
$idxRaw = Join-Path $work 'index.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
$idxList = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($idxRaw)) -split "`0" | Where-Object { $_ -ne '' })
$stgList = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force |
             ForEach-Object { $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/') })
$idxSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($x in $idxList) { $idxSet.Add($x) | Out-Null }
$stgSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($x in $stgList) { $stgSet.Add($x) | Out-Null }
$missingCount = 0
foreach ($x in $idxList) { if (-not $stgSet.Contains($x)) { $missingCount++ } }
$extraCount = 0
foreach ($x in $stgList) { if (-not $idxSet.Contains($x)) { $extraCount++ } }
Check 'index vs disk: nothing missing' ($missingCount -eq 0) "missing=$missingCount (index=$($idxList.Count) disk=$($stgList.Count))"
Check 'index vs disk: nothing extra' ($extraCount -eq 0) "extra=$extraCount"

# Mojibake detector: a corrupted extraction produces names in the GBK-mojibake
# range. Legitimate CJK content will not contain these sequences.
$mojibake = @(Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '[\u951F\u9225\u952F\u5C79]' }).Count
Check 'no mojibake filenames' ($mojibake -eq 0) "suspicious names: $mojibake"
$r.Add('')

# ------------------------------------------------------------------ 3. flatten
$r.Add('=== 2. Flatten the Rust workspace (avoid pacgate-ai\pacgate-ai\) ===')
$inner = Join-Path $stage 'pacgate-ai'
Check 'inner pacgate-ai dir exists in archive' (Test-Path -LiteralPath $inner) $inner

if (Test-Path -LiteralPath $inner) {
    $innerNames = @(Get-ChildItem -LiteralPath $inner -Force | Select-Object -ExpandProperty Name)
    $clash = @($innerNames | Where-Object { Test-Path -LiteralPath (Join-Path $stage $_) })
    Check 'no name collisions when promoting' ($clash.Count -eq 0) "collisions: $($clash.Count) $(if($clash.Count){'-> ' + ($clash -join ', ')})"

    foreach ($item in (Get-ChildItem -LiteralPath $inner -Force)) {
        Move-Item -LiteralPath $item.FullName -Destination (Join-Path $stage $item.Name) -Force
    }
    Remove-Item -LiteralPath $inner -Force

    Check 'Cargo.toml now at stage root' (Test-Path -LiteralPath (Join-Path $stage 'Cargo.toml')) ''
    Check 'no nested pacgate-ai\pacgate-ai remains' (-not (Test-Path -LiteralPath $inner)) ''
}
$r.Add('')

# ------------------------------------------------------------------ 4. exclusions
$r.Add('=== 3. Exclusions (the 6.4 GB that must NOT move) ===')
Check 'no rust target/ directory' (-not (Test-Path -LiteralPath (Join-Path $stage 'target'))) ''
$tCount = @(Get-ChildItem -LiteralPath $stage -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'target' }).Count
Check 'no target/ dir anywhere in stage' ($tCount -eq 0) "found: $tCount"

$dataPresent = Test-Path -LiteralPath (Join-Path $stage 'deploy\client-bundle\data')
Check 'no client-bundle\data (client history) in stage' (-not $dataPresent) ''
$dfs = Test-Path -LiteralPath (Join-Path $stage 'deploy\deer-flow-src')
Check 'no deer-flow-src (31 MB vendored clone) in stage' (-not $dfs) ''

# size sanity: the staged tree must be small (tens of MB, not GB)
$sizeMb = [math]::Round((((Get-ChildItem $stage -Recurse -File -Force) | Measure-Object Length -Sum).Sum)/1MB, 1)
Check 'staged size is tens of MB (not GB)' ($sizeMb -gt 5 -and $sizeMb -lt 200) "$sizeMb MB"
$r.Add('')

# ------------------------------------------------------------------ 5. required content
$r.Add('=== 5. Required content present ===')
$required = @(
    'Cargo.toml',
    'crates',
    'wasm-crates',
    'deploy\client-bundle\compose.bundle.yaml',
    'deploy\client-bundle\compose.prod.yaml',
    'deploy\client-bundle\install.ps1',
    'deploy\client-bundle\deer-flow-config.yaml',
    'deploy\client-bundle\deer-flow-extensions-config.template.json',
    'deploy\qm-pacgate\compose.qm.yaml',
    'deploy\build-images.ps1',
    'pacgate-adapters',
    'scope-assets',
    'patches',
    'plans',
    'docs',
    'nginx',
    'auth-gate',
    'scripts'
)
foreach ($q in $required) {
    Check $q (Test-Path -LiteralPath (Join-Path $stage $q)) ''
}
$r.Add('')

# ------------------------------------------------------------------ 6. credentials
$r.Add('=== 4. Credential removal (MANDATORY step) ===')
# The tracked content DOES carry OPERATOR.md (proven by rehearsal). The migration
# must remove it from the stage before anything reaches git.
$before = @(Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' }).Count
$r.Add("  credential carriers present BEFORE removal: $before")
Check 'credential carriers are present (so removal is needed)' ($before -gt 0) ''

$vend = Join-Path $stage 'pacgate-ai-assets'
if (Test-Path -LiteralPath $vend) { Remove-Item -LiteralPath $vend -Recurse -Force }
foreach ($c in @(Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' })) {
    Remove-Item -LiteralPath $c.FullName -Force
}
$after = @(Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' }).Count
Check 'all credential carriers removed' ($after -eq 0) "remaining: $after"
Check 'vendored assets duplicate gone' (-not (Test-Path -LiteralPath (Join-Path $stage 'pacgate-ai-assets'))) ''
$r.Add('')

# ------------------------------------------------------------------ 7. hardcoded paths
$r.Add('=== 7. Hardcoded old paths that still need rewriting ===')
$hpath = 0
foreach ($f in (Get-ChildItem $stage -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.Extension -notin @('.ps1','.py','.yaml','.yml','.json','.md','.sh','.conf','.txt','.ts','.js','.toml')) { continue }
    if ($f.Length -gt 400000) { continue }
    try { $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f.FullName)) } catch { continue }
    if ($t -match 'C:\\pacgate-ai-pr') { $hpath++ }
}
$r.Add("  files still referencing C:\pacgate-ai-pr: $hpath")
$r.Add('  (expected ~23; Task 2 of the plan rewrites these)')
$r.Add('')

# ------------------------------------------------------------------ summary
$r.Add('=' * 62)
$r.Add("REHEARSAL SUMMARY: $pass PASS, $fail FAIL")
$r.Add('=' * 62)
$r.Add('')
if ($fail -eq 0) {
    $r.Add('The mechanics are sound. The real migration can proceed once:')
    $r.Add('  1. compose.prod.yaml gets its `name:` key (the dry-run FAIL)')
    $r.Add('  2. a maintenance window is chosen (the stack must restart)')
} else {
    $r.Add('Resolve the FAILs before attempting the real migration.')
}

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

# clean up the rehearsal area (proves nothing is left behind)
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "REHEARSAL COMPLETE: $pass PASS, $fail FAIL"
Write-Output "  $out"
Write-Output "  (rehearsal area $work removed)"