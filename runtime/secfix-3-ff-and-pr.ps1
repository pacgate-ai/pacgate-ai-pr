# Step 1c: fast-forward fork/main to the security commit (stops fork's public leak)
# + open PR to upstream. ASCII output only.
$ErrorActionPreference = "Stop"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$fork = "pacgate-ai/pacgate-ai-pr"
$upstream = "JZKK720/pacgate-ai-pr"
$secCommit = "ec17f28088837302078829737c656cc883d0cf22"

# 0. Fork visibility (context for the leak)
$fRepo = Invoke-RestMethod -Uri "$api/repos/$fork" -Headers $h -TimeoutSec 30
Write-Output "fork visibility: private=$($fRepo.private)"

# 1. Fast-forward fork/main -> security commit (its parent IS current fork/main)
$ffBody = @{ sha = $secCommit; force = $false } | ConvertTo-Json
try {
    $r = Invoke-RestMethod -Uri "$api/repos/$fork/git/refs/heads/main" -Method Patch -Headers $h -TimeoutSec 30 -Body $ffBody -ContentType "application/json"
    Write-Output "fork/main now: $($r.object.sha)"
} catch {
    Write-Output "fast-forward FAIL: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    exit 1
}

# 2. Verify fork/main tree has 0 carriers
$fMain = Invoke-RestMethod -Uri "$api/repos/$fork/git/ref/heads/main" -Headers $h -TimeoutSec 30
$fCommit = Invoke-RestMethod -Uri "$api/repos/$fork/git/commits/$($fMain.object.sha)" -Headers $h -TimeoutSec 30
$fTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$($fCommit.tree.sha)`?recursive=1" -Headers $h -TimeoutSec 60
$fOp = @($fTree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "*pacgate-ai-remote-handbook/OPERATOR.md" })
$fMcpDir = @($fTree.tree | Where-Object { $_.type -eq "tree" -and $_.path -like "*MCP*" -and $_.path -like "*pacgate-ai-assets*" })
Write-Output "VERIFY fork/main: OPERATOR=$($fOp.Count) MCP-dir=$($fMcpDir.Count) (expect 0/0)"

# 3. Open PR to upstream (head = fork branch, base = upstream main)
$prBody = @{
    title = "fix(security): remove credential carriers from tracked tree"
    head = "pacgate-ai:security/remove-credential-carriers"
    base = "main"
    body = "Removes 5 tracked files containing live PacGate credentials (incident 2026-09-16):`n`n" +
        "- pacgate-ai-remote-handbook/OPERATOR.md (GitHub account credentials)`n" +
        "- 3 files under the MCP-authorized directory (legal-DB logins + resource inventory docx,`n" +
        "  the docx blob existed at two paths - both removed)`n`n" +
        "Also adds .gitignore rules so they cannot be re-added.`n`n" +
        "**This does NOT purge history.** The credentials remain in prior public commits`n" +
        "and MUST be rotated. This PR only stops the current tree from exposing them.`n`n" +
        "Verified: post-commit tree contains 0 carriers (SHA-based match, codepage-proof).`n`n" +
        "Note: the docx blob a59e30ed was discovered at TWO paths in the tree (5 files total,`n" +
        "not the 4 previously documented)."
} | ConvertTo-Json
$prJson = [System.Text.Encoding]::UTF8.GetBytes($prBody)
try {
    $pr = Invoke-RestMethod -Uri "$api/repos/$upstream/pulls" -Method Post -Headers $h -TimeoutSec 30 -Body $prJson -ContentType "application/json; charset=utf-8"
    Write-Output "PR created: #$($pr.number) $($pr.html_url)"
} catch {
    Write-Output "PR FAIL: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}