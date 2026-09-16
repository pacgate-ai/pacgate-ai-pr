param()

$ErrorActionPreference = 'Continue'

# ============================================================================
# Verify whether checkout-index really delivers the two probed CJK paths.
# The rehearsal reported them missing; this isolates whether the problem is the
# extraction method or the test's path assumptions.
# ============================================================================

$src = 'C:\pacgate-ai-pr'
$work = 'C:\temp\probe2'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\PROBE-CJK-PATHS.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('PROBE: are the two CJK test paths actually extracted?')
$r.Add('')

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
& git -C $src checkout-index -a -f --prefix=($stage.TrimEnd('\') + '\') 2>&1 | Out-Null

# IMPORTANT: build the CJK probe paths from CODE POINTS.
# PowerShell 5.1 reads a BOM-less .ps1 using the system ANSI codepage (GBK here),
# so a CJK literal written directly in this file is corrupted BEFORE the script
# runs -- the probe then searches for a mojibake name and always reports "missing".
# That is exactly what happened on the first run of this script.
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
# 项目时间线与关键节点.pdf
$f1 = (ConvertFrom-CodePoints @(0x9879,0x76EE,0x65F6,0x95F4,0x7EBF,0x4E0E,0x5173,0x952E,0x8282,0x70B9)) + '.pdf'
# Pacgate_AI_Phase1_技术方书面澄清问题清单.docx (the CJK run only)
$f2 = 'Pacgate_AI_Phase1_' + (ConvertFrom-CodePoints @(0x6280,0x672F,0x65B9,0x4E66,0x9762,0x6F84,0x6E05,0x95EE,0x9898,0x6E05,0x5355)) + '.docx'

$probes = @(
    ('docs\progress-reportcard\' + $f1),
    ('docs\assets\q&a\' + $f2)
)

foreach ($p in $probes) {
    $srcPath = Join-Path $src $p
    $stgPath = Join-Path $stage $p
    $r.Add("path: $p")
    $r.Add("   in source : $(Test-Path -LiteralPath $srcPath)")
    $r.Add("   in stage  : $(Test-Path -LiteralPath $stgPath)")
    $r.Add('')
}

# If not found by that literal path, search the stage for the filename.
$r.Add('--- filesystem search for the leaf names in the stage ---')
foreach ($p in $probes) {
    $leaf = Split-Path $p -Leaf
    $hits = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq $leaf })
    $r.Add("  '$leaf' -> $($hits.Count) hit(s)")
    foreach ($h in $hits) {
        $rel = $h.FullName.Substring($stage.Length).TrimStart('\')
        $r.Add("      actual relative path: $rel")
    }
}

# Also list what IS under progress-reportcard in the stage (compare to source)
$r.Add('')
$r.Add('--- docs\progress-reportcard in the STAGE ---')
$dir = Join-Path $stage 'docs\progress-reportcard'
if (Test-Path -LiteralPath $dir) {
    foreach ($f in (Get-ChildItem -LiteralPath $dir -File -Force)) { $r.Add("    $($f.Name)") }
} else { $r.Add('    (directory missing)') }

$r.Add('')
$r.Add('--- docs\progress-reportcard in the SOURCE ---')
$sdir = Join-Path $src 'docs\progress-reportcard'
if (Test-Path -LiteralPath $sdir) {
    foreach ($f in (Get-ChildItem -LiteralPath $sdir -File -Force)) { $r.Add("    $($f.Name)") }
}

# Mojibake check: is the file there under a CORRUPTED name?
$r.Add('')
$r.Add('--- any mojibake-named files in the stage? ---')
$mj = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '[\u951F\u9225\u952F\u5C79]' })
$r.Add("  count: $($mj.Count)")
foreach ($m in ($mj | Select-Object -First 5)) { $r.Add("    $($m.Name)") }

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "wrote $out"