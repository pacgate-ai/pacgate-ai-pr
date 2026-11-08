# AIPC1 upgrade — v0.2.30 → v0.2.32 (upstream/main 17a498e)

Date: 2026-11-08
Machine: AIPC1 (`C:\Users\pacga\github-pr\pacgate-law`)
Target: `upstream/main` = `17a498e`, which is **2 commits ahead of the `v0.2.32` tag** (`7a6dd73`).

## Why upstream/main and not the tag

`v0.2.32` is not the head. Two doc commits landed after it:

| Commit | Subject |
|---|---|
| `f19b8c1` | fix(docs): put the client README under version control like every other doc |
| `17a498e` | fix(docs): re-render the two handbook PDFs the version bump orphaned |

The 0.2.30 upgrade set this precedent for the same reason.

## Merge method

The two histories are unrelated, so no `git merge`. Per-file 3-way merge
(`git merge-file`) with `28d73c4` (v0.2.30) as base:

- **7 files** adopted new (did not exist locally)
- **34 files** adopted verbatim (local blob == 0.2.30 base, so upstream wins)
- **8 files** three-way merged — **7 merged clean, 1 conflicted** (`run-all-checks.ps1`)

All 41 adopted files verified byte-identical by `git hash-object` vs `git rev-parse`.

## 🔴 The three shadowing defects this upgrade had to fix

A bind mount **wins** over the image's baked copy. Three local files were
byte-identical to the **0.2.30 base** and bind-mounted over the exact paths
0.2.32 changed — so pulling the new image alone would have changed **nothing**:

| File | Mounted over | Was | Now |
|---|---|---|---|
| `patches/deer-flow-run-recursion-cap.py` | `app/gateway/services.py` | `== 28d73c4` | 0.2.32, floor 2000 |
| `patches/deer-flow-worker.py` | `runtime/runs/worker.py` | `== 28d73c4` | 0.2.32, actionable message |
| `deploy/pacgate-mcp/server.py` | `/app/server.py` | `== 28d73c4` | 0.2.32, firecrawl tools |

Verified live in the running containers after recreate:

```
docker exec deer-flow grep -c '_PACGATE_MIN_RECURSION_LIMIT' .../services.py   -> 4
docker exec deer-flow grep -c '_recursion_exhaustion_message' .../worker.py    -> 2
docker exec pacgate-mcp python3 -c "...ast..."  -> ['pacgate_web_scrape', 'pacgate_web_search']
```

## 🔴 The fourth defect: a gate that was not running

`scripts/run-all-checks.ps1` had **dropped** two registrations that exist in the
0.2.30 base:

```
-    'scripts/test-run-recursion-cap.ps1'
-    'scripts/test-chat-artifact-durability.ps1'
```

`test-run-recursion-cap.ps1` existed on disk but was not registered, so the
1000-wall survived a fully green suite. Restored. The array is now the union of
local (70) and upstream (72) = **74 gates**, no duplicates.

## A fifth defect found during the merge

`scripts/audit-deer-flow-patches.ps1` had lost its
`deer-flow-run-recursion-cap.py` → `backend/app/gateway/services.py` mapping in a
prior local edit. That made `test-run-recursion-cap.ps1` fail on its rebase-audit
assertion (42 passed, 1 failed). Restored; the gate is now **43 passed, 0 failed**.

## Local deltas preserved

| File | What survived |
|---|---|
| `patches/deer-flow-agent.py` | `_resolve_subagent_enabled()` + both call sites (upstream never touched this file) |
| `patches/deer-flow-memory-updater.py` | LOCAL-ONLY, still mounted |
| `patches/deer-flow-uploads-middleware.py` | LOCAL-ONLY, still mounted |
| `patches/deer-flow-sandbox-tools.py` | LOCAL-ONLY, still mounted |
| `deer-flow-config.yaml` | `sandbox.mounts` → `/mnt/playbooks`; the 10-agent `subagents:` block; loop-guard rationale |
| `playbooks/nda-playbook.md` | LOCAL-ONLY |
| `compose.{bundle,prod}.yaml` | `../../../deer-flow/skills/public`; `./deer-flow-skills`; memory-updater / sandbox-tools / uploads-middleware mounts; `DEERFLOW_MAX_RECURSION_LIMIT: "4000"` |
| `install.ps1` | `Invoke-WithNativeStderr` helper + 38 call sites |
| `ollama-models.txt` | `qwen3.8-legal:27b-mid`, `qwen3.8:27b-mtp-q4_K_M` |
| `run-all-checks.ps1` | `test-prompt-contract.ps1`, `test-document-roundtrip-e2e.ps1` |

Both compose lanes carry **29 patch mounts** and A5 parity holds.

## Model roster after the upgrade

Decision: **Option A** — adopt upstream's residency argument.

| Tier | Tag | Note |
|---|---|---|
| Main | `deepseek-v4.1-flash:cloud` | cloud |
| Mid | `nemotron-3.5-bolt:e4b-q8_0` | **changed** from `qwen3.8-legal:27b-mid` (17 GB on a 16 GB card) |
| Low | `nemotron-3.5-bolt:e4b-q8_0` | same tag as Mid — one resident model, no eviction |
| Fallback | `ornith-1.5:9b` | still installed and picker-selectable |
| Embeddings | `nomic-embed-text:latest` | present |

`test-model-roster-consistency.ps1` → **15 of 15 passed** (A1a/A1b/A1c/A2/A3/A4/A5/A6).

## Images

All five pinned to `0.2.32` and pulled from GHCR. **All share revision `7a6dd732c6df`.**

| Image | Digest |
|---|---|
| `pacgate-api` | `sha256:6273177417887ed70daf59cc61e9168b2a203c07d34edd894d97eb7a2f1b97cd` |
| `deer-flow-pacgate` | `sha256:7019ae03323f6e6a37733e2666141ad86b66117f12baa5040ad591332e5338c3` |
| `deer-flow-frontend-pacgate` | `sha256:ff70b1d03c8f3df8dac412a967b5868a3cd21ca25731725e0d37d36550b36abb` |
| `pacgate-mcp` | `sha256:cb33113c6756d1310e9f5e280dd34e5fe0f2a59d73f99819df896569346457e6` |
| `ocr-service` | `sha256:419a5e4c8a7a580dc3ffced4e66b05380324912be60e90ed31c0cd6cdf6df1e4` |

`/pacgate/build-info` → `{"revision":"7a6dd732c6df285c610182f352dd351d68f28d50","version":"0.2.32"}`

## ⚠️ Operational note: the Docker proxy is dead

`HTTP_PROXY`/`HTTPS_PROXY` point at `http://127.0.0.1:7890`, which is **not
listening**. `docker compose pull` fails with
`connectex: No connection could be made because the target machine actively refused it`.
GHCR is reachable **directly** (verified: token endpoint 200 in 0.58 s).

Workaround used, and the one to use until the proxy is restored:

```powershell
$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:http_proxy=''; $env:https_proxy=''
docker pull ghcr.io/jzkk720/<image>:0.2.32
```

`docker compose pull` also stalled for >10 min with no layer progress even with
the proxy cleared; direct `docker pull` per image worked. Prefer it.

## Verification

### Runtimes — all healthy

`pacgate-api`, `deer-flow`, `deer-flow-frontend`, `pacgate-mcp`, `ocr-service`,
`openviking`, `pacgate-db`, `pacgate-nginx` — 8/8 healthy on `0.2.32`.
`qm-pacgate` (6 containers) untouched and still up. 22 containers, 0 unhealthy.

### Gate suite — 74 gates

| Result | Count | Detail |
|---|---|---|
| PASS | 71 | |
| FAIL | 2 | both structural, see below |
| SKIP | 1 | `test-rust-workspace.ps1` — no cargo on this box |

**`test-release-provenance.ps1` — FAIL, structural, not a regression.**
It PASSES its real assertion (`all 6 published images share one revision
(7a6dd732c6df)`) and then fails because it compares that revision against **our
fork HEAD**, which is a different lineage with 861 local-delta files. It can
never pass on a fork. The images themselves are correct.

**`test-compose-healthchecks.ps1` — FAIL under `powershell` 5.1, PASS under `pwsh`.**
It uses `ConvertFrom-Json -AsHashtable`, which is PowerShell 6+. Verified
**unchanged by this upgrade** (base == local == upstream blob), so it is a
pre-existing PS 5.1 incompatibility. Under `pwsh`: `0 failure(s), 0 skipped`.

### The four gates this upgrade exists to satisfy

| Gate | Result |
|---|---|
| `test-run-recursion-cap.ps1` | **43 passed, 0 failed** |
| `test-pdf-outline-extraction.ps1` | **7 passed, all green** |
| `test-firecrawl-wiring.ps1` | **19 passed, 0 failed** |
| `test-chat-artifact-durability.ps1` | **7 of 7 passed** |

### Functional

| Area | Result |
|---|---|
| MCP handshake | `initialize` OK, server `pacgate` v1.30.0 |
| MCP tool count | **26** (was 24) — includes `pacgate_web_search`, `pacgate_web_scrape` |
| `pacgate_web_search` live | `available: true`, real results returned |
| `/pacgate/api/search/health` | **firecrawl `available: true`**; 10 of 11 connectors up (only `opencorporates` false) |
| pymupdf4llm | installed, `pymupdf 2.1`; converter resolves to `auto` |
| Document generation | **19/19**, plus **8/8 soak runs HTTP 200, 0 failures** |
| Document roundtrip | **33 passed, 0 failed, 0 skipped** |
| Sanitizer e2e | **PASS** |
| Agent MCP e2e | **5 passed, 0 failed** |
| Model picker e2e | **13 passed, 0 failed** |
| Legal journey | **full legal journey PASSED, all lanes verified** |
| Lane connectivity | 11 passed, 0 not reachable |
| Stack version coherence | **14 passed** — every service is the image its pin names |
| Baked patch parity | **16 passed, 0 failed, 0 warnings** |
| Workflow library | 222 workflows, 46 categories served |
| Playbook mount | `/mnt/playbooks/nda-playbook.md` reachable (8126 bytes) |
| Skills | 65-skill merged tree + 5 seeds |
| Extensions config | **30 connectors intact** (backup at `runtime/upgrade-0.2.32/extensions-config.backup.json`) |

## Known gaps

1. **`test-release-provenance.ps1`** needs a fork-aware mode before it can be
   green here. The images are correct; the gate's comparison target is not.
2. **`test-compose-healthchecks.ps1`** needs `pwsh`, not `powershell`. Pre-existing.
3. **`opencorporates` connector** reports `available: false` — no API key on this
   machine. Unrelated to the upgrade.
4. **`deer-flow` sub-repo** is 852 commits behind `bytedance/deer-flow` and 14
   ahead. Deliberately out of scope; separate upgrade with its own risk profile.
5. **Docker proxy `127.0.0.1:7890` is dead.** Restore it, or keep clearing the
   proxy env vars before any registry operation.
