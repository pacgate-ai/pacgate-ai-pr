$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg8.txt'
$msg = @"
build(relocate): add .dockerignore; validate all four build graphs

Answers "did the build survive?" with evidence rather than assumption.

KEY CORRECTION: the running stack proves the RUN survived, not the BUILD.
Every service in the stack runs a PULLED image (ghcr.io/pacgate-ai/*,
ghcr.io/yc-software/qm/*), so a healthy stack says nothing about buildability.

Validated with `docker build --check` (resolves base images + verifies COPY
sources, without executing the compile). All four now pass with
"Check complete, no warnings found":
  - pacgate-api (Rust)              exit=0
  - pacgate-mcp (Python)            exit=0
  - deer-flow-pacgate               exit=0
  - deer-flow-frontend-pacgate      exit=0

qm-pacgate is NOT built from source: compose.qm.yaml has zero `build:`
directives and there is no Dockerfile. Its 5 images are digest-pinned pulls
from ghcr.io/yc-software/qm/*. So there is no qm build to survive.

Added .dockerignore at the platform root. Without it the Rust Dockerfile's
`COPY . .` sent the ENTIRE tree to the daemon: measured 1,957.6 MB, of which
1,915.7 MB (98.4%) is client runtime data the compiler never reads. That is
minutes of pure overhead per build, growing as client data accumulates.

Caught and fixed a regression I introduced: the first version excluded
deploy/deer-flow-src/, but deploy/deer-flow-frontend-pacgate/Dockerfile does
`COPY deploy/deer-flow-src/frontend ./frontend`, so BuildKit failed with
CopyIgnoredFile. That path is a build input and is now explicitly retained.

Environment note: docker.io is unreachable from this machine (timeout), but
the daocloud mirror works and is already in use. Pulled rust:1.94-bookworm and
debian:bookworm-slim through it so the Rust graph could be validated offline.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline | Select-Object -First 3
