$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$cb   = Join-Path $repo 'pacgate-ai\deploy\client-bundle'
$out  = Join-Path $repo 'runtime\relocate\COMPOSE-NAME-VERIFY.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'COMPOSE PROJECT-NAME VERIFICATION'
A ('=' * 62)
A ''
A 'Both compose files must resolve to the SAME project name, otherwise they'
A 'prefix named volumes differently and one of them attaches to an empty DB.'

foreach ($f in @('compose.bundle.yaml', 'compose.prod.yaml')) {
    $p = Join-Path $cb $f
    A "`n=== $f ==="
    if (-not (Test-Path $p)) { A '  MISSING'; continue }

    # declared name
    $decl = @(Select-String -Path $p -Pattern '^name:' | ForEach-Object { $_.Line.Trim() })
    A ("  declared : {0}" -f $(if ($decl) { $decl -join ', ' } else { '(none)' }))

    # what compose actually resolves (authoritative)
    Push-Location $cb
    $resolved = (& docker compose -f $f config 2>$null | Select-String -Pattern '^name:' | Select-Object -First 1)
    Pop-Location
    A ("  resolved : {0}" -f $(if ($resolved) { $resolved.Line.Trim() } else { '(could not resolve)' }))
}

A "`n=== Live stack (what is actually running) ==="
# NOTE: do NOT use $l as a loop variable here -- PowerShell is case-insensitive,
# so $l IS $L and the loop would overwrite the results list.
$lbl = docker inspect pacgate-db 2>$null | Select-String -Pattern 'com.docker.compose.project"|config_files' |
       ForEach-Object { $_.Line.Trim() }
foreach ($line in $lbl) { A ("  " + $line) }

A "`n=== Volumes present ==="
docker volume ls --format '{{.Name}}' 2>$null | Select-String 'pacgate-db-data' | ForEach-Object { A ("  " + $_.Line) }

A "`n=== VERDICT ==="
# `docker compose config` needs the .env present; fall back to reading the
# declared key directly if it cannot resolve.
function Get-ProjectName([string]$file) {
    Push-Location $cb
    try {
        $r = (& docker compose -f $file config 2>$null | Select-String -Pattern '^name:' | Select-Object -First 1)
        if ($r) { return ($r.Line -replace '^name:\s*', '').Trim() }
    } finally { Pop-Location }
    $d = @(Select-String -Path (Join-Path $cb $file) -Pattern '^name:' | Select-Object -First 1)
    if ($d) { return ($d.Line -replace '^name:\s*', '').Trim() }
    return ''
}
$bn = Get-ProjectName 'compose.bundle.yaml'
$pn = Get-ProjectName 'compose.prod.yaml'
A ("  bundle -> '{0}'" -f $bn)
A ("  prod   -> '{0}'" -f $pn)
if ($bn -eq $pn -and $bn -ne '') { A '  MATCH -- both resolve to the same project. Safe.' }
else { A '  MISMATCH -- fix before starting the stack.' }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
