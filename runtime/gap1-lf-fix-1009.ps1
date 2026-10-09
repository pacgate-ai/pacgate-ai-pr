# Fix the CRLF contamination: rewrite all 5 files on fork/main with LF endings
# via the Contents API. The worktree files were CRLF (Windows checkout); upstream
# uses LF. Convert locally, then PUT each file again.
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

$files = @(
    'deploy/client-bundle/patches/deer-flow-tool-policy.py',
    'deploy/client-bundle/patches/deer-flow-skill-storage.py',
    'deploy/client-bundle/compose.bundle.yaml',
    'deploy/client-bundle/compose.prod.yaml',
    'deploy/client-bundle/deer-flow-config.yaml'
)

foreach ($f in $files) {
    $localPath = Join-Path $wt ($f -replace '/', '\')
    $raw = [System.IO.File]::ReadAllBytes($localPath)
    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    # Normalize CRLF -> LF (and stray CR)
    $lf = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($lf))

    $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$f`?ref=main" -Headers $hdr -TimeoutSec 20
    $bodyObj = @{
        message = "fix(release): normalize line endings to LF - $([System.IO.Path]::GetFileName($f))"
        content = $b64
        sha     = $existing.sha
        branch  = 'main'
    }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 5))
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$f" -Method Put -Headers $hdr -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 30
        Write-Output "$f -> $($r.commit.sha.Substring(0,8))"
    } catch {
        Write-Output "$f FAILED: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
        exit 1
    }
}

$v = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/main" -Headers $hdr -TimeoutSec 20
Write-Output "VERIFY fork/main = $($v.sha)"
