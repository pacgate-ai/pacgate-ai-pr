# The commit a864e7a was created locally in the worktree, so its tree objects
# exist ONLY locally - the remote doesn't have them. The Git Data API path
# requires uploading every changed blob first. Simpler: use the Contents API
# to PUT each of the 5 changed files directly onto fork/main.
$ErrorActionPreference = 'Stop'
$wt = 'C:\Users\pacga\github-pr\pacgate-law\runtime\wt-v0125'
$env:Path += ';C:\Program Files\Git\cmd'

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

# The 5 files changed by the release-prep commit (repo-relative paths).
$files = @(
    'deploy/client-bundle/patches/deer-flow-tool-policy.py',
    'deploy/client-bundle/patches/deer-flow-skill-storage.py',
    'deploy/client-bundle/compose.bundle.yaml',
    'deploy/client-bundle/compose.prod.yaml',
    'deploy/client-bundle/deer-flow-config.yaml'
)

foreach ($f in $files) {
    $localPath = Join-Path $wt ($f -replace '/', '\')
    $contentBytes = [System.IO.File]::ReadAllBytes($localPath)
    $b64 = [Convert]::ToBase64String($contentBytes)

    # Get the existing file's blob SHA (needed for update; new files skip 404).
    $existingSha = $null
    try {
        $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$f`?ref=main" -Headers $hdr -TimeoutSec 20
        $existingSha = $existing.sha
        Write-Output "$f : updating existing (blob $($existingSha.Substring(0,8)))"
    } catch {
        Write-Output "$f : new file"
    }

    $bodyObj = @{
        message = "fix(release): v0.1.25 prep - $([System.IO.Path]::GetFileName($f))"
        content = $b64
        branch  = 'main'
    }
    if ($existingSha) { $bodyObj.sha = $existingSha }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 5))
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$f" -Method Put -Headers $hdr -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 30
        Write-Output "  -> committed $($r.commit.sha.Substring(0,8))"
    } catch {
        Write-Output "  -> FAILED: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
        exit 1
    }
}

# Verify final state.
$v = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main" -Headers $hdr -TimeoutSec 20
Write-Output "VERIFY fork/main = $($v.sha) : $($v.commit.message.Split([char]10)[0])"
