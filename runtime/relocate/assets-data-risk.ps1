$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$as   = Join-Path $repo 'pacgate-ai-assets'
$out  = Join-Path $repo 'runtime\relocate\ASSETS-DATA-RISK.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'DATA AT RISK IN pacgate-ai-assets (blocks absorbing it)'
A ('=' * 78)
A ''
A 'Recon showed: ahead=3 vs origin, plus 1 untracked file. Absorbing this repo'
A '(deleting its .git) would PERMANENTLY LOSE that work. Investigate before'
A 'deciding anything.'

# ---- 1. the 3 unpushed commits ---------------------------------------------
A "`n=== 1. The 3 commits that exist ONLY on this machine ==="
$br = ((& git -C $as branch --show-current 2>$null) -join '').Trim()
A ("  branch: {0}" -f $br)
$log = @(& git -C $as log --oneline "origin/$br..$br" 2>&1)
foreach ($x in $log) { A ("    " + $x) }

A "`n  --- full messages ---"
foreach ($x in @(& git -C $as log "origin/$br..$br" --format='%h %ad %an%n    %s%n' --date=short 2>&1)) {
    A ("  " + $x)
}

A "`n  --- files touched by those commits ---"
$files = @(& git -C $as diff --name-status "origin/$br..$br" 2>&1)
foreach ($x in ($files | Select-Object -First 30)) { A ("    " + $x) }
A ("  (total changed paths: {0})" -f $files.Count)

# ---- 2. the untracked file -------------------------------------------------
A "`n=== 2. The untracked file (would be lost with .git deletion) ==="
$st = @(& git -C $as status --porcelain 2>&1)
foreach ($x in $st) {
    # unquote git's octal-escaped path
    $p = ($x -replace '^\?\?\s+', '').Trim('"')
    A ("  raw: {0}" -f $x)
    $full = Join-Path $as ($p -replace '/', '\')
    if (Test-Path -LiteralPath $full) {
        $fi = Get-Item -LiteralPath $full
        A ("  size : {0} bytes" -f $fi.Length)
        A ("  mtime: {0}" -f $fi.LastWriteTime)
        $head = ([System.IO.File]::ReadAllLines($full) | Select-Object -First 4) -join ' | '
        if ($head.Length -gt 120) { $head = $head.Substring(0,120) + '...' }
        A ("  head : {0}" -f $head)
    } else {
        A "  (path did not resolve - CJK escaping)"
    }
}

# ---- 3. can we push them? --------------------------------------------------
A "`n=== 3. Can the 3 commits be pushed? (then nothing would be at risk) ==="
A ("  remotes: {0}" -f ((& git -C $as remote 2>$null) -join ', '))
Push-Location $as
$dr = & git push --dry-run origin "${br}:${br}" 2>&1
Pop-Location
foreach ($x in $dr) { A ("    " + $x) }

A "`n=== VERDICT ==="
A '  If the push dry-run succeeds, push first - then absorbing becomes safe.'
A '  If it fails (auth), absorbing MUST NOT proceed: those commits would be'
A '  destroyed with no way to recover them.'
A ''
A '  RECOMMENDATION: leave pacgate-ai-assets as-is (already gitignored in the'
A '  monorepo). It costs nothing to keep and risks losing real work to absorb.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"