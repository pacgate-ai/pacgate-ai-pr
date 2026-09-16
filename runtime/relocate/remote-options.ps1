$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$out  = Join-Path $repo 'runtime\relocate\REMOTE-OPTIONS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'REMOTE OPTIONS for the monorepo (the highest-value outstanding gap)'
A ('=' * 78)
A ''
A 'Current state: pacgate-law has NO remote. With a squashed history it is the'
A 'ONLY copy of this content and cannot be reconstructed from pacgate-ai-pr.'
A 'Investigate what could serve as a remote.'

# ---- 1. current remotes ----------------------------------------------------
A "`n=== 1. Current remotes ==="
$r = @(& git -C $repo remote -v 2>$null)
A ("  pacgate-law remotes: {0}" -f $(if ($r.Count) { '' } else { 'NONE' }))
foreach ($x in $r) { A ("    " + $x) }

# ---- 2. what the sibling repos use -----------------------------------------
A "`n=== 2. Remotes on the sibling repos (candidates to mirror) ==="
foreach ($p in @('C:\pacgate-ai-pr', (Join-Path $repo 'deer-flow'), (Join-Path $repo 'pacgate-ai-assets'))) {
    if (-not (Test-Path $p)) { continue }
    A ("`n  --- {0} ---" -f $p)
    $rr = @(& git -C $p remote -v 2>$null)
    if (-not $rr.Count) { A '    (none)' }
    foreach ($x in $rr) { A ("    " + $x) }
}

# ---- 3. credentials available? ---------------------------------------------
A "`n=== 3. Credential availability (names only) ==="
$gh = Get-Command gh -ErrorAction SilentlyContinue
A ("  gh CLI on PATH      : {0}" -f $(if ($gh) { $gh.Source } else { 'no' }))
if ($gh) {
    $st = (& gh auth status 2>&1) -join "`n"
    foreach ($x in @($st -split "`n" | Select-Object -First 8)) { A ("    " + $x) }
}
A ("  GITHUB_TOKEN env    : {0}" -f $(if ($env:GITHUB_TOKEN) { 'SET' } else { 'unset' }))
A ("  GH_TOKEN env        : {0}" -f $(if ($env:GH_TOKEN) { 'SET' } else { 'unset' }))
$cred = Join-Path $env:USERPROFILE '.git-credentials'
A ("  ~/.git-credentials  : {0}" -f $(if (Test-Path $cred) { 'present' } else { 'absent' }))

# ---- 4. network reachability -----------------------------------------------
A "`n=== 4. Network reachability (VPN-dependent) ==="
foreach ($h in @('github.com','ghcr.io')) {
    $t0 = Get-Date
    try {
        $x = Invoke-WebRequest -Uri "https://$h" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        A ("  {0,-14} HTTP {1} in {2}s" -f $h, $x.StatusCode, [math]::Round(((Get-Date)-$t0).TotalSeconds,1))
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code) { A ("  {0,-14} HTTP {1} (reachable)" -f $h, $code) }
        else { A ("  {0,-14} UNREACHABLE: {1}" -f $h, $_.Exception.Message) }
    }
}

# ---- 5. size of what would be pushed ---------------------------------------
A "`n=== 5. What a push would transfer ==="
$raw = Join-Path $env:TEMP 'ro.raw'
& cmd /c "git -c core.quotepath=false -C `"$repo`" ls-files > `"$raw`""
$files = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($raw)) -split "`r?`n" | Where-Object { $_ -ne '' })
A ("  tracked files : {0}" -f $files.Count)
$gitDir = Join-Path $repo '.git'
$mb = [math]::Round((Get-ChildItem $gitDir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
A ("  .git size     : {0} MB  (this is what pushes)" -f $mb)
A ("  commits       : {0}" -f ((& git -C $repo rev-list --all --count 2>$null) -join ''))
Remove-Item $raw -Force -ErrorAction SilentlyContinue

# ---- 6. options ------------------------------------------------------------
A "`n=== 6. Options ==="
A ''
A '  A. Push to a NEW private repo (e.g. pacgate-ai/pacgate-law)'
A '     + clean separation; the monorepo is its own thing'
A '     + no history conflict (squashed history is fine for a new repo)'
A '     - needs the repo created first'
A ''
A '  B. Push to the EXISTING pacgate-ai-pr fork as a new branch'
A '     + no new repo needed'
A '     - mixes two unrelated histories in one repo; confusing'
A '     - the credential files are still in that repo history'
A ''
A '  C. Local bare mirror on another drive'
A '     + works offline, no VPN, instant'
A '     - not off-machine; does not survive disk failure'
A ''
A '  D. Do nothing yet'
A '     - the monorepo remains the single point of failure'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"