# Build a real git tree for upstream 86a9feb from the downloaded files, then
# prove it equals the commit's actual tree SHA (526da22b...).
#
# WHY NOT `git worktree add 337fb9d` + copy: this repo has core.autocrlf=true on a
# Windows host, so a checkout materialises CRLF and `write-tree` would hash the
# CRLF bytes - producing a tree that does NOT match upstream's LF tree. The blob
# route below writes the downloaded bytes verbatim (`--no-filters`) and checks
# each blob SHA against GitHub's own, so any encoding drift fails loudly.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$git = 'C:\Program Files\Git\cmd\git.exe'
$out = Join-Path $env:TEMP '86a9feb'
$apiBase = 'https://api.github.com/repos/JZKK720/pacgate-ai-pr/contents'
$expectedTree = '526da22b591157a5ef7cebea933cbc8d280a4862'
$parentTree = '085b5a9481bb8df706c4363367d2b8c8907acff0'  # 337fb9d^{tree}

$files = @(
    'deploy/client-bundle/compose.bundle.yaml'
    'deploy/client-bundle/compose.prod.yaml'
    'deploy/client-bundle/patches/deer-flow-memory-prompt.py'
    'plans/031-aipc-latency-root-cause-and-fix.md'
    'plans/README.md'
    'scripts/run-all-checks.ps1'
    'scripts/test-memory-lane.ps1'
    'scripts/test-memory-prompt-stability.ps1'
)

# Confirm the parent tree we read from really is 337fb9d's, or every hash below
# is being computed against the wrong base.
$actualParent = (& $git rev-parse '337fb9d^{tree}').Trim()
if ($actualParent -ne $parentTree) {
    throw "parent tree mismatch: have $actualParent want $parentTree"
}

# 1. Write each downloaded file as a blob and compare to GitHub's blob SHA.
$blobs = @{}
$mismatch = 0
foreach ($f in $files) {
    $dest = Join-Path $out ($f -replace '/', '\')
    $sha = (& $git hash-object -w --no-filters $dest).Trim()
    $meta = (curl.exe -sS --max-time 60 "$apiBase/$f`?ref=86a9feb") | ConvertFrom-Json
    $want = $meta.sha
    $ok = ($sha -eq $want)
    if (-not $ok) { $mismatch++ }
    '{0,-6} {1}  {2}' -f $(if ($ok) { 'OK' } else { 'BAD' }), $sha.Substring(0, 12), $f
    $blobs[$f] = $sha
}
if ($mismatch -ne 0) { throw "$mismatch blob(s) do not match GitHub - the download is not byte-identical" }

# 2. Read the parent tree into a throwaway index, overlay the 8 blobs, write-tree.
$idx = Join-Path $env:TEMP 'idx-86a9feb'
Remove-Item -Force $idx -ErrorAction SilentlyContinue
$env:GIT_INDEX_FILE = $idx
try {
    & $git read-tree $parentTree
    if ($LASTEXITCODE -ne 0) { throw 'read-tree failed' }
    foreach ($f in $files) {
        & $git update-index --add --cacheinfo "100644,$($blobs[$f]),$f"
        if ($LASTEXITCODE -ne 0) { throw "update-index failed for $f" }
    }
    $builtTree = (& $git write-tree).Trim()
}
finally {
    Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    Remove-Item -Force $idx -ErrorAction SilentlyContinue
}

"built_tree =$builtTree"
"expect_tree=$expectedTree"
if ($builtTree -ne $expectedTree) { throw "TREE MISMATCH - do not swap to this" }

# 3. Materialise a synthetic commit so the swap has a ref to point at.
$msg = 'upstream 86a9feb: stable memory prompt prefix + bounded input (materialised via HTTPS; git transport blocked on this host)'
$commit = (& $git commit-tree $builtTree -p 337fb9d -m $msg).Trim()
& $git update-ref refs/upstream-curl/86a9feb $commit
"ref       =$((& $git rev-parse refs/upstream-curl/86a9feb).Trim())"
"ref_tree  =$((& $git rev-parse 'refs/upstream-curl/86a9feb^{tree}').Trim())"
'--- 4/4 blob + tree identity verified ---'
