---
description: "Repo safety rules and verification traps for pacgate-ai-pr. Use when editing deploy/client-bundle (compose, config, patches, install.ps1), scripts/, or .github/workflows — the paths where a wrong edit silently corrupts a running client stack."
applyTo: "{deploy/client-bundle/**,scripts/**,.github/workflows/**,plans/**}"
---

# pacgate-ai-pr — working rules for the deploy surface

These are not style preferences. Each rule below exists because the failure it prevents
has already happened on a live client machine.

## 1. The repo IS the deployment monorepo

`deploy/client-bundle/` is the **live stack definition**, not a sample. Containers on a
client AIPC run directly from these files via `docker compose -f compose.bundle.yaml`.

- Never "tidy" a filename or move a directory in `deploy/client-bundle/` without checking
  every reference. `compose.prod.yaml` derives its **Compose project name** from the
  directory name, and the project name prefixes every **named volume**.
- `compose.prod.yaml` must keep `name: pacgate-ai-bundle`. Remove that key and Compose
  derives `client-bundle` from the directory, creates a **second, empty**
  `client-bundle_pacgate-db-data` volume, and the app connects to an empty database —
  which looks exactly like total data loss while the real data sits in the old volume.
  Both volumes exist today; the orphan is **not** empty. Never delete a Docker volume.

## 2. `patches/` files are whole-file bind mounts

Every entry in `compose.bundle.yaml` mounts a patch **over** a shipped file, e.g.

```
./patches/deer-flow-agent.py:/app/backend/packages/harness/deerflow/agents/lead_agent/agent.py:ro
```

Consequences that bite:

- A patch is a **full replacement**, not a diff. Editing a patch by copying from the
  deer-flow upstream repo will **revert** the live file's other local fixes. Always start
  from the **live** file, then change it:
  ```bash
  docker exec deer-flow cat /app/backend/packages/harness/deerflow/<path> > patches/<name>.py
  ```
- A **new** patch needs three things together, or it silently does nothing: the file, a
  mount line, and a container **recreate**.
- `docker compose up -d` alone does **not** apply an env or volume change. Use:
  ```bash
  docker compose -f deploy/client-bundle/compose.bundle.yaml up -d --force-recreate --no-deps <service>
  ```
  Never `--force-recreate` `pacgate-db`.

## 3. The deployed base is NOT the deer-flow source in this repo

The image is built from **deer-flow v2.0.0**. The `deer-flow/` checkout may be **v2.1.0**
and contains modules that **do not exist in the container**.

**Before relying on any harness file, confirm it is present in the running image:**

```bash
docker exec deer-flow sh -c "ls /app/backend/packages/harness/deerflow/agents/middlewares/ | grep -i routing"
```

This has already caused a wrong diagnosis: a plan assumed
`mcp_routing_middleware.py` existed, but v2.0.0 has only
`deferred_tool_filter_middleware.py`, and `tool_search.py` has no
`build_mcp_routing_middleware`. Confirm, then plan.

Use `/app/backend/.venv/bin/python` inside the container — `python` is a bare interpreter
with no project dependencies.

## 4. PowerShell 5.1 traps (all three have shipped bugs)

- **`$ErrorActionPreference='Stop'` + any redirection** turns a native command's *stderr*
  write into a **terminating** error. `ollama show <missing-tag>` writes to stderr, so a
  fresh-install path dies. Lower the preference for the call:
  ```powershell
  $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & $exe @args 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previous }
  ```
- **`docker inspect -f '{{index .Config.Labels "x"}}'`** breaks. Use `ConvertFrom-Json`.
- **`??`** is unsupported; `$pass` collides case-insensitively with `$script:pass`.
- **Encoding:** never `Get-Content`/`Set-Content` on UTF-8 files carrying CJK — Chinese
  Windows decodes as GBK and double-encodes. Use
  `[System.IO.File]::ReadAllText/WriteAllText` with `UTF8Encoding($false)` (no BOM).
  The connector template carries 314 CJK characters.

## 5. Credentials — active incident, verify by blob SHA

Four credential files were published in this repo's history. Deleting files does **not**
undo public history; the credentials must be **rotated**.

Checking by **filename silently fails**: three names are CJK, and PowerShell 5.1 decodes
git's UTF-8 output as GBK, producing mojibake that never matches — a *false* "not tracked".
Check by **blob SHA** instead (`scripts/assert-no-staged-secrets.ps1`,
`scripts/check-credential-state.ps1`).

Never commit `.env`, `deer-flow-extensions-config.json`, `data/`, `.deer-flow/`,
`checkpoints.db*` — all gitignored. Never `git add -f` them.

## 6. Two clocks, two machines

- `docker logs deer-flow` timestamps are **UTC**.
- `%LOCALAPPDATA%\Ollama\server.log` is local **+08**.
- Cloud model calls (`:cloud` tags) **never appear** in the local Ollama log. A local-log
  maximum therefore **cannot** bound a cloud prompt size. Do not reason across the two.

## 7. Per-machine values stay local

Do **not** upstream: the model roster, `PACGATE_MODEL_{MAIN,MID,LOW}`,
`GATEWAY_CORS_ORIGINS`, or machine-specific context/quantisation tuning
(user directive 2026-09-21). These are pinned per client machine.

## 8. Verify against the live stack, and label projections

A config file on disk is not evidence that a running container behaves that way: the live
config is a **bind mount** and may differ from the repo copy (it did — the repo root
`config.yaml` was stale while the container read `deer-flow-config.yaml`).

State every quantitative claim so a reader can reproduce it, and label anything not yet
measured as a **projection**, not a result.
