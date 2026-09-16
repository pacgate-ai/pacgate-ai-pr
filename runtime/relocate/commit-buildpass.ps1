$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$f = Join-Path $env:TEMP 'pg-msg9.txt'
$msg = @"
build(relocate): full Rust build PASSES and runs against the live database

Ran the actual build (not just --check). Result: the monorepo path builds and
the resulting image is functionally correct.

  docker build -f Dockerfile -t pacgate-api:local-verify .
  -> exit 0, 7.4 min cold build, 0 compiler warnings, 163 MB image

Verified beyond "it compiled":
  - both binaries present and executable (pacgate-server 16.7 MB, pacgate-seed 9.6 MB)
  - pacgate-seed --help exits 0 with usage
  - all shared libs resolve (libssl.so.3, libcrypto.so.3, liblzma, libgcc_s)
  - migrations copied into the image (5 SQL files)
  - END-TO-END: ran the built image on the live pacgate-ai-bundle_default
    network against the real pacgate-db:
      "Connected to database" -> "Migrations applied" ->
      "RAG store initialized" -> "Listening on http://0.0.0.0:8080"
      container stayed running, restarts=0
  - HTTP: 4/4 endpoints responded (401 = auth middleware working as intended)

The .dockerignore effect is measurable: build context transferred 6.54 MB
instead of 1,957.6 MB.

Also fixed a test-harness bug: passing env via repeated -e flags broke because
OPENVIKING_CONF_CONTENT is JSON containing spaces, and PowerShell's
array-to-native marshalling split it ("docker run requires at least 1
argument"). Switched to --env-file.

Note: the deer-flow-pacgate build is still running; it pulls a large base image
and installs build tooling from deb.debian.org, which is slow from this region.
"@
[System.IO.File]::WriteAllText($f, $msg, (New-Object System.Text.UTF8Encoding($false)))
& git -C $repo add -A
& git -C $repo commit -q -F $f
Remove-Item $f -Force
& git -C $repo log --oneline | Select-Object -First 3
