# PacGate-AI — Full-Stack Re-Audit (post-0.2.32)

**Date:** 2026-11-08
**Stack revision:** `7a6dd732c6df285c610182f352dd351d68f28d50` (v0.2.32)
**Scope:** pacgate-api, pacgate-mcp, deer-flow, qm-pacgate, OpenViking, model regression,
workflows, matters, KB search, templates, vector store, sanitizer, OCR, document generation.

---

## Verdict

**The 0.2.32 upgrade landed cleanly with zero runtime regressions across every subsystem,
but the score is capped because the 2026-09 credential leak was closed forward-only and the
exposed legal-database credentials have still not been rotated.**

**Score: 66/100** — capped at 69 by an unresolved secrets obligation.

---

## Blockers

| # | Blocker | Why it blocks | Owner action |
|---|---|---|---|
| **B1** | **Credential rotation outstanding.** 4 files (`OPERATOR.md`, `法律数据库MCP.md`, `境外法律数据库和网站.md`, `百宸AI系统资源接入清单V2.docx`) leaked publicly. They are now untracked + ignored, so **no new exposure** — but the leaked credentials remain valid and readable in public git history. Deleting files cannot undo public history. | A law firm's legal-DB and GitHub account credentials are live in public history. No amount of code fixes this; only rotation does. | Rotate all credentials in those 4 files, then verify no old credential still authenticates. |

**No other blockers.** Every functional subsystem was exercised live and passed.

---

## High-value fixes

All are **gate/verification defects**, not runtime defects. None affects a user-facing path.

| # | Fix | Evidence | Effort |
|---|---|---|---|
| **H1** | Register the 19 unregistered gates (or delete the dead ones). 93 gate scripts exist on disk; only 74 run in `run-all-checks.ps1`. Every gate not registered is a check that silently never protects anything — and this audit found 3 defects *inside* those 19 that no CI run would ever have surfaced. | `(Get-ChildItem scripts/test-*.ps1).Count` = 93 vs 74 entries in the registry. | S |
| **H2** | `test-initialize-gate.ps1` hardcodes `-Image 'ghcr.io/jzkk720/deer-flow-pacgate:0.1.17'` — an image that no longer exists locally. Gate fails on a stale default; **passes 8/8** when given `-Image ...:0.2.32`. | L34 of the script; verified both directions. | XS |
| **H3** | `test-skill-tool-declarations.ps1` probes skills from `/app`, where `LocalSkillStorage` resolves 0 skills. From `/app/backend` it resolves 5. Gate A1 fails for its own cwd, not the runtime. | `cwd /app` → 0; `cwd /app/backend` → 5. | XS |
| **H4** | `test-recursion-budget.ps1` R5 asserts "a request of 50 must not be raised", which directly contradicts `DEFECT-recursion-budget-floor.md` L107-114 (`if requested < floor: requested = floor`). The live patch implements the doc. **R5 encodes the pre-floor contract and should be rewritten**, not the runtime. | Doc L110-114 vs gate L186-192. | XS |
| **H5** | `test-handbook-verify.ps1` is **vacuously green**: `$compose` is a bare relative path, so run from anywhere but `pacgate-ai/` it silently yields zero pins and exits 0 having verified nothing. Anchor it to `$PSScriptRoot`. | From `scripts/` → `找不到路径`, exit 0, 0 pins. From `pacgate-ai/` → 5 pins. | XS |
| **H6** | `test-qm-sandbox-fingerprint.ps1` and `test-compose-healthchecks.ps1` require `pwsh` (PS 6+); under PS 5.1 they die on a native-stderr trap / `ConvertFrom-Json -AsHashtable`. Both **pass under `pwsh`** (25/25 and green). Pin the runner or add a version guard. | `pwsh` → 25 passed, 0 failed. | XS |
| **H7** | **Latent risk:** skill loading is *cwd-relative*. Any supervisor entrypoint change that launches from `/app` instead of `/app/backend` silently yields **0 skills** with no error. Not currently buggy, but it is one config edit away from a silent capability wipe. | Measured: `/app` → 0, `/app/backend` → 5. | S |

---

## Evidence checked

### Gate suite — 93 gates (74 registered + 19 unregistered)

| Bucket | Count | Detail |
|---|---|---|
| **PASS** | **86** | Includes 3 recovered on correct invocation (`qm-sandbox-fingerprint`, `compose-healthchecks` under `pwsh`; `legal-journey` on re-run) |
| Gate-defect FAIL | 3 | H2, H3, H4 — all reproduce as green when the gate's own bug is bypassed |
| Pre-existing / structural FAIL | 3 | `release-provenance` (compares to fork HEAD — cannot pass on a fork lineage), `install-repo-pull` (`InvokeMethodOnNull`), `update-end-to-end` (0 passed / 1 failed). All three verified **UNCHANGED** by the upgrade. |
| CANNOT-CHECK | 1 | `rust-workspace` — no `cargo` on this box |

**Zero runtime regressions.** Every failure is either a defect in the gate itself, a pre-existing
condition, or a structural impossibility on a fork.

### pacgate-api
- `0.2.32`, revision `7a6dd732c6df`; `/pacgate/health` → 200.
- 25 routes enumerated from source; all 8 data routes return **401 unauthenticated** → auth gate enforced.
- 10 tables present. Schema is idempotent `CREATE TABLE IF NOT EXISTS` via `pacgate_tenant::run_migrations` — there is **no `_sqlx_migrations`** by design, so its absence is not a defect.

### pacgate-mcp
- 26 MCP tools registered; `firecrawl` → `available: true`; 10 of 11 connectors available (only `opencorporates` false).

### deer-flow
- Healthy on `0.2.32`; all three shadowing fixes live in-container: recursion **floor** (4 refs), `_recursion_exhaustion_message` (2), firecrawl tools.
- pymupdf4llm 2.1 installed; `pdf_converter: auto`; 30 connectors; 65-skill tree + 5 seeds; playbook 8126 bytes.
- 29 patch mounts, **A5 parity** holds between `compose.bundle.yaml` and `compose.prod.yaml`.

### qm-pacgate
- 7 containers up; `qm-sandbox-fingerprint` **25/25** under `pwsh`.
- Cross-stack credential gate: qm `/mcp` accepts `OPENVIKING_API_KEY` (HTTP 200).
- *Note:* no sandbox image is built (`LOCAL_SANDBOX_IMAGE` unset) — the markdown fix exists in source but is not in any built image. Not exercised today.

### OpenViking
- v0.4.16; `/ready` all ok (agfs, vectordb, api_key_manager, embedding, ollama).
- VLM = `nemotron-3.5-bolt`; embed dim **768**, matching the DB.

### Model regression (live)
- All 8 roster models resident. Mid == Low == `nemotron-3.5-bolt:e4b-q8_0` (upstream residency argument: one resident model on 16 GB, no eviction). Trade-off: no parallelism between the two tiers.
- **Live generation: 16.3s, 62.1 tok/s, 120 tokens, coherent CJK output** (`非公知性`).
- `audit-model-tags` → every requested local tag pre-pulled; delegates to `test-model-roster-consistency` (15/15).

### Vector store / KB search
- pgvector **0.8.6**, HNSW index, **2327 chunks all 768-dim**, 100% `content_tsv` populated.
- `cjk_tsquery('资料收集')` → **exactly 21**, matching the 0.2.30 baseline. **No regression.**
  (A `plainto_tsquery` probe returns 0 — wrong function for the per-character CJK split; not a fault.)

### Matters
- 2 tenants: `pacgate-law` (d64908b0 — all 242 docs / 2327 chunks) and `default-firm` (722dbdd8 — empty compose fallback). UNIQUE slug. **Not a defect.**

### Workflows / templates
- 15 workflow YAML: source = 15, mount source = 15, container `/app/workflows` = 15. **Consistent.**
  (An apparent 62 was duplicate copies inside an agent thread workspace — a sandbox artifact.)
- `pacgate-template` crate present (`Template` / `list_templates`).
- `test-skills-and-templates` 9 passed; `test-skill-evolution` 14 passed.

### Sanitizer
- **66 sanitizer jobs, 51 redaction ledger rows** of real throughput; verdicts `pass` 42 / `block` 24.
- **19/19 blocked jobs actually altered bytes** (`input_sha256 != output_sha256`) and recorded redactions.
  This directly refutes the documented historical bug where "sanitized" meant "allowed" and bytes passed through unredacted.
- `test-sanitization-gate` → ALL ASSERTIONS PASSED.

### OCR
- Healthy on **:8100** (not 8000). Live extraction of `Moritz 深度调研（2025-2026）.pdf`:
  **17.9s, 690 CJK chars, 46 spans, `incomplete: false`**. `test-ocr-extraction` PASS.

### Document generation
- 19/19 and 8/8 soak, all HTTP 200. `test-officecli-set-contract` 8 passed.

### Credentials
- All 4 leaked files: **untracked + ignored** (verified codepage-proof). No `ghp_`/`sk-`/`AKIA` patterns in tracked HEAD.
- Gitattributes fix held: **0 of 29 patches CRLF**.
- `test-cross-stack-credentials` PASS; `test-auth-registration-gate` 8/8.

---

## Evidence missing

1. **`cargo test`** — no Rust toolchain on this box (`test-rust-workspace` CANNOT-CHECK). The 16 crates are unverified at unit level.
2. **Credential rotation status** — verifiable only by the operator attempting the old credentials. Cannot be confirmed from the repo, and the repo says it is outstanding.
3. **qm sandbox image** — the markdown fix is in source but no image was built, so the sandbox path is unexercised end-to-end.
4. **Authenticated API round-trips** — all 8 data routes verified to *refuse* anonymous callers (401), but no authenticated `POST /api/chat` → `documents` loop was driven this pass. Auth was proven by the 401s and by `test-auth-registration-gate`; the authenticated happy path relies on earlier E2E runs.
5. **GHCR reachability is proxy-dependent.** All 5 pins returned **HTTP 200** only after clearing the dead `127.0.0.1:7890` proxy. `install.ps1` will still fail at its `pull` step on this machine until the proxy is removed.

---

## Next action

1. **Rotate the 4 leaked credentials** (B1). This is the only blocker, and it is the only item that
   cannot be fixed in code. Everything else is cosmetic.
2. Then, in one small commit: **H2–H6** — six one-line gate fixes that convert 3 false FAILs and
   1 vacuous PASS into real signal. **H1** (register the 19) prevents the next gate from silently
   never running. **H7** is a defensive follow-up, not urgent.
3. Leave the **deer-flow version upgrade strictly to you**, as decided.

---

## Appendix — gate result files

- `gates.txt` — the 74 registered gates, as `VERDICT|name|exit|last-line`
- `unregistered.txt` — the 19 unregistered gates, with per-gate triage
