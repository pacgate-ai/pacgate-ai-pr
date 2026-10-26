# Sync + evaluation — upstream 0.2.6 (`06c1e4c`) into the `pacgate-ai/` subtree

**Date:** 2026-10-25
**From:** `b5fa7dd` (the 2026-10-23 sync point, still pinned to 0.2.3 images)
**To:** `upstream/main` `06c1e4c` — **three tagged releases: v0.2.4, v0.2.5, v0.2.6**
**Local baseline:** `99c6ea9` (pre-swap HEAD)

## 1. This sync is different from the last one

The 2026-10-23 sync carried **scripts and documents only** — no Dockerfile, no
application source, no pin moved, so there was nothing to pull. This one carries
**real code and three releases**, so the stack is upgraded, not just the tree.

| | 2026-10-23 sync | this sync |
|---|---|---|
| upstream delta | 3 commits, 8 files, +956 | 16 commits, 40 files, +2804/−180 |
| releases | none | **v0.2.4, v0.2.5, v0.2.6** |
| images | unchanged (0.2.3) | **0.2.3 → 0.2.6, all five** |
| Rust source | untouched | 9 crates + 1 new test |

## 2. What 0.2.4 / 0.2.5 / 0.2.6 actually fix

All three releases exist because **0.2.3 could not carry the fixes**: its tag
pointed at `d33553e` while the published package was a different image from the
local rebuild, so a `docker pull` silently reverted every fix. That is
`DEFECT-release-tag-provenance.md`, and it is why 0.2.4 exists at all.

### 0.2.4 — six fixes that were only ever built locally

| Fix | Why it mattered here |
|---|---|
| **summarization treadmill** | The "42 steps and no report" hang. `trigger=12000` sat BELOW the unremovable per-call floor (system prompt 3,220 + 45 tool schemas 11,508 = **14,728 tok**), so `_should_summarize` fired on every call including immediately after a pass. Measured on thread `d46320fd`: six passes at steps 402/410/419/428/437/446, **1,000,467 input tokens over 66 calls**, no closing message. `keep` was not the lever — replaying at keep=12000/8000/6000/4000 all still fired. Now `trigger=36000`, `keep=6000`. |
| **prompt: how to read a PDF, never `pip install`** | An offline AIPC run died on a 3.0 MB Chinese PDF. The agent HAD the `.md` and read it, then decided it needed a "real" parser: `pdfinfo` (127), `import pypdf`, `import fitz`, then `pip install pymupdf` — which retries index URLs past the **420s stream idle watchdog** and aborts the run. |
| **kb_search: empty and blocked both say why** | A lawyer asked for 互联网+/电商合规 material and got `[]` eighteen times. The tool was never broken — the matter had zero documents. But `[]` reads identically to "the firm holds no such authority", which is a factual claim the tool was not making. |
| **redactor: stop blocking on public entities + window overflow** | Firm documents were held for review over entities that are not confidential. |
| **redactor: real softmax confidence** | Model spans were gated on a hardcoded 0.85 instead of the actual confidence. |

### 0.2.5 — one fix 0.2.4 could not carry

A placeholder **shifted by an earlier redaction** was reported as residue, so any
document with a phone before a card held for review with **zero real leaks**.

### 0.2.6 — the headline

A **blocked document can be recovered by re-sanitizing it**. Before this, the
ingest guard deliberately skips rows already marked `blocked`, so a second
sanitize returned `verdict=pass, residue=none` while the document stayed blocked
forever. 0.2.6 adds an explicit, audited reopen (`REOPEN_BLOCKED_DOCUMENT_SQL`)
before the verdict.

## 3. Sync performed

Index swap, not a merge — the two histories are unrelated (different root
commits), so `git diff upstream/main..HEAD` is meaningless and a merge is
impossible.

```powershell
git rm -r --cached pacgate-ai --quiet
git read-tree --prefix=pacgate-ai/ "06c1e4c^{tree}"   # QUOTE the rev
git checkout -- pacgate-ai
```

**Byte-identity verified by tree SHA**, not per-file:

```
subtree after swap : 87d5c5cef9e23b532692ff45924d69df3486aa57
upstream 06c1e4c   : 87d5c5cef9e23b532692ff45924d69df3486aa57   ✅
```

### Local deltas: 59 files, 4 overlaps

59 files differed from `b5fa7dd`. **55 restored verbatim**; **4 overlapped**
upstream's changed set and were re-applied by hand:

| File | Resolution |
|---|---|
| `compose.bundle.yaml` | Re-added the **skills-tree mount** and the **uploads-middleware mount** on top of upstream's 0.2.6 pins. |
| `compose.prod.yaml` | Same two mounts. `name: pacgate-ai-bundle` pin survived (verified — this is the volume-safety key that a previous sync silently dropped). |
| `patches/deer-flow-prompt.py` | Kept upstream's new PDF-reading + no-`pip install` guidance **AND** the local `read_file`-first directive. The local line replaced upstream's softer "Use `read_file` tool to read uploaded files" — both say read the file, but only the local one forbids *claiming the file is inaccessible*. |
| `scripts/run-all-checks.ps1` | Kept upstream's **3 new gates** (summarization-treadmill, prompt-document-reading, kb-search-empty-signal) **and** re-added the local prompt-contract gate. |

`deer-flow-config.yaml` was **identical** to `b5fa7dd` locally, so upstream's
summarization fix applied cleanly. The local model roster is untouched — it is a
per-deployment choice, not upstreamable (user directive 2026-09-21).

Verified delta after re-application: **exactly the same 59 files** as before the
swap, no more, no fewer.

## 4. Stack upgrade

All five images pulled at 0.2.6 and verified present on GHCR before pulling:

```
pacgate-api                    0.2.6  sha256:6a79cc695e8c...
pacgate-mcp                    0.2.6  sha256:93c49607980c...
deer-flow-pacgate              0.2.6  sha256:9ba38f047541...
deer-flow-frontend-pacgate     0.2.6  sha256:34c48925a0ed...
ocr-service                    0.2.6  sha256:870a5e38bae2...
```

Recreated with `--force-recreate --no-deps` (an env-only or mount-only change is
**not** picked up by a plain `up -d`):

```powershell
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps `
  pacgate-api deer-flow deer-flow-frontend pacgate-mcp ocr-service
```

**Result:** 5/5 healthy, **0 restarts**, DB intact (**2 tenants / 5 users**),
`pacgate-db` / `pacgate-nginx` / `openviking` / all 7 `qm-*` untouched (Up 20h).

### Provenance verified independently of the gate

All five images carry the same revision label, and it is the `v0.2.6` tag commit:

```
version=0.2.6  revision=c4b32c19b00879b7569944d6ea523f0d1a4382c0   (all five)
v0.2.6 tag   → c4b32c19b00879b7569944d6ea523f0d1a4382c0
```

## 5. Live verification of the new fixes

| Fix | How verified | Result |
|---|---|---|
| summarization treadmill | `test-summarization-treadmill.ps1` (6 checks) + live container read | **PASS** — `trigger=36000`, `keep=6000`, `trim=36000`; S1 confirms trigger > floor+margin (22,728) |
| prompt: PDF reading / no pip | `test-prompt-document-reading.ps1` (5 checks) | **PASS** — `markitdown` and `pip install` guidance both present |
| kb_search empty signal | `test-kb-search-empty-signal.ps1` (5 checks) **+ live MCP call** | **PASS** — live response returns `empty_reason: no_documents` with counts and an explicit "This is NOT a statement that the firm lacks material" |
| redactor: placeholder shift (0.2.5) | **live probe** — phone BEFORE card, the exact regression ordering | **PASS** — `verdict=pass`, `redactions=1`, no false residue hold |
| redactor: public entities (0.2.4) | **live probe** — bare unlabelled ID repeated 3× | **PASS** — `verdict=pass`; the document no longer blocks at all |
| blocked-document recovery (0.2.6) | source-verified (`REOPEN_BLOCKED_DOCUMENT_SQL`) | **present** — the live probe could not exercise it because the 0.2.4 fix means the probe document no longer blocks |

Probes kept at `runtime/sync-1025/test-redactor-025-regression.ps1` and
`runtime/sync-1025/test-blocked-recovery-026.ps1`.

## 6. Gate suite

```
run-all-checks.ps1  →  ALL 52 GATES PASSED (14 live-stack gate(s) checked separately)
```

Up from 48 — the three new upstream gates plus the local prompt-contract gate.

Notable individual results:

| Gate | Result |
|---|---|
| `test-summarization-treadmill.ps1` | 6/6 — the treadmill cannot recur |
| `test-prompt-document-reading.ps1` | 5/5 |
| `test-kb-search-empty-signal.ps1` | 5/5 |
| `test-prompt-contract.ps1` | PASS — no new prompt-contract regressions |
| `test-stack-version-coherence.ps1` | 14 passed — every service runs its 0.2.6 pin |
| `test-mcp-tool-surface.ps1` | 6 passed |
| `test-document-generation-e2e.ps1` | 19 passed |
| `test-text-native-sanitize.ps1` | 59 passed |
| `test-format-coverage-e2e.ps1` | every accepted format survived upload → extract → sanitize → convert |
| `test-release-provenance.ps1` | **PASSED** — v0.2.6 identifies the c4b32c1 artifacts |

One gate is `CANNOT CHECK` (exit 2, not a failure): `test-model-picker-e2e.ps1`
needs a deer-flow credential not configured on this box.

### Two transient failures, both diagnosed rather than papered over

1. **`test-release-provenance.ps1` failed before the commit.** It compares
   against **committed** HEAD, which still held the pre-sync tree, so the 10
   changed Rust files looked like post-release drift. It resolved on commit —
   confirmed by re-running it green.
2. **It then failed twice on a registry read timeout** (20s hardcoded,
   `HttpClient.Timeout`). This is the known VPN flakiness, not a defect. Proven
   by reading the same provenance claim straight off the pulled images (§4) and
   then re-running the gate green.

## 7. Not adopted, deliberately

| Item | Why |
|---|---|
| `deploy/DEFECT-*.md` (4 new files) | Adopted — they are the evidence trail for the fixes above. |
| Local model roster changes | Per-deployment choice (user directive 2026-09-21). Upstream's roster is untouched by this sync. |
| `pacgate-ai-assets/` | Still deferred — own repo, unpushed work. |

## 8. Restore points

- Pre-swap HEAD: `99c6ea9` — `git checkout 99c6ea9 -- pacgate-ai` restores the
  entire subtree as it was.
- Config backup: `runtime/backup-pre-0.2.6-20261025/` — `.env`,
  `deer-flow-extensions-config.json` (30 MCP servers), `deer-flow-config.yaml`,
  both compose files, `ollama-models.txt`.
- Local delta snapshot: `runtime/sync-1025/local-preserve/` (59 files).
- Both sides of the 4 overlaps: `runtime/sync-1025/LOCAL-DELTA-overlaps.diff`
  and `UPSTREAM-DELTA-overlaps.diff`.

## 9. Rollback

```powershell
cd C:\Users\pacga\github-pr\pacgate-law
git checkout 99c6ea9 -- pacgate-ai
cd pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps `
  pacgate-api deer-flow deer-flow-frontend pacgate-mcp ocr-service
```

The 0.2.3 images are still local, so this is a fast rollback. The DB is
untouched by the upgrade (no migration ran), so no data step is needed.

---

# Addendum — second sync, same day: upstream `337fb9d` (memory lane)

**Date:** 2026-10-25 (later)
**From:** `06c1e4c` (the sync above)
**To:** `upstream/main` `337fb9d` — 2 commits, **no new tag**

## A1. No image to pull

Unlike the 0.2.6 sync, this delta carries **no release**. It is a bind-mounted
patch plus a benchmark report, so the stack needed only a `deer-flow` recreate —
no pull, no pin change, no rebuild.

| File | Kind |
|---|---|
| `deploy/client-bundle/patches/deer-flow-memory-storage.py` | new patch (+266) |
| `deploy/client-bundle/compose.bundle.yaml` | +5 (the mount) |
| `deploy/client-bundle/compose.prod.yaml` | +5 (the mount) |
| `scripts/test-memory-lane.ps1` | +67 (runtime assertions) |
| `deploy/BENCHMARK-2026-10-25-0.2.6.md` | docs (+270) |

## A2. The defect: a compliance failure wearing a healthy face

`get_memory_storage()` wrapped instantiation in a bare `except Exception` and
substituted `FileMemoryStorage`, logging at error level only.

On this stack that is not a cosmetic fallback:

- `PacgateMemoryStorage` writes matter memory **through pacgate-api**, so it
  inherits the sanitization gate.
- `FileMemoryStorage` writes **plaintext JSON to the local filesystem** —
  outside the gate, outside the audit log, invisible to every health check.

The stack would report healthy while the memory lane had quietly left the
sanitized path.

The fallback is reachable by a plain **initialization-order mistake**: calling
`get_memory_storage()` before `get_app_config()` reads the module-level
default `MemoryConfig()`, whose `storage_class` *is* `FileMemoryStorage` —
so the configured class is never even attempted.

The patch falls back **only when nothing was configured**. A configured class
that cannot be built now raises.

## A3. Sync

Index swap, byte-identity verified by tree SHA:

```
subtree after swap : 085b5a9481bb8df706c4363367d2b8c8907acff0
upstream 337fb9d   : 085b5a9481bb8df706c4363367d2b8c8907acff0   ✅
```

59 local deltas, **2 overlaps** (both compose files). 57 restored verbatim; the
two compose files had the skills-tree and uploads-middleware mounts re-applied on
top of upstream's new memory-storage mount. Post-merge delta is the same 59
files.

## A4. Verified in both directions

Before recreating, confirmed the configured adapter imports and instantiates
cleanly — otherwise the stricter patch would turn a silent degradation into a
startup failure.

After recreating (`runtime/sync-1025b/test-memory-storage-patch.ps1`):

| Assertion | Result |
|---|---|
| A. after `get_app_config()`, `storage_class` is not the default | **PASS** — `pacgate_deerflow_adapter.storage.PacgateMemoryStorage` |
| B. a broken configured class **raises** | **PASS** — `REFUSING to fall back to FileMemoryStorage - that would move matter memory outside the pacgate-api sanitization gate without any visible failure` |
| C. the real configured class still builds | **PASS** — `PacgateMemoryStorage` |

### A probe mistake worth recording

My first probe called `get_memory_storage()` **without** `get_app_config()`
first and got `FileMemoryStorage`. That looked like a live degradation but was
the probe **reproducing the initialization-order bug** the commit describes. The
patch deliberately still falls back when `storage_class` *is* the default, so a
fresh install with no config keeps working. The probe was wrong, not the patch.

## A5. Gates

```
run-all-checks.ps1  →  ALL 52 GATES PASSED
```

`test-memory-lane.ps1` now includes upstream's two runtime assertions and both
pass:

```
RUNTIME: the silent fallback is closed
  PASS  the mounted memory storage carries the refusal patch
  PASS  a broken configured storage RAISES instead of degrading to FileMemoryStorage
```

## A6. One restart, and it was not a crash

`pacgate-api` showed `RestartCount=1`. Investigated rather than assumed:

- `ExitCode=0`, `OOMKilled=False`
- `FinishedAt` 03:07:49.66, `StartedAt` 03:07:50.11
- **every** container on the host started at 03:07:44

So this was a **host/Docker restart**, not a crash. `pacgate-api` exited 0
because the DB was not yet accepting connections, and Docker restarted it. The
log line is explicit: `Failed to connect to database` at 03:07:49, then
`Connected to database` on the next start.

The 500s in the log were transient negative-path tests during the gate run — the
last one is at 03:54:48, inside the run that passed 52/52. Confirmed healthy
afterwards: login 200, `/api/matters` 200, `/api/workflows` 200.
(`/api/agents` 404 is expected — that gallery belongs to deer-flow, not
pacgate-api.)

## A7. Pushed

`fork/aipc1/v0.2.6-sync` → `2b1f64e`. Credential gate: 0 carrier blobs across
1,893 tracked files.
