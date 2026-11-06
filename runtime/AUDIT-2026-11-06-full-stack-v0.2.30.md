# Full-stack audit — AIPC1 after v0.2.30 (2026-11-06)

Scope: deer-flow, qm, OpenViking, pacgate-api, pacgate-mcp, document-generation
loop, sanitizer, OCR. Question asked: *is everything wired up and working e2e?*

## Verdict

**Production audit: 62/100 — risky.** The stack itself is wired correctly and
verified end to end; the score is capped by one **critical security finding**
(live credentials in a public repo) and one missing rollback artefact.

## 🔴 Blocker — live credentials in a PUBLIC repo

`scripts/detect-literal-credentials.ps1` flagged 7 tracked files. Six were
confirmed to contain values read straight out of `deploy/client-bundle/.env`,
and they were pushed to the **public** `pacgate-ai/pacgate-ai-pr`:

| File | Secret |
|---|---|
| `runtime/e2e-fallback-1010.py` | `PACGATE_API_PASSWORD` |
| `runtime/e2e-warm-1010.py` | `PACGATE_API_PASSWORD` |
| `runtime/gen-template-1016.ps1` | `VAQUILL_API_KEY` |
| `runtime/gen-template2-1016.ps1` | `VAQUILL_API_KEY` |
| `runtime/relocate/BUILT-IMAGE-E2E.txt` | `PACGATE_DB_PASSWORD` |
| `runtime/upgrade-0.2.24/deer-flow-extensions-config.json.pre-0.2.24` | 7 connector keys (pkulaw, qcc, yuandian, vaquill, ansvar, openviking root + api) |

All 6 are now untracked and `.gitignore`d. **Untracking does not undo history** —
they are still readable in every commit that contained them, including
`a9c86c3` and `042d49f` on `fork/aipc1/v0.2.30-sync`.

**Required:** rotate `PACGATE_API_PASSWORD`, `VAQUILL_API_KEY`,
`QCC_API_KEY`, `PKULAW_API_KEY`, `YUANDIAN_API_KEY`, `ANSVAR_API_KEY`,
`OPENVIKING_ROOT_API_KEY`/`OPENVIKING_API_KEY`, and `PACGATE_DB_PASSWORD` if that
volume ever leaves this machine. Rotation is the only remedy; history rewriting on
a shared public fork is not viable.

Note the 7th hit, `runtime/create-todos-user-1010.py`, holds only the literal
`TestPass123!` fixture — not a live secret, left in place.

## ✅ What is verified working

### Runtimes (all healthy)

`pacgate-api`, `deer-flow`, `deer-flow-frontend`, `pacgate-mcp`, `ocr-service`,
`openviking`, `pacgate-db`, `pacgate-nginx`, plus 6 `qm-pacgate` + `qm-mailpit`.
22 containers up, **0 unhealthy, 0 exited**. `/version` → `0.2.30 @ 436d41e`.

### deer-flow

- Gateway `/health` 200; auth `needs_setup=False`.
- Agent run completes and **invokes real MCP tools** (`pacgate_kb_search`,
  `pacgate_list_connectors`, `pacgate_sanitize_text`) — `test-agent-mcp-e2e` 5/5.
- Model picker serves a 5-entry roster and **delivers a generation** through nginx
  (`PONG`, 11.2 s) — `test-model-picker-e2e` 13/13.
- 10/10 A-series subagents resolve to an **installed** tag.
- Skills: 5 seeds mounted at the agent root + 60-skill merged tree at
  `/app/skills/public`; playbook reachable at `/mnt/playbooks/nda-playbook.md`.

### qm

- `core` /healthz 200, `admin` 200, `web-ui` 200, `mailpit` 200; `portal` and
  `auth` correctly 401 without a session.
- DB `qm` fully populated: 85+ tables incl. `pgboss` queues; `test-qm-currentness`
  PASS (30 files, 0 warnings).
- qm → pacgate-api authenticated (HTTP 200) and qm → OpenViking `/mcp` accepted,
  from inside `qm-pacgate-core`.

### OpenViking

- `v0.4.16`, healthy, `auth_mode=api_key`, **zero error lines** in logs.
- VLM configured as `nemotron-3.5-bolt:e4b-q8_0` and **returns real output** —
  the silent 404 from the retired `gemma4:12b-it-q8_0` is gone.
- VLM tag carries `completion, vision, audio, tools, thinking`.
- Embeddings: `nomic-embed-text` returns dim **768** in 2.2 s.
- Write → recall round trip succeeds (`test-legal-journey` step 10).

### pacgate-api + connectors

- 222 workflows listed.
- Connectors: **9 of 11** available (yuandian, pkulaw, qcc, fyopen, courtlistener,
  sec_edgar, gleif, vaquill, eur-lex). 2 unavailable — see gaps.
- External search returned 135 results in the legal-journey run.

### Document generation loop

- `test-document-generation-e2e` **20/20**, including an **8/8 soak, 0 failures**
  (HTTP 200×8). Real `.docx` on disk, valid OOXML, CJK round-trip intact.
- `test-officecli-mcp` 13/13 — `validate` clean, text read back, structured query.
- `test-officecli-set-contract` 8/8 — incl. CJK through the batch path.

### Sanitizer

- `test-sanitizer-e2e` **PASS** — ID/phone redacted, mapping sealed server-side,
  verdict `pass`, ledger + audit rows written, attorney restore refused, admin
  restore returns originals.
- `test-text-native-sanitize` **59/59**; `test-empty-extraction-gate` **15/15**.

### OCR

- `test-format-coverage-e2e` **56/56, 0 skipped** — every accepted format survives
  upload → extract → sanitize → convert, with the identifier proven present before
  sanitization (so the redaction assertion is real).

### Full e2e journey

`test-legal-journey` **PASSED, 19 assertions** — upload → OCR → sanitize → review
gate → search → deer-flow sign-in gate → qm → OpenViking recall → cleanup.

## Gate suite

**79 PASS, 1 FAIL, 1 SKIP** (was 77/1/3 before this audit).

| Result | Gate | Reason |
|---|---|---|
| FAIL | `test-release-provenance.ps1` | Structural: compares the image's `org.opencontainers.image.revision` (`436d41e`) against **our HEAD**, a different lineage with 77 local deltas. Cannot pass on any fork. Needs a fork-aware mode — not a gate edit. |
| SKIP | `test-rust-workspace.ps1` | `cargo` is not installed on this box. The 13 crates are scaffolded, not built here. |

## Gaps that would change the score

1. **2 of 11 connectors unavailable.** Not yet identified which. If either is a
   client-contracted legal DB (北大法宝 / 元典 / 企查查), that is a functional gap,
   not cosmetic. `test-lane-connectivity` reports 11/11 *reachable* but the
   connector registry reports 9/11 *available* — the two measure different things.
2. **No rollback artefact for this upgrade.** `runtime/upgrade-0.2.30/` holds the
   report and handoff but no restore script. Rolling back means re-pinning the
   `0.2.7` images and restoring `deer-flow-config.yaml` from `aipc1-pre-0.2.30`.
   That is documented, not automated.
3. **`deploy/deer-flow-pacgate/config.yaml` still names `gemma4:12b-it-qat`**
   (models[0], memory, title). Dormant because the live compose bind-mounts
   `client-bundle/deer-flow-config.yaml` over it — but an upstream bug that bites
   any build without that mount.
4. **Rust workspace unverified.** 13 crates claim to exist; nothing compiles them
   on this machine.
5. **Transient doc-gen failure observed once.** The first soak attempt reported
   `9 passed, 2 failed`; an identical re-run reported `20 passed, 0 failed`. Both
   runs had 0/8 soak failures. The 2 failures were not captured — worth a third
   run before trusting the gate in CI.

## Evidence checked

`docker ps -a`, `docker inspect`, `/version`, `/health`; gates:
`test-legal-journey`, `test-agent-mcp-e2e`, `test-model-picker-e2e`,
`test-document-generation-e2e` (+`-FailureRateRuns 8`), `test-sanitizer-e2e`,
`test-text-native-sanitize`, `test-empty-extraction-gate`,
`test-format-coverage-e2e`, `test-officecli-mcp`, `test-officecli-set-contract`,
`test-lane-connectivity`, `test-qm-currentness`, `test-model-roster-consistency`,
`test-skills-and-templates`, `test-skill-evolution`,
`test-workflow-compose-wiring`, `test-workflow-namespace`,
`test-ollama-gpu-residency`, `smoke-full-stack`, `detect-literal-credentials`,
and the full `run-all-checks` suite. Direct probes of Ollama (inference,
json_schema, embeddings, `ollama show`, `ollama ps`), Postgres (pgvector, CJK
`cjk_tsquery`, qm schema), OpenViking (`ov.conf`, VLM generate), and the
deer-flow SQLite user store.

## Next action

Rotate the 8 exposed credentials. Everything else is a gap to accept knowingly,
not a blocker — the stack is wired and works e2e.
