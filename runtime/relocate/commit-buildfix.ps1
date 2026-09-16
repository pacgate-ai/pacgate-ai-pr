$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg7.txt'
$msg = @"
fix(relocate): repair build paths broken by the workspace flatten

The import flattened the Rust workspace (source `pacgate-ai/X` -> monorepo
`pacgate-ai/X`), which moved Dockerfile/Cargo.toml up one level. Two build
entry points still referenced the old nested layout and would have failed:

  - deploy/build-images.ps1: `-f $Root/pacgate-ai/Dockerfile` with context
    `$Root/pacgate-ai` -> now `-f $Root/Dockerfile` with context `$Root`
  - .github/workflows/build-ghcr.yml: `context: pacgate-ai` +
    `file: pacgate-ai/Dockerfile` -> `context: .` + `file: Dockerfile`

Verified after the fix: every docker build context/file resolves, the
Dockerfile's `COPY migrations` resolves, all 16 workspace members and both
binaries (pacgate-server, pacgate-seed) resolve, and all crate path deps are
relative (`../pacgate-core` etc.) so they are location-independent.

Also verified: no absolute `path =` deps anywhere, and Cargo.toml/Cargo.lock
contain no absolute paths.

Remaining (not a build breakage): deploy/knowledge-graph.json is a GENERATED
graphify artifact whose `filePath` fields still name the old layout. It is
regenerable, not a build input.

Note: cargo/rustc are NOT installed on this host. Rust builds run in Docker
(FROM rust:1.94-bookworm), so `docker build` is the build path, not `cargo`.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline | Select-Object -First 3
