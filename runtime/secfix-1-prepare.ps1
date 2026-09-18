# Step 1a: clone fork, branch from upstream/main, remove the 4 credential carriers,
# add gitignore rules, commit. NEVER prints tokens. ASCII-only console output.
$ErrorActionPreference = "Stop"
$tmp = "C:\Users\pacga\github-pr\pacgate-law\runtime\tmp-sec-fix"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
git clone --quiet https://github.com/pacgate-ai/pacgate-ai-pr.git $tmp
if ($LASTEXITCODE -ne 0) { Write-Output "CLONE-FAIL"; exit 1 }
git -C $tmp remote add upstream https://github.com/JZKK720/pacgate-ai-pr.git | Out-Null
git -C $tmp fetch --quiet upstream main
if ($LASTEXITCODE -ne 0) { Write-Output "FETCH-UPSTREAM-FAIL"; exit 1 }
$up = git -C $tmp rev-parse upstream/main
Write-Output "upstream/main base: $up"
git -C $tmp checkout --quiet -b security/remove-credential-carriers $up
if ($LASTEXITCODE -ne 0) { Write-Output "BRANCH-FAIL"; exit 1 }

# Enumerate what the pathspecs WILL match (verification before removal)
$all = git -C $tmp ls-tree -r --name-only HEAD
$mcpMatches = @($all | Select-String "MCP")
$opMatches  = @($all | Select-String "OPERATOR.md")
Write-Output "pre-check: MCP-matching paths=$($mcpMatches.Count) OPERATOR paths=$($opMatches.Count)"
Write-Output "pre-check: total tracked files=$($all.Count)"

# Remove via CJK-free glob pathspecs (codepage-proof)
git -C $tmp rm -r -q -- ':(glob)pacgate-ai-assets/**/MCP*/**' ':(glob)pacgate-ai-assets/**/OPERATOR.md'
if ($LASTEXITCODE -ne 0) { Write-Output "RM-FAIL"; exit 1 }
$staged = @(git -C $tmp diff --cached --name-only)
Write-Output "staged deletions: $($staged.Count)"
git -C $tmp diff --cached --name-status | ForEach-Object { $_.Substring(0, [Math]::Min(60, $_.Length)) }

if ($staged.Count -ne 4) { Write-Output "STOP: expected exactly 4 deletions"; exit 1 }
# Confirm none of the staged paths is outside pacgate-ai-assets
$outside = @($staged | Where-Object { -not $_.StartsWith("pacgate-ai-assets/") })
Write-Output "staged paths outside pacgate-ai-assets: $($outside.Count)"
if ($outside.Count -ne 0) { Write-Output "STOP: unexpected scope"; exit 1 }
# Confirm OPERATOR.md is among them and post-state has 0 matches
$stillOp = @(git -C $tmp ls-files | Select-String "OPERATOR.md")
$stillMcp = @(git -C $tmp ls-files | Select-String "MCP")
Write-Output "post-rm: OPERATOR remaining=$($stillOp.Count) MCP remaining=$($stillMcp.Count)"

# Append gitignore rules (byte-level, encoding-safe)
$gi = Join-Path $tmp ".gitignore"
$addition = [System.Text.Encoding]::UTF8.GetBytes(
  "`n# Credential carriers (incident 2026-09-16) - never track`n" +
  "pacgate-ai-assets/**/pacgate-ai-remote-handbook/OPERATOR.md`n" +
  "pacgate-ai-assets/**/MCP*/`n")
if (Test-Path $gi) {
  $b = [System.IO.File]::ReadAllBytes($gi)
  [System.IO.File]::WriteAllBytes($gi, $b + $addition)
  Write-Output "gitignore: appended to existing"
} else {
  [System.IO.File]::WriteAllBytes($gi, $addition)
  Write-Output "gitignore: created new"
}
git -C $tmp add .gitignore

# Commit with message from UTF-8 file (CJK-safe)
$msg = Join-Path $tmp "..\commit-msg-secfix.txt"
git -C $tmp commit --quiet -F $msg
if ($LASTEXITCODE -ne 0) { Write-Output "COMMIT-FAIL"; exit 1 }
$sha = git -C $tmp rev-parse HEAD
Write-Output "commit: $sha"
git -C $tmp show --stat --format="%h %s" HEAD | Select-Object -First 8 | Out-String -Width 120
Write-Output "READY-TO-PUSH"