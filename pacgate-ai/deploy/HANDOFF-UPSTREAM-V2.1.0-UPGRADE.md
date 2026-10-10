# Upstream Handoff — deer-flow v2.1.0 upgrade + full-stack GHCR rebuild

> **For:** the maintainer of `JZKK720/pacgate-ai-pr` (or an agent working in that repo).
> This is an **upstream job** — it cannot be done on the deployment machine
> (`pacgate-law` is a local-only docs/scope wrapper with **no push target** and does
> not own the GHCR build).
> **Status:** documented 2026-10-10. The upgrade is NOT yet executed. The deployed
> stack is still on **v2.0.0**. This handoff is what the developer pulls from the fork.
> Evidence source: `pacgate-ai/plans/023-deer-flow-2.1-upgrade.md` (the authoritative
> procedure), verified against live `v2.0.0`/`v2.1.0` tags in this session.

## Why this is urgent

The deployed deer-flow base is **v2.0.0** (frontend clone tag `v2.0.0`, backend
digest `sha256:e7c503a803c99a039e08da61359932877a9e0d0196799429698244117338af13`).
Upstream bytedance **`v2.1.0`** (`f6e747be`, GA released 2026-10-07) is **1019 commits
ahead** of v2.0.0. Plan 023's trigger has fired, but the §2 rebase **execution remains**
(upstream JZKK720 commit `9e16546` states this explicitly).

Until this upgrade lands and GHCR images are rebuilt, the **memory card page still
cannot load** because the v2.1.0 memory architecture is not in the deployed base.

## Path mapping

The deployment monorepo nests everything under `pacgate-ai/`, so
**`pacgate-ai/deploy/X` here = `deploy/X` in `JZKK720/pacgate-ai-pr`**.
The deer-flow source lives at `pacgate-ai/deploy/deer-flow-src/` (shallow clone).
The authoritative procedure is `pacgate-ai/plans/023-deer-flow-2.1-upgrade.md`.

---

## Gap 1 — Memory adapter: HARD BREAK (this is the memory-card root cause)

**v2.1.0 DELETED `backend/packages/harness/deerflow/agents/memory/storage.py`** and
replaced it with `manager.py` + `backends/<name>/`. Verified:

```
v2.0.0: storage.py EXISTS     v2.1.0: storage.py MISSING
v2.0.0: manager.py MISSING    v2.1.0: manager.py EXISTS
```

The current adapter imports the deleted module — **this crashes on import under
v2.1.0**:

- `pacgate-adapters/python/pacgate_deerflow_adapter/storage.py:16` →
  `from deerflow.agents.memory.storage import MemoryStorage`

**Required migration (plan 023 §1.3 DECISION):** migrate `PacgateMemoryStorage` to the
v2.1.0 `MemoryManager` contract:

- Abstract methods (a backend must implement or it will not construct):
  - `add(thread_id, messages, *, agent_name, user_id, trace_id) -> None`
  - `get_context(user_id, ...)` — returns text injected into the prompt
  - `from_config(cls, backend_config, *, mode, **host_hooks) -> MemoryManager`
- Entry point is the **classmethod** `from_config` (constructor is not called directly).
- Resolution accepts a registered short name **or** a dotted import path
  (`pkg.mod:Cls`), so the adapter stays pip-installed and
  `manager_class: pacgate_deerflow_adapter.storage:PacgateMemoryManager` reaches it.
- It **fails loud** (no silent fallback to DeerMem) — deliberate.

**Do NOT adopt upstream's official OpenViking backend.** It relocates firm memory out
of `pacgate-api`. The per-matter lane, `PACGATE_MATTER_ID`, the revision/`If-Match`
conflict semantics (`MatterMemoryConflict`), and the matter-scoped isolation all live
on the pacgate side. Keep the migration's regression test green:
`pacgate-adapters/python/tests/test_memory_revision.py`.

**Carry-forward risk to check:** `deer-flow-sync.py` overrides
`deerflow/tools/sync.py` and reaches memory through the package 2.1.0 restructures.
The bind-mount path survives, but the **imports inside it** must be re-checked (the
audit script checks bind-mount targets, not the imports).

---

## Gap 2 — 13 backend patch mounts need a 3-way merge

All 13 patch-mount paths **still exist** in v2.1.0 (no silent breakage), but upstream
churn is large. Measured `git diff --numstat v2.0.0 v2.1.0`:

| Patch file | Upstream churn |
|---|---|
| `deer-flow-worker.py` | +2637/-269 |
| `deer-flow-thread-runs.py` | +1455/-115 |
| `deer-flow-agent.py` | +876/-137 |
| `deer-flow-auth.py` | +666/-74 |
| `deer-flow-prompt.py` | +567/-194 |
| `deer-flow-artifacts.py` | +440/-64 |
| `deer-flow-uploads.py` | +228/-155 |
| `deer-flow-title-middleware.py` | +219/-28 |
| `deer-flow-model-factory.py` | +185/-28 |
| `deer-flow-skill-storage.py` | +77/-4 |
| `deer-flow-tool-policy.py` | +23/-2 |
| `deer-flow-sync.py` | +16/-0 |
| `deer-flow-auth-errors.py` | +1/-0 |
| **TOTAL** | **+7390/-1070** |

**Procedure (plan 023 §2.1):** `git merge-file` 3-way per file. CRITICAL — **LF-normalize
all three inputs first** (ours is CRLF, upstream is LF; feeding CRLF against LF makes
every line differ → whole-file conflict). Then verify the result equals **only our
intended delta** (from plan 023 §1.2 table — e.g. `thread-runs` should be `+8/-2`, not
`+31/-1`). Use `--ignore-cr-at-eol` on verification diffs. Read base/new blobs to
**bytes**, never through a PowerShell string (em-dash transcode inflates deltas).

---

## Gap 3 — 17 frontend overlays need re-derivation

All overlay paths EXIST in v2.1.0 **except** `src/core/sanitizer/*` (missing in BOTH —
pacgate-only files). Measured upstream churn:

| Overlay file | Upstream churn |
|---|---|
| `input-box.tsx` | +2102/-195 |
| `threads/hooks.ts` | +2632/-509 |
| `en-US.ts` | **+1120/-10** |
| `zh-CN.ts` | **+1047/-10** |
| `types.ts` | +876/-5 |
| `chat-box.tsx` | +364/-81 |
| `memory-settings-page.tsx` | +17/-4 |

**Highest risk — `src/core/i18n/locales/en-US.ts`:** our overlay is `+52/-7` against
v2.0.0 but `+62/-1,127` against v2.1.0-rc0. **Copying it forward would delete 1,127
upstream locale lines.** The 17 files are copied via `cp -rv` after a sparse
`--branch v2.0.0` clone (see `deploy/build-frontend.ps1`). Move the clone branch to
v2.1.0, then **re-derive each overlay by 3-way merge** — do NOT copy snapshots forward.

Also re-check: `types.ts`, `hooks.ts`, `chat-box.tsx`, `input-box.tsx`, `env.js`,
and the sanitizer module.

---

## Gap 4 — Config schema diff

The live rendered `deer-flow-config.yaml` carries **10 top-level keys** vs the wrapper
default's **6**, so an upstream key rename lands silently in the rendered file. Diff
both against upstream `config.example.yaml` AND against the v2.1.0 breaking-change list.

---

## Gap 5 — 5 pins to bump (one unified version)

1. `deploy/deer-flow-pacgate/Dockerfile` — `FROM` digest (prefer digest over tag)
2. `.github/workflows/build-ghcr.yml` — the frontend clone `--branch` tag
3. `pacgate-ai/Cargo.toml` + `Cargo.lock`
4. `deploy/client-bundle/compose.prod.yaml`
5. `deploy/client-bundle/compose.bundle.yaml`

Use `scripts/bump-release-version.ps1 -To X.Y.Z -Preview` first — it discovers versions
rather than hardcoding and refuses to finish if pins moved but `Cargo.toml` did not.

---

## Gap 6 — Verify (nothing here is optional)

1. `scripts/audit-deer-flow-patches.ps1 -TargetRef v2.1.0` → exit 0.
2. Config schema diff (see Gap 4).
3. **Memory-lane regression** — re-run the adapter test with `PACGATE_MATTER_ID` active;
   confirm a run reaches `success` and the memory queue performs a real save
   (200 + fact readable back).
4. **Runtime proof of the patch set** — start the stack, confirm the mounted patches
   are in effect (MCP tool count + pacgate behaviour e.g. the interrupt default).
5. **Fresh-clone validation** of any install-path change.
6. Full e2e suite.

---

## Then: rebuild GHCR full stack (upstream's job)

A push to `main` builds **NOTHING** — the trigger is tags/dispatch only.

1. Merge this upgrade to `JZKK720/pacgate-ai-pr` main (via fork → PR).
2. `workflow_dispatch` with `tag=<new version>` (not a tag push — decouples published
   tag from build commit; the 0.1.14 release failed on that).
3. Verify GHCR: **all 5 images** at the new version, anonymous manifest HEAD = 200.
   Images: `pacgate-api`, `pacgate-mcp`, `deer-flow-pacgate`,
   `deer-flow-frontend-pacgate`, `ocr-service`.
4. AIPCs: `docker compose pull && docker compose up -d`; then verify `/version`,
   MCP tool count, and the memory card renders (200 on `/api/memory`).

## Traps (from prior releases)

- **Line endings:** the patch files are CRLF, upstream blobs are LF. `git merge-file`
  compares literally — LF-normalize all three inputs or you get a whole-file conflict.
- **Never copy a snapshot forward** for a patch or overlay — it silently reverts
  upstream code. Always 3-way merge.
- **Read blobs to bytes, not PowerShell strings** — em-dashes transcode and inflate
  deltas by ~30%.
- **`docker compose pull` overwrites a locally rebuilt image** with the published one —
  the fix is lost until a new version exists.
- Do NOT port CI files from the monorepo — its `build-ghcr.yml` is stale; this repo's
  workflow is authoritative.
