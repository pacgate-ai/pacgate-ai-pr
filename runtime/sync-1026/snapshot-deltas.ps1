# Enumerate every pacgate-ai/ path that differs from upstream 337fb9d, then copy
# each out as raw bytes and prove the copies are byte-identical.
#
# The subtree swap reverts ALL local deltas (AGENTS.md warns about exactly this),
# so this snapshot is the only thing standing between the swap and silent loss.
#
# ENCODING NOTE (this script failed once on it - see below):
# PowerShell 5.1 decodes a native command's stdout using the CONSOLE CODEPAGE
# (GBK on this host). `git ls-tree` emits UTF-8, so every CJK path came back as
# mojibake, Test-Path failed on all 56 of them, and they were reported MISSING
# with no explanation. Two defences, both required:
#   1. `-z`  : NUL-separated, and git does NOT quote/escape paths under -z
#   2. capture stdout to a FILE and read it as UTF-8 bytes ourselves, so the
#      console codepage never enters the pipeline
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$git = 'C:\Program Files\Git\cmd\git.exe'
$repo = (Get-Location).Path
$dst = Join-Path $repo 'runtime\sync-1026\local-preserve'
$listFile = Join-Path $repo 'runtime\sync-1026\local-delta-list.txt'

New-Item -ItemType Directory -Force -Path $dst | Out-Null

function Get-GitNames([string]$rev, [string]$pathspec) {
    # CRITICAL: PowerShell 5.1's `>` redirection writes UTF-16LE, which would
    # destroy a NUL-separated byte stream (this produced delta_count=0 on the
    # first attempt). Use Start-Process so the bytes land unmodified.
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
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    return ($text -split "`0" | Where-Object { $_ -ne '' })
}

$tracked = Get-GitNames 'HEAD' 'pacgate-ai'

$rows = New-Object System.Collections.Generic.List[string]
foreach ($p in $tracked) {
    if (-not $p.StartsWith('pacgate-ai/')) { continue }
    $sub = $p.Substring('pacgate-ai/'.Length)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = & $git cat-file -e ("337fb9d:{0}" -f $sub) 2>&1 }
    finally { $ErrorActionPreference = $prevEap }

    if ($LASTEXITCODE -ne 0) { $rows.Add(("{0}`tLOCAL_ONLY" -f $p)); continue }
    $l = (& $git rev-parse ("HEAD:{0}" -f $p)).Trim()
    $u = (& $git rev-parse ("337fb9d:{0}" -f $sub)).Trim()
    if ($l -ne $u) { $rows.Add(("{0}`tDIFFERS" -f $p)) }
}

[System.IO.File]::WriteAllText($listFile, (($rows -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
"delta_count=$($rows.Count)"

'--- copying as raw bytes ---'
$missing = 0
foreach ($row in $rows) {
    $p = ($row -split "`t")[0]
    $src = Join-Path $repo ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { "STILL_MISSING $p"; $missing++; continue }
    $target = Join-Path $dst ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    # Byte copy: Get-Content/Set-Content would transcode UTF-8 CJK to GBK.
    [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($src))
}

'--- verifying byte identity ---'
$bad = 0
foreach ($row in $rows) {
    $p = ($row -split "`t")[0]
    $src = Join-Path $repo ($p -replace '/', '\')
    $cpy = Join-Path $dst ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $cpy)) { "NOCOPY $p"; $bad++; continue }
    $a = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash
    $b = (Get-FileHash -Algorithm SHA256 -LiteralPath $cpy).Hash
    if ($a -ne $b) { "MISMATCH $p"; $bad++ }
}
"missing=$missing byte_mismatches=$bad"
