# Snapshot every pacgate-ai/ path that differs from the ADOPTED BASE (86a9feb),
# then copy each out as raw bytes and prove the copies are byte-identical.
#
# WHY A NEW SCRIPT RATHER THAN REUSING sync-1026's: that one hardcodes 337fb9d as
# the comparison base. Our adopted base moved to 86a9feb on 2026-10-26, so reusing
# it would classify every 86a9feb change as a "local delta" and we would then
# re-apply upstream's own work on top of itself.
#
# Encoding traps handled (both cost a failed run on 2026-10-26):
#   1. PS 5.1 decodes native stdout as the CONSOLE CODEPAGE (GBK here), so
#      `git ls-tree` UTF-8 CJK paths came back mojibake and Test-Path failed on
#      56 files. Fix: `ls-tree -z` + read the stream as UTF-8 bytes ourselves.
#   2. PS `>` redirection writes UTF-16, which destroys a NUL-separated stream
#      (produced delta_count=0). Fix: Start-Process -RedirectStandardOutput.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$git = 'C:\Program Files\Git\cmd\git.exe'
$repo = (Get-Location).Path
$base = '86a9feb'          # the revision this tree was last adopted to
$dst = Join-Path $repo 'runtime\sync-1027\local-preserve'
$listFile = Join-Path $repo 'runtime\sync-1027\local-delta-list.txt'

New-Item -ItemType Directory -Force -Path $dst | Out-Null

function Get-GitNames([string]$rev, [string]$pathspec) {
    $f = Join-Path $env:TEMP ("names-{0}.bin" -f ([guid]::NewGuid().ToString('N')))
    $p = Start-Process -FilePath $git `
        -ArgumentList @('-c', 'core.quotepath=false', 'ls-tree', '-r', '-z', '--name-only', $rev, '--', $pathspec) `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $f -RedirectStandardError (Join-Path $env:TEMP 'gitnames.err')
    if ($p.ExitCode -ne 0) {
        $err = Get-Content (Join-Path $env:TEMP 'gitnames.err') -Raw -ErrorAction SilentlyContinue
        Remove-Item -Force $f -ErrorAction SilentlyContinue
        throw "ls-tree failed for ${rev}: $err"
    }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    Remove-Item -Force $f -ErrorAction SilentlyContinue
    return ([System.Text.Encoding]::UTF8.GetString($bytes) -split "`0" | Where-Object { $_ -ne '' })
}

$tracked = Get-GitNames 'HEAD' 'pacgate-ai'

$rows = New-Object System.Collections.Generic.List[string]
foreach ($p in $tracked) {
    if (-not $p.StartsWith('pacgate-ai/')) { continue }
    $sub = $p.Substring('pacgate-ai/'.Length)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = & $git cat-file -e ("{0}:{1}" -f $base, $sub) 2>&1 }
    finally { $ErrorActionPreference = $prevEap }

    if ($LASTEXITCODE -ne 0) { $rows.Add(("{0}`tLOCAL_ONLY" -f $p)); continue }
    $l = (& $git rev-parse ("HEAD:{0}" -f $p)).Trim()
    $u = (& $git rev-parse ("{0}:{1}" -f $base, $sub)).Trim()
    if ($l -ne $u) { $rows.Add(("{0}`tDIFFERS" -f $p)) }
}

[System.IO.File]::WriteAllText($listFile, (($rows -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
"base=$base"
"delta_count=$($rows.Count)"

'--- copying as raw bytes ---'
$missing = 0
foreach ($row in $rows) {
    $p = ($row -split "`t")[0]
    $src = Join-Path $repo ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { "STILL_MISSING $p"; $missing++; continue }
    $target = Join-Path $dst ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($src))
}

'--- verifying byte identity ---'
$bad = 0
foreach ($row in $rows) {
    $p = ($row -split "`t")[0]
    $src = Join-Path $repo ($p -replace '/', '\')
    $cpy = Join-Path $dst ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $cpy)) { "NOCOPY $p"; $bad++; continue }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $cpy).Hash) { "MISMATCH $p"; $bad++ }
}
"missing=$missing byte_mismatches=$bad"
