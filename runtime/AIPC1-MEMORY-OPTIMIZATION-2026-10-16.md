# AIPC1 Memory-Wall Optimization — Root Cause, Validation, Fix

**Date**: 2026-10-16 · **Machine**: PACGATE-AI01 (AIPC1) · **Stack**: v0.1.31 (all 5 GHCR-pinned images)  
**Method**: systematic-debugging Phase 1 evidence → Phase 2 pattern → Phase 3 hypothesis+test → Phase 4 fix+verify  
**Symptom reported**: "we hit the memory wall every prompt when deer-flow starts its multimodal sessions; CPU hits 31 GB RAM; the 16 GB dGPU fits our 12B local model; our LLM is cloud deepseek-v4.1-flash"

---

## 1. Executive summary

The memory wall is **not** caused by deer-flow, by the containers, or by the cloud model. It is caused by **one Ollama configuration fact**: the local `gemma4`/`qwen3.8` tags declare a **262144-token context**, and Ollama 0.40.5 *auto-fits the runner up to that declared maximum*. A per-request `num_ctx` is ignored outright; `OLLAMA_CONTEXT_LENGTH` is a server-wide default that applies only after a restart (see the correction in §2).

At 262144 the KV cache does not fit in the 16 GB card, so Ollama splits the runner **across CPU + GPU**. The GPU keeps a slice; the rest of the *weights* get CPU-mapped **and** ~8.5 GB of KV lands in host RAM. `llama-server` then commits **18–27 GB**, host free RAM falls to 0.5–1.2 GB, and every subsequent prompt pays page-thrash + queueing. That is the wall.

**Fix (verified)**: bake the context ceiling into the tag itself — `ollama create` derivatives with `num_ctx` set. The weights, vision projector, tool-calling and JSON-grammar behaviour are unchanged; only the KV ceiling moves.

| Model | Before (262144) | After (capped) |
|---|---|---|
| `gemma4:12b-it-q8_0` → `gemma4-legal:12b-chat` (131072) | **2% / 98%** CPU/GPU · commit **20 941 MB** · host free **1.2 GB** · cold **165–197 s** | ✅ **100 % GPU** · commit **12 972 MB** · host free **9.7 GB** · cold **20 s** |
| `qwen3.8:27b-mtp-q4_K_M` → `qwen3.8-legal:27b-mid` (32768) | **62% / 38%** CPU/GPU · commit **18 135 MB** · host free **0.50 GB** | **30% / 70%** CPU/GPU · commit **13 959 MB** · host free **4.4 GB** |

**Whole-system result after the fix** (deer-flow's own `/v1` call path, 256-token completion):

| Metric | Before | After |
|---|---|---|
| Host free physical RAM | 1.16 – 1.28 GB | **7.79 GB** |
| Commit charge | 49.8 / 65.1 GB (76.5 %) | **42.2 / 65.1 GB (64.9 %)** |
| `llama-server` working set | 16 170 MB | **12 533 MB** |
| Runner placement | 2 %/98 % CPU/GPU | **100 % GPU** |
| Cold prompt → response | 165–197 s | **20–63 s** |

---

## 2. Why the obvious fixes do NOT work

This was verified, not assumed:

1. **Per-request `num_ctx`** — ignored. A request with `options.num_ctx = 16384` still produced a runner with `-c 262144` (`ollama ps` → `CONTEXT 262144`).
2. **`OLLAMA_CONTEXT_LENGTH`** — server-wide; honoured **after a server restart**, but *not* per-model. The first pass wrongly reported "not applied on those routes" (the value was not in the state of the server that served the request, so the test was confounded — see §2). Not used as the fix because this box needs `131072` for gemma4 and `32768` for the 27B, and because it changes nothing until the server restarts.
3. **OpenAI-compat (`/v1/chat/completions`)** — deer-flow's path. Auto-fits to 262144.
4. **Native (`/api/chat`)** — openviking's VLM path and pacgate-api's tier path. *Also* auto-fits to 262144.

Because **all four lanes** converge on the declared 262144, and because a tag cap is
route-independent while the alternatives are not, **the cap must live in the tag**.

### Correction to the original claim about `OLLAMA_CONTEXT_LENGTH`

The first pass reported that `OLLAMA_CONTEXT_LENGTH` is "not applied on those routes".
**That was confounded and is corrected here.** It is a **server-wide** default and it
*is* honoured once `ollama serve` is restarted with it — observed later the same evening:
server start 21:38 with the value persisted, runner came up `-c 131072`, and the
scheduler logged `system_free="3.7 GiB"` without escalating. The earlier `32768` test
returned `-c 262144` because the value was not in the state of the server that served
the request.

It is still **not** the right lever, for three reasons:

1. It is **global** — it cannot differ per model. This box needs `131072` for gemma4 but
   only `32768` for the 27B Mid tier; one value cannot express both.
2. It is **invisible state** — it silently does nothing until the server restarts, which
   is the same class of latent misconfiguration that produced the original bug.
3. It does **not** reach a `:cloud` tag or protect a lane that pins its own context.

The tag cap is per-model, route-independent, and was verified 100 % GPU at
`num_ctx` **32768 / 65536 / 98304 / 131072 / 196608** regardless of env state.
`OLLAMA_CONTEXT_LENGTH=131072` is still set as a belt-and-braces default.

---

## 3. Evidence trail (Phase 1)

| # | Finding | Source |
|---|---|---|
| 1 | Box is at the wall **at idle, before deer-flow**: free physical **1.28 GB** of 31.12 GB | `Win32_OperatingSystem` |
| 2 | `llama-server` runtime args: **`-c 262144`**, `--mmproj` (vision), `--cache-type-k/v q8_0`, `-np 1` | `Win32_Process.CommandLine` |
| 3 | `ollama ps` → `gemma4:12b-it-q8_0 … **2%/98% CPU/GPU** … CONTEXT 262144` | `ollama ps` |
| 4 | Real VRAM = **15.98 GB** (RX 7600 XT); the `Win32_VideoController.AdapterRAM` 4 GB reading is the known 32-bit wraparound artefact | registry `HardwareInformation.qwMemorySize` |
| 5 | llama.cpp breakdown: `load_tensors: ROCm0 model buffer size = 11613 MiB`; `CPU_Mapped model buffer size = 1247 MiB`; `KV buffer size = 2176 MiB` (8 global layers) + `242 MiB` (40 SWA layers) | `%LOCALAPPDATA%\Ollama\server.log` |
| 5b | **First pass misread this:** setting `OLLAMA_CONTEXT_LENGTH=32768` appeared not to apply (`-c 262144`). It is a server-wide default that only takes effect after `ollama serve` restarts — a later restart at 21:38 produced `-c 131072` and `offloaded 49/49 layers to GPU`. The claim is corrected in §2; the fix does not depend on it | `server.log` at 21:54 |
| 6 | gemma4 arch confirms the split: `n_swa = 1024`, `is_swa_any = 1`, and `n_head_kv` alternates **8 … 1** — 8 global-attention layers whose KV grows linearly with context | `server.log` `print_info` |
| 7 | `llama-server` **priv = 20 941 MB** while VRAM dedicated = 16 269 MB → ~8.5 GB is spilled host KV/mapped weights | `Get-Process` + `\GPU Adapter Memory` |
| 8 | Scheduler eviction confirms the prediction model: `predicted="23.0 GiB" predicted_num_ctx=262144 … available="8.2 GiB"` (9 evictions in 3 days) | `server.log` `sched.go:602` |
| 9 | llama.cpp **prompt cache enabled, size limit 8192 MiB** + **context checkpoints max=32** → additional host-RAM allocators | `server.log` |
| 10 | **No `.wslconfig` exists** → Docker/WSL keeps its 16 GB default while **27 containers** run | filesystem probe |
| 11 | 26 running containers total only **~4.3 GB** — they are **not** the wall | `docker stats --no-stream` |
| 12 | deer-flow today: lead agent = `deepseek-v4.1-flash-cloud`, but **`/v1/chat/completions` to `host.docker.internal:11434` still runs** (memory updater, summarizer, title, VLM, workflow tiers) | `docker logs deer-flow` |
| 13 | openviking VLM uses `api_base` **without** `/v1` (native route); PACGATE_MODEL_* feed pacgate-api tiers | `.env` / `compose.bundle.yaml` |
| 14 | Controller experiment: a plain `/api/chat` call with **no** `num_ctx` → runner `-c 262144`, `2%/98%` | live test |

### The cost model (from first principles, confirmed by the log)

KV bytes ≈ `ctx × n_layer_global × n_head_kv × head_dim × K-bytes × 2 (K and V)`

- gemma4 has **8 global layers**, `n_head_kv = 8`, `head_dim = 512`.
- At **q8_0** (1 byte/element, plus block scales ≈ 1.0625): 8×8×512×1 × 2 = **65 536 B/token** → 262144 × 65 536 ≈ **16.3 GiB** … but the log also shows a `242 MiB` SWA component. In practice llama.cpp allocated **2176 MiB for the 8 global layers at 262144**, i.e. **8 704 B/token** for that group — so the *empirical* slope is what a fix must respect, and it is linear.

Empirical fit from the sweep (global-attention KV, MiB):

| `num_ctx` | KV (global) | + weights (11 613) + compute (838) | Fits 16 GB? |
|---|---|---|---|
| 262144 | 2 176 | 14 627 | ❌ total commit 20 941 MB (spill) |
| 131072 | 1 088 | 13 539 | ✅ 100 % GPU |
| 65536 | 544 | 12 995 | ✅ 100 % GPU |
| 32768 | 272 | 12 723 | ✅ 100 % GPU |

---

## 4. Why 131072 is the chosen ceiling

- The base tag's declared 262144 does **not** fit; moving down to 131072 was verified **100 % GPU** and reclaimed **~8.5 GB**.
- 131072 is **>3× deer-flow's 40000-token auto-escalation threshold**, so no legitimate conversation loses headroom. The 2026-10-10 E2E that peaked at **61 413 input tokens** is comfortably inside it.
- Note gemma4's tokenizer counts ≈1.9× more tokens than nemotron for the same text (61 k vs 32.7 k in that E2E) — this is why 131072, not 65536, is the safe choice.
- 196608 was *also* verified to fit (VRAM 15 621 MiB, host free 8.79 GB), but it leaves only ~0.4 GB of VRAM headroom for the **other** lanes that share the card (openviking VLM, ocr-service, the 890M iGPU's shared surface). 131072 leaves ~0.8 GB and is the better risk/benefit point.

---

## 5. What was changed

All paths are under `pacgate-ai/`. Everything is **LOCAL-ONLY** — do **not** upstream (user directive 2026-09-21/10-09 for roster changes).

| File | Change |
|---|---|
| `deploy/client-bundle/deer-flow-config.yaml` | All 4 local roles (chat, memory, summarizer, title) now point at **`gemma4-legal:12b-chat`**. One shared tag ⇒ zero VRAM swap between chat and background roles. Block comment records the root cause + measurements. |
| `deploy/client-bundle/.env` | `PACGATE_MODEL_MAIN`/`_LOW` → `gemma4-legal:12b-chat`; `PACGATE_MODEL_MID` → `qwen3.8-legal:27b-mid`; openviking `vlm.model` → `gemma4-legal:12b-chat`. `.env` wins over the compose `${VAR:-default}`. |
| `deploy/client-bundle/ollama-models.txt` | Declares both derivative tags (so config refs resolve) with a comment explaining they are *created*, not pulled. |
| `deploy/client-bundle/install.ps1` | Pull loop now materialises the two derivatives via `ollama create` instead of `ollama pull` (a pull on a derivative returns HTTP 404). Behaviour for every other entry is unchanged. |
| `deploy/client-bundle/ensure-context-capped-model.ps1` | **New.** Idempotent creator for both capped tags; supports `-Target/-Source/-NumCtx` for one-off use. Syntax-checked and re-run clean. |
| `scripts/audit-model-tags.ps1` | Now reads `deploy/client-bundle/.env` as a tier source. Without this the guard reported a **false** "pre-pulled but never requested" for the capped tags — the exact drift class it exists to catch. |
| Ollama User env | `OLLAMA_CONTEXT_LENGTH=131072`, `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_NUM_PARALLEL=1` (KV type `q8_0` and keep-alive `10m` were already set). Set for consistency; the durable lever is the tag. |

**Applied to the live stack** (no `pacgate-db` impact):

```
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api openviking
docker compose -f compose.bundle.yaml restart deer-flow
```

Confirmed in the running containers: `PACGATE_MODEL_MAIN=gemma4-legal:12b-chat`, `PACGATE_MODEL_MID=qwen3.8-legal:27b-mid`, `VLM model = gemma4-legal:12b-chat`, and the connector file **byte-identical to its backup** (the AGENTS.md connector-wipe hazard did not trigger — see §6b for the exact 30-configured / 18-enabled split).

---

## 6. Verification (Phase 4)

| Check | Result |
|---|---|
| Runner placement, chat tag | ✅ `100% GPU`, `CONTEXT 131072` |
| Runner placement, 27B Mid tag | ✅ `30%/70% CPU/GPU` (was 62/38), host free 4.4 GB |
| Usable context preserved | ✅ 131072 > 3× the 40000 escalation threshold |
| **Multimodal/vision** | ✅ correct answer ("There are three circles: red, blue, and green."), 28.2 s, 100 % GPU |
| **deer-flow `/v1` path** | ✅ 200 OK, correct usage block, model loaded 100 % GPU |
| Whole-system free RAM | ✅ **7.79 GB** (was 1.16–1.28 GB) |
| Commit charge | ✅ **64.9 %** (was 76.5 %) |
| `llama-server` working set | ✅ **12 533 MB** (was 16 170 MB) |
| `audit-model-tags.ps1` | ✅ every requested local tag pre-pulled; 1 expected warning (base `q8_0`) |
| `test-model-roster-consistency.ps1` | ✅ **13 / 13** |
| Container health | ✅ deer-flow, pacgate-api, openviking, pacgate-mcp, pacgate-db, frontend all **healthy** |
| Idempotency | ✅ re-running `ensure-context-capped-model.ps1` reports `[ok] already exists` |
| Restore artifact | `deer-flow-extensions-config.json.bak.pre-1016` |

---

## 6b. Audit addendum (2026-10-16, evening) — karpathy-guidelines review + E2E

A full independent audit of the fixes was run with the `karpathy-guidelines` lens
(surgical changes, minimum code, goal-driven verification).

### A real bug the first review missed — found and fixed

`ensure-context-capped-model.ps1` used `& $ollama show <tag> --parameters 2>$null`
while `$ErrorActionPreference = 'Stop'`. This repo documents that trap twice
(`install.ps1`, `smoke-deer-flow-outputs.ps1`): under **Windows PowerShell 5.1** any
native command that writes to **stderr** becomes a **terminating** error once a
redirection is attached. `ollama show <missing-tag>` writes model-not-found to stderr,
so on a **fresh install** — the one run that needs this script — it would have died.

Reproduced in both hosts:

| Host | `ollama show <missing> --parameters 2>$null` under Stop |
|---|---|
| `powershell.exe` (5.1) | ❌ **[TERMINATING ERROR]** |
| `pwsh` (7.6.7) | ✅ survived, `LASTEXITCODE=1` |

The first idempotency test passed only because both tags already existed — a
**false green**. Fixed by adding `Invoke-OllamaQuiet`, which lowers the preference for
the duration of the call (the pattern this repo already uses) and returns
`{Output, ExitCode}`. `install.ps1` additionally now wraps the helper in `try/catch`
and **warns instead of aborting**, because `install.ps1` itself runs under `Stop` and a
non-fatal derivative failure must not kill the whole deploy.

Verified after the fix, under **PS 5.1**:
- fresh-install path (target absent) → `[..] missing - creating` → `[ok] created and verified`
- missing **source** → clean actionable message (`Run: ollama pull …`), no partial model
- idempotent re-run → `[ok] already exists`, no rebuild
- both scripts parse clean under the 5.1 parser

### E2E + smoke results

| Lane | Result | Evidence |
|---|---|---|
| `scripts/smoke-full-stack.ps1` | ✅ **19 pass / 0 fail / 2 skip** | pai 0.1.31 + revision, 19 MCP tools, deer-flow MCP wiring, frontend branded + 200, openviking 200, ocr weights, qm portal |
| `smoke-deer-flow-outputs.ps1` | ✅ **PASS** | real admin login → outputs list (2 files, `virtual_path` + `artifact_url`) → artifact download 200 (62 B) |
| `scripts/test-legal-journey.ps1` | ✅ **19/19** | matter → upload → OCR → sanitize (2 redactions) → egress gate → search → **OpenViking write→recall round trip** → qm → cleanup |
| `scripts/test-mcp-401-retry.ps1` | ✅ **16/16** | incl. Case 4: a `PACGATE_JWT_TOKEN`-only deploy must not blind-retry |
| `deploy/client-bundle/e2e-audit.py` | ✅ **exit 0** | create thread → upload DOCX → auto-convert MD → MD readable |
| `test-install-render.ps1` | ✅ 11 passed, 0 failed | my `install.ps1` edit did not break the render path |
| `test-compose-healthchecks.ps1` | ✅ 0 failures, 0 skipped | |
| `test-workflow-compose-wiring.ps1` | ✅ wiring complete/consistent | prod/bundle agree |
| `test-model-roster-consistency.ps1` | ✅ 13/13 | |

Runtime/shell caveat worth recording: this **dev** shell is `pwsh` **7.6.7**, but
`install.ps1` runs under `powershell.exe` 5.1 — which is why the trap above did not
surface in my first test.

### Secrets / access wiring verdict

Checked by **presence + length + SHA-256 prefix only** — no secret values printed
(active credential-exposure incident in this repo).

| Item | Verdict | Note |
|---|---|---|
| `OPENVIKING_ROOT_API_KEY` ↔ served config | ✅ **hash MATCH** | `.env` value and `root_api_key` in `OPENVIKING_CONF_CONTENT` are the same 32-char key |
| OpenViking end-to-end auth | ✅ works | legal journey's MCP `remember` → `find` round trip is the live proof |
| `PACGATE_API_EMAIL` (21) / `PACGATE_API_PASSWORD` (24) / `PACGATE_MATTER_ID` (36) | ✅ set | reaching deer-flow, pacgate-api and pacgate-mcp; used successfully by both smoke tests |
| `PACGATE_JWT_TOKEN` = **empty** on all 3 services | ✅ **by design** | Case 4 of the 401 gate: empty ⇒ login-based auth, no blind retry. Not a wiring break |
| `PACGATE_DB_PASSWORD` (16) | ✅ set | db healthy; volume intact |
| Connector keys (yuandian/pkulaw/qcc/fyopen/vaquill/ansvar) | ✅ set | journey: **9 of 10 connectors available** |
| `COURT_LISTENER_API_KEY`, `OPENCORPORATES_API_KEY` | ⚪ absent — **expected** | both are **commented out** in `.env.example`; their connectors report unavailable rather than failing a run |
| `PACGATE_SETUP_TOKEN` absent | ✅ by design | setup gate not armed; `needs_setup=False` |
| `AUTH_JWT_SECRET` unset | ⚪ warning, self-healed | deer-flow logs a WARNING and auto-generates `.jwt_secret`, persisted across restarts. Optional hardening |
| **`pacgate-db` volume** | ✅ **untouched** | still on `pacgate-ai-bundle_pacgate-db-data`, 100.3 MB, `matters=11`, `documents=102` — the AGENTS.md hazard did not trigger |
| **Connector config** | ✅ **byte-identical to backup** | `deer-flow-extensions-config.json` SHA-256 unchanged |

**Correction to §5:** deer-flow's connector file holds **30 MCP servers, of which 18 are
`enabled` and 12 `disabled`** (11 granular `qcc-*` entries + `ansvar`). The earlier
phrasing "30 connectors intact" was imprecise. This split is **pre-existing** (the file
is byte-identical to the pre-change backup) and is consistent with the working unified
`qcc` connector path — pacgate-api's external search returned 135 results and the
journey reported `qcc` available.

### Frontend verdict

| Surface | Result |
|---|---|
| deer-flow UI `:8090` | ✅ 200, 61 221 B, 16 ms; `/api/auth/setup-status` and `/api/threads` both **401 anonymously** (correct) and **200 with a session** (proven by the outputs smoke test) |
| qm portal `:8181` | ✅ `/healthz` → **200**; `/` → **401** — exactly the behavior `test-legal-journey.ps1` documents at L315 (auth-gated portal, health endpoint open) |
| qm web-ui `:8182`, core `:8180`, admin `:8183` | ✅ all up |
| ingress `:8089/pacgate/` | ✅ 401 anonymously (correct); used successfully by the journey test |

One cosmetic nit, pre-existing and unrelated: `smoke-full-stack.ps1` reports
"frontend is BRANDED (47 files reference pacgate)" while a raw `GET /` on `:8090`
returns `<title>DeerFlow</title>`. The branding lives in assets, not the title, so this
is not a regression from this change and was left alone.


---

## 7. Second-order issues found (not caused by this change)

1. **`compose.{bundle,prod}.yaml` tier defaults still name the uncapped base tags** (`PACGATE_MODEL_MAIN: ${PACGATE_MODEL_MAIN:-gemma4:12b-it-qat}`). `.env` currently wins, so the live stack is correct — but `test-model-roster-consistency.ps1` asserts *Rust fallback == compose default*, so these defaults **cannot simply be repointed** without also changing `ModelConfig::DEFAULT_*_TAG` in Rust. Tracked as follow-up; the `.env` override is the safe lever.
2. **`gemma4:12b-it-qat` happens to fit at 262144** (Q4_0, 7.2 GB, 100 % GPU, host free 13.7 GB). It is therefore benign — but any *other* lane that pulls the **q8_0** base tag directly will re-create the wall. It is now warned by the audit.
3. **No `.wslconfig`** ⇒ WSL/Docker capped at 16 GB inside a 32 GB box. **Observed later the same evening: `vmmemWSL` had grown to 13.9 GB private / 6.1 GB working set**, which was the dominant remaining consumer once the model was fixed (free RAM read 1.84 GB *because of WSL*, not the model — the runner itself was healthy at `100% GPU`, `n_ctx 131072`, `system_free=3.7 GiB`). This is Linux page cache inside the VM, so it is reclaimable rather than leaked, but it makes host free RAM a misleading indicator. A `.wslconfig` with `memory=8GB` would add a hard ceiling; left alone deliberately because it forces a WSL restart and does not affect the fixed defect.
4. **Prior eviction cycles are gone** — the 9 logged evictions were all `predicted_num_ctx=262144`; the runner no longer starts there.

---

## 8. Reproduce / roll back

**Reproduce on any AIPC (idempotent):**
```powershell
cd pacgate-ai\deploy\client-bundle
powershell -NoProfile -ExecutionPolicy Bypass -File .\ensure-context-capped-model.ps1
```

**Confirm the wall is gone:**
```powershell
ollama run gemma4-legal:12b-chat "Say OK"
ollama ps          # PROCESSOR must read '100% GPU'
```

**Roll back** (restores the previous spill behaviour — do this only to A/B the symptom):
```powershell
# deer-flow-config.yaml: point the 4 local roles + .env tiers + ov VLM back at gemma4:12b-it-q8_0
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api openviking
docker compose -f compose.bundle.yaml restart deer-flow
```

Scripts kept for reuse: `ensure-context-capped-model.ps1`.
