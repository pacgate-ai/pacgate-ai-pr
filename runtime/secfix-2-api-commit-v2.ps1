# Security fix via GitHub API - v2 with SHA-based carrier matching (codepage-proof).
# The MCP授权 directory tree SHA is fetched from the base tree; its blob SHAs are
# matched against the recursive listing. No CJK literals are typed in this script.
$ErrorActionPreference = "Stop"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-secfix"; Accept = "application/vnd.github+json" }
$api = "https://api.github.com"
$fork = "pacgate-ai/pacgate-ai-pr"

# 1. Base = fork/main (synced to upstream)
$fMain = Invoke-RestMethod -Uri "$api/repos/$fork/git/ref/heads/main" -Headers $h -TimeoutSec 30
$baseSha = $fMain.object.sha
$baseCommit = Invoke-RestMethod -Uri "$api/repos/$fork/git/commits/$baseSha" -Headers $h -TimeoutSec 30
$baseTree = $baseCommit.tree.sha
Write-Output "base=$baseSha tree=$baseTree"

# 2. Recursive listing
$tree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$baseTree`?recursive=1" -Headers $h -TimeoutSec 60
Write-Output "recursive entries: $($tree.tree.Count)"

# 3. Find the MCP-authorized directory tree (CJK name - find by structure:
#    a tree whose path ends with the 3-char CJK dir under zhiiku... we cannot type it.
#    Instead: find trees whose path contains 'MCP' AND type=tree AND is under pacgate-ai-assets)
$mcpDirs = @($tree.tree | Where-Object { $_.type -eq "tree" -and $_.path -like "*MCP*" -and $_.path -like "*pacgate-ai-assets*" })
Write-Output "candidate MCP dirs: $($mcpDirs.Count)"
$mcpDirs | ForEach-Object { Write-Output "  dir: $($_.path) sha=$($_.sha)" }
if ($mcpDirs.Count -ne 1) { Write-Output "STOP: expected exactly 1 MCP dir tree"; exit 1 }
$mcpDirSha = $mcpDirs[0].sha

# 4. Fetch that directory tree -> its blob SHAs (codepage-proof: SHAs only)
$mcpTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$mcpDirSha" -Headers $h -TimeoutSec 30
$mcpBlobShas = @($mcpTree.tree | Where-Object { $_.type -eq "blob" } | ForEach-Object { $_.sha })
Write-Output "blobs inside MCP dir: $($mcpBlobShas.Count)"
if ($mcpBlobShas.Count -ne 3) { Write-Output "STOP: expected 3 blobs in MCP dir"; exit 1 }

# 5. Match full paths by SHA in the recursive listing
$carriers = @($tree.tree | Where-Object { $_.type -eq "blob" -and ($mcpBlobShas -contains $_.sha) })
Write-Output "carriers via SHA match: $($carriers.Count)"
$carriers | ForEach-Object { Write-Output "  - sha=$($_.sha.Substring(0,8)) size=$($_.size) path-len=$($_.path.Length)" }

# 6. OPERATOR.md by pure-ASCII path match
$op = @($tree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "*pacgate-ai-remote-handbook/OPERATOR.md" })
Write-Output "OPERATOR.md matches: $($op.Count)"
if ($op.Count -ne 1) { Write-Output "STOP: expected 1 OPERATOR.md"; exit 1 }
$carriers += $op[0]

# 7. Final gate: SHA match found 4 entries but one blob (a59e30ed, the docx)
#    exists at TWO paths -> 4 + 1 OPERATOR = 5 carrier files to remove.
if ($carriers.Count -ne 5) { Write-Output "STOP: expected 5 total (docx duplicated at 2 paths)"; exit 1 }
$outside = @($carriers | Where-Object { -not $_.path.StartsWith("pacgate-ai/pacgate-ai-assets/") })
if ($outside.Count -ne 0) { Write-Output "STOP: carrier outside expected subtree"; exit 1 }
Write-Output "GATE-PASSED: 5 carriers, all in pacgate-ai/pacgate-ai-assets/"

# 8. Build new tree: 5 deletions + gitignore update
$treeItems = @()
foreach ($c in $carriers) { $treeItems += @{ path = $c.path; mode = $c.mode; type = "blob"; sha = $null } }
$giEntry = $tree.tree | Where-Object { $_.path -eq ".gitignore" }
if ($giEntry) {
    $giBlob = Invoke-RestMethod -Uri "$api/repos/$fork/git/blobs/$($giEntry.sha)" -Headers $h -TimeoutSec 30
    $giText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($giBlob.content))
} else { $giText = ""; Write-Output "note: no .gitignore in base tree" }
$giNew = $giText + "`n# Credential carriers (incident 2026-09-16) - never track`n" +
    "pacgate-ai/**/pacgate-ai-remote-handbook/OPERATOR.md`n" +
    "pacgate-ai/**/MCP*/`n"
$giBytes = [System.Text.Encoding]::UTF8.GetBytes($giNew)
$giBody = @{ content = [Convert]::ToBase64String($giBytes); encoding = "base64" } | ConvertTo-Json
$giBlobNew = Invoke-RestMethod -Uri "$api/repos/$fork/git/blobs" -Method Post -Headers $h -TimeoutSec 30 -Body $giBody -ContentType "application/json"
Write-Output "new gitignore blob: $($giBlobNew.sha)"
$treeItems += @{ path = ".gitignore"; mode = "100644"; type = "blob"; sha = $giBlobNew.sha }

# 9. Create tree + commit + branch
# CRITICAL: bodies contain CJK paths. PS 5.1 Invoke-RestMethod encodes string
# bodies with the system codepage (GBK) -> mojibake -> GitRPC::BadObjectState.
# Send UTF-8 BYTES explicitly.
$newTreeBody = [System.Text.Encoding]::UTF8.GetBytes((@{ base_tree = $baseTree; tree = $treeItems } | ConvertTo-Json -Depth 5))
$newTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees" -Method Post -Headers $h -TimeoutSec 30 `
    -Body $newTreeBody -ContentType "application/json; charset=utf-8"
Write-Output "new tree: $($newTree.sha)"
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$commitJson = (@{
    message = "fix(security): remove credential carriers from tracked tree`n`n" +
        "Removes 4 files containing live PacGate credentials from the public tree`n" +
        "(incident 2026-09-16): OPERATOR.md + 3 MCP-authorized files.`n`n" +
        "NOTE: removal from HEAD does NOT purge git history. Credentials in prior`n" +
        "commits remain public and MUST be rotated. This commit only stops the`n" +
        "current tree from exposing them."
    tree = $newTree.sha
    parents = @($baseSha)
    author = @{ name = "pacgate-ai"; email = "pacgate-ai@users.noreply.github.com"; date = $now }
} | ConvertTo-Json -Depth 5)
$commitBody = [System.Text.Encoding]::UTF8.GetBytes($commitJson)
$newCommit = Invoke-RestMethod -Uri "$api/repos/$fork/git/commits" -Method Post -Headers $h -TimeoutSec 30 -Body $commitBody -ContentType "application/json; charset=utf-8"
Write-Output "new commit: $($newCommit.sha)"
$branchBody = @{ ref = "refs/heads/security/remove-credential-carriers"; sha = $newCommit.sha } | ConvertTo-Json
try {
    $null = Invoke-RestMethod -Uri "$api/repos/$fork/git/refs" -Method Post -Headers $h -TimeoutSec 30 -Body $branchBody -ContentType "application/json"
    Write-Output "branch created"
} catch {
    $null = Invoke-RestMethod -Uri "$api/repos/$fork/git/refs/heads/security/remove-credential-carriers" -Method Patch -Headers $h -TimeoutSec 30 -Body $branchBody -ContentType "application/json"
    Write-Output "branch updated"
}

# 10. Verify new tree has 0 carriers
$vTree = Invoke-RestMethod -Uri "$api/repos/$fork/git/trees/$($newTree.sha)`?recursive=1" -Headers $h -TimeoutSec 60
$vMcp = @($vTree.tree | Where-Object { $_.type -eq "blob" -and ($mcpBlobShas -contains $_.sha) })
$vOp = @($vTree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "*pacgate-ai-remote-handbook/OPERATOR.md" })
Write-Output "VERIFY: MCP blobs remaining=$($vMcp.Count) OPERATOR remaining=$($vOp.Count) (expect 0/0)"
Write-Output "DONE commit=$($newCommit.sha)"