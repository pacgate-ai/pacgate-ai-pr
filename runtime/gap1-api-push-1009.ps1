# API-only push: github.com (git-over-HTTPS) is down but api.github.com works.
# Push the release-prep commit (a864e7a) to fork main via the Git Data API.
# Pattern proven 2026-09-18 (memory: pacgate-topology.md).
# CRITICAL: PS 5.1 Invoke-RestMethod encodes string bodies with GBK -> send UTF-8 BYTES.
$ErrorActionPreference = 'Stop'

# 1. Get the PAT from Windows Credential Manager (never print it).
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = 'git'
$proc.StartInfo.Arguments = 'credential fill'
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardInput = $true
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.RedirectStandardError = $true
$proc.Start() | Out-Null
$proc.StandardInput.WriteLine("protocol=https`nhost=github.com`n")
$proc.StandardInput.Close()
$credOut = $proc.StandardOutput.ReadToEnd()
$proc.WaitForExit(10000)
$pat = ($credOut | Select-String -Pattern 'password=(.+)').Matches[0].Groups[1].Value.Trim()
if (-not $pat) { Write-Output 'NO PAT - ABORT'; exit 1 }
Write-Output "PAT acquired (length $($pat.Length), not printed)"

$hdr = @{
    Authorization = "Bearer $pat"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$repo = 'pacgate-ai/pacgate-ai-pr'

# 2. Read the commit object locally to get tree + parents + message.
$wt = 'C:\Users\pacga\github-pr\pacgate-law\runtime\wt-v0125'
$env:Path += ';C:\Program Files\Git\cmd'
$treeSha = git -C $wt 'rev-parse' 'HEAD^{tree}'
$parentSha = git -C $wt 'rev-parse' 'HEAD^'
$commitSha = git -C $wt 'rev-parse' 'HEAD'
$msg = git -C $wt 'log' -1 --format='%B'
Write-Output "commit: $commitSha tree: $treeSha parent: $parentSha"

# 3. Verify the tree exists on the remote (objects shared via fork network).
try {
    $t = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/trees/$treeSha" -Headers $hdr -TimeoutSec 20
    Write-Output "remote tree OK: $($t.sha) ($($t.tree.Count) entries)"
} catch {
    Write-Output "remote tree MISSING: $($_.Exception.Message)"
    exit 1
}

# 4. Create the commit object on the remote (UTF-8 bytes for the CJK-safe message).
$msgBytes = [System.Text.Encoding]::UTF8.GetBytes(($msg -join "`n"))
$bodyObj = @{
    message    = [System.Text.Encoding]::UTF8.GetString($msgBytes)
    tree       = $treeSha
    parents    = @($parentSha)
} | ConvertTo-Json -Depth 5
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyObj)
try {
    $c = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/commits" -Method Post -Headers $hdr -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 20
    Write-Output "remote commit created: $($c.sha)"
} catch {
    Write-Output "commit create FAILED: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
    exit 1
}

# 5. Fast-forward fork/main to the new commit.
$refBody = @{ sha = $c.sha; force = $false } | ConvertTo-Json
$refBytes = [System.Text.Encoding]::UTF8.GetBytes($refBody)
try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/refs/heads/main" -Method Patch -Headers $hdr -ContentType 'application/json; charset=utf-8' -Body $refBytes -TimeoutSec 20
    Write-Output "fork/main updated: $($r.object.sha)"
} catch {
    Write-Output "ref update FAILED: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
    exit 1
}

# 6. Verify.
$v = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main" -Headers $hdr -TimeoutSec 20
Write-Output "VERIFY fork/main = $($v.sha)"
if ($v.sha -eq $c.sha) { Write-Output 'GAP 1 CLOSED (API path)' } else { Write-Output 'MISMATCH - investigate' }
