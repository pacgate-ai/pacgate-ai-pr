# Security fix via GitHub API only (no git-over-HTTPS needed).
# Creates a branch on the FORK based on upstream/main, removes the 4 credential
# carriers, adds gitignore rules, commits via the Git Data API.
# NEVER prints the token.
$ErrorActionPreference = "Stop"

$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$upstream = "JZKK720/pacgate-ai-pr"
$fork = "pacgate-ai/pacgate-ai-pr"

# 1. Get upstream main SHA
$upMain = Invoke-RestMethod -Uri "$api/repos/$upstream/git/ref/heads/main" -Headers $h -TimeoutSec 30
$baseSha = $upMain.object.sha
Write-Output "base (upstream/main): $baseSha"

# 2. Get the base commit object
$baseCommit = Invoke-RestMethod -Uri "$api/repos/$fork/git/commits/$baseSha" -Headers $h -TimeoutSec 30
$baseTree = $baseCommit.tree.sha
Write-Output "base tree: $baseTree"

# 3. Locate the 4 carriers in the tree (recursive listing, filter by path)
$tree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$baseTree`?recursive=1" -Headers $h -TimeoutSec 60
$carriers = @($tree.tree | Where-Object { $_.path -like "*pacgate-ai-remote-handbook/OPERATOR.md" -or $_.path -like "*MCP*" })
Write-Output "carriers found in tree: $($carriers.Count)"
$carriers | ForEach-Object { Write-Output "  - $($_.path.Substring(0, [Math]::Min(90, $_.path.Length))) type=$_.type" }
if ($carriers.Count -ne 4) { Write-Output "STOP: expected 4 carriers"; exit 1 }
if (@($carriers | Where-Object { $_.type -ne "blob" }).Count -ne 0) { Write-Output "STOP: non-blob match"; exit 1 }

# 4. Build the new tree: base tree + 4 deletions + gitignore update
$treeItems = @()
foreach ($c in $carriers) {
    $treeItems += @{ path = $c.path; mode = $c.mode; type = "blob"; sha = $null }
}
# gitignore: fetch current content, append rules
$giPath = ".gitignore"
$giEntry = $tree.tree | Where-Object { $_.path -eq $giPath }
if ($giEntry) {
    $giBlob = Invoke-RestMethod -Uri "$api/repos/$fork/git/blobs/$($giEntry.sha)" -Headers $h -TimeoutSec 30
    $giText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($giBlob.content))
} else {
    $giText = ""
}
$giNew = $giText + "`n# Credential carriers (incident 2026-09-16) - never track`n" +
    "pacgate-ai-assets/**/pacgate-ai-remote-handbook/OPERATOR.md`n" +
    "pacgate-ai-assets/**/MCP*/`n"
$giBytes = [System.Text.Encoding]::UTF8.GetBytes($giNew)
$giBlobNew = Invoke-RestMethod -Uri "$api/repos/$fork/git/blobs" -Method Post -Headers $h -TimeoutSec 30 `
    -Body ([System.Text.Encoding]::UTF8.GetBytes((@{ content = [Convert]::ToBase64String($giBytes); encoding = "base64" } | ConvertTo-Json))) `
    -ContentType "application/json"
Write-Output "new gitignore blob: $($giBlobNew.sha)"
$treeItems += @{ path = $giPath; mode = "100644"; type = "blob"; sha = $giBlobNew.sha }

# 5. Create the new tree
$body = @{ base_tree = $baseTree; tree = $treeItems } | ConvertTo-Json -Depth 5
$newTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees" -Method Post -Headers $h -TimeoutSec 30 -Body $body -ContentType "application/json"
Write-Output "new tree: $($newTree.sha)"

# 6. Create the commit (author = pacgate-ai)
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$commitBody = @{
    message = "fix(security): remove credential carriers from tracked tree`n`n" +
        "Removes 4 files containing live PacGate credentials from the public tree`n" +
        "(incident 2026-09-16): OPERATOR.md + 3 MCP-authorized files.`n`n" +
        "NOTE: removal from HEAD does NOT purge git history. Credentials in prior`n" +
        "commits remain public and MUST be rotated. This commit only stops the`n" +
        "current tree from exposing them."
    tree = $newTree.sha
    parents = @($baseSha)
    author = @{ name = "pacgate-ai"; email = "pacgate-ai@users.noreply.github.com"; date = $now }
} | ConvertTo-Json -Depth 5
$newCommit = Invoke-RestMethod -Uri "$api/repos/$fork/git/commits" -Method Post -Headers $h -TimeoutSec 30 -Body $commitBody -ContentType "application/json"
Write-Output "new commit: $($newCommit.sha)"

# 7. Create branch on fork
$branchBody = @{ ref = "refs/heads/security/remove-credential-carriers"; sha = $newCommit.sha } | ConvertTo-Json
try {
    $null = Invoke-RestMethod -Uri "$api/repos/$fork/git/refs" -Method Post -Headers $h -TimeoutSec 30 -Body $branchBody -ContentType "application/json"
    Write-Output "branch created: security/remove-credential-carriers"
} catch {
    # branch exists -> update it
    $null = Invoke-RestMethod -Uri "$api/repos/$fork/git/refs/heads/security/remove-credential-carriers" -Method Patch -Headers $h -TimeoutSec 30 -Body $branchBody -ContentType "application/json"
    Write-Output "branch updated: security/remove-credential-carriers"
}

# 8. Verify: list the new branch tree, count carriers
$vTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$($newTree.sha)`?recursive=1" -Headers $h -TimeoutSec 60
$vCarriers = @($vTree.tree | Where-Object { $_.path -like "*pacgate-ai-remote-handbook/OPERATOR.md" -or $_.path -like "*MCP*" })
Write-Output "VERIFY: carriers in new tree = $($vCarriers.Count) (expect 0)"
Write-Output "DONE"