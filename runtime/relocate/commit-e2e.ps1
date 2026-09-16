$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg13.txt'
$msg = @"
chore(relocate): e2e audit, and close a gap the audit found

Ran a full end-to-end audit rather than assuming completion. Results:

BUILD MATRIX (all four attempted):
  pacgate-api (Rust)       PASS  - built, ran against the live DB, served HTTP 4/4
  pacgate-mcp (Python)     PASS  - cached layers
  deer-flow-pacgate        PASS  - exit=0, 3919.8s (65 min)
  deer-flow-frontend       FAIL  - COPY deploy/deer-flow-src/frontend not found

DIAGNOSED the frontend failure instead of guessing. deploy/deer-flow-src is
GITIGNORED and UNTRACKED in the original repo (0 tracked files; 574 files /
31.3 MB on disk). It is a GENERATED artifact that build-frontend.ps1 clones
from the bytedance tag on demand, so Phase 1 correctly skipped it as source.

BUT it is a real gap in the cutover: the runtime-state copy step transferred
data/, openviking/, .env and node_modules, and MISSED this directory. The old
repo had it from a previous build; the new one did not. Closed by copying
574/574 files, verified still gitignored so it cannot be staged.

Also recorded the honest completion state in runtime/relocate/E2E-STATUS.txt.
Not fully e2e, for six reasons - the two that matter being:
  1. NO GIT REMOTE (github.com is reachable but gh is not authenticated)
  2. Credential rotation still outstanding (4 files still public on GitHub)
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline -1
& git -C $repo status --porcelain | Measure-Object -Line | ForEach-Object { "uncommitted: $($_.Lines)" }