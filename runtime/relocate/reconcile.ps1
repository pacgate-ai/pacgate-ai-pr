$ErrorActionPreference = 'Continue'
$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$target = Join-Path $repo 'pacgate-ai'
$out    = Join-Path $repo 'runtime\relocate\RECONCILE.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RECONCILE: credential-probe hits + staged-vs-expected gap'
A ('=' * 62)

# ---------- 1. what did the broad '*MCP*' probe actually hit? ---------------
A "`n=== 1. Credential probe hits (pattern was over-broad: '*MCP*') ==="
$hits = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' -or $_.FullName -like '*MCP*' })
A ("  hits: {0}" -f $hits.Count)
foreach ($h in $hits) {
    $rel = $h.FullName.Substring($target.Length)
    A ("    {0}" -f $rel)
    A ("        size={0} bytes" -f $h.Length)
}
A ''
A '  Classify: a CREDENTIAL file would live under an MCP授权 dir or be a known'
A '  carrier name. A legitimate file merely CONTAINS "MCP" (e.g. mcp.json).'

# ---------- 2. staged vs on-disk reconciliation -----------------------------
A "`n=== 2. On-disk vs staged reconciliation ==="
$idxRaw = Join-Path $env:TEMP 'pg-idx3.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
$idxList = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($idxRaw)) -split "`0" |
             Where-Object { $_ -ne '' })
$expect = @($idxList | Where-Object { $_ -notmatch 'pacgate-ai-assets/' } |
            ForEach-Object { $_ -replace '^pacgate-ai/', '' })
$staged = @(& git -C $repo diff --cached --name-only |
            Where-Object { $_ -match '^pacgate-ai/' } |
            ForEach-Object { $_ -replace '^pacgate-ai/', '' })

$stagedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($s in $staged) { [void]$stagedSet.Add($s) }

$notStaged = @($expect | Where-Object { -not $stagedSet.Contains($_) })
A ("  expected (tracked, minus credential tree) : {0}" -f $expect.Count)
A ("  staged under pacgate-ai/                 : {0}" -f $staged.Count)
A ("  tracked but NOT staged                  : {0}" -f $notStaged.Count)

if ($notStaged.Count) {
    A "`n  --- the gap, with the reason git gives ---"
    foreach ($n in $notStaged) {
        $p = 'pacgate-ai/' + $n
        $r = & git -C $repo check-ignore --no-index -v $p 2>&1
        if ($r) { A ("    IGNORED  {0}" -f $n); A ("             rule: {0}" -f ($r -join ' ; ')) }
        else    { A ("    UNEXPLAINED {0}" -f $n) }
    }
}

# ---------- 3. anything on disk NOT expected (extra) ------------------------
A "`n=== 3. Files on disk that the source index does not list (extras) ==="
$disk = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue |
          ForEach-Object { $_.FullName.Substring($target.Length).TrimStart('\').Replace('\','/') })
$expSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($e in $expect) { [void]$expSet.Add($e) }
$extras = @($disk | Where-Object { -not $expSet.Contains($_) })
A ("  disk files: {0}   extras: {1}" -f $disk.Count, $extras.Count)
foreach ($x in ($extras | Select-Object -First 20)) { A ("    " + $x) }

Remove-Item -LiteralPath $idxRaw -Force -ErrorAction SilentlyContinue

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
