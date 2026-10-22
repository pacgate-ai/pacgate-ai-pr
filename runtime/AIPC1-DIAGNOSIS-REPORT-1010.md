# AIPC1 Differential Diagnosis — model hangs, delays, 401s, GPU <50%, cloud failures
**Date**: 2026-10-10 (evening) · **Machine**: PACGATE-AI01 (AIPC1) · **Stack**: v0.1.25, all 5 GHCR-pinned images
**Method**: systematic-debugging (Phase 1 evidence → Phase 2 differential vs AIPC2 → Phase 3 hypothesis → verified fix)
**Scripts**: `runtime/diag1-env-1010.ps1` … `diag7-smoke-1010.ps1` (+ outputs `.txt`), `e2e-fallback-1010.py`, `e2e-warm-1010.py`

---

## Executive summary

| User-reported symptom | Root cause (verified) | Status |
|---|---|---|
| Model hang / delay | **nemotron-30b CPU-spill thrash + single-runner queueing** — 24.05GB model on 16GB VRAM card: 13GB in VRAM, ~11GB spilled to host RAM; host RAM hit **0.45GB free** → spilled pages thrash; every agent call queues behind the previous one on the single Ollama runner slot | ✅ FIXED (pre-authorized fallback applied) |
| "dGPU <50%" | Structural: 12.99/24.05GB = **54% in VRAM, 46% on CPU** — the model is simply bigger than the card; RAM starvation made the CPU half crawl (prefill 195 t/s vs 580 t/s fully-in-VRAM) | ✅ FIXED (100% in VRAM now) |
| pacgate-api 401 | **NOT a server defect.** Fresh-token auth works (200 + data). All 81 nginx 401s today = unauthenticated probes (audit scripts, version checks, my own curl tests) + 19 failed logins. Adapter re-login patch live (6 hits in container). MCP re-authenticates fine | ✅ explained (no defect) |
| Cloud model can't finish | **Cloud API healthy** (deepseek-v4.1-flash:cloud → 200 in 1.1s). Failures = ollama.com Pro rolling limit (429s) + 78k-token agent contexts; runs table shows today's cloud runs actually **succeeded** (2 interrupted by user) | ✅ explained (transient limits) |
| AIPC2 fine, AIPC1 not | Same hardware, different **state**: AIPC1 runs extra containers (hermes-web crash-looping 244 restarts, odysseus, open-webui, ironclaw) competing for the same 29.6GB RAM, and carries the nemotron spill burden | ✅ explained |

## The degradation engine (why it "hangs")

Today's Ollama log census (server.log + server-1.log, ~2.5h window):
**13 evictions · 18 `llm server error` · 34 model loads · 30 slow POSTs (>1min)**

The cycle:
1. nemotron loaded → 12.99GB VRAM + ~11GB host RAM → host at 0.45GB free
2. Ollama predicts next request exceeds memory → **evicts** ("predicted 24.8GiB, available 2.7GiB, system_free 1.2GiB")
3. Reload = 15–52s; then **full re-prefill** of the 18k-token agent prompt at ~195 t/s = **93s**
4. Meanwhile every other call (suggestions, memory updater, summarizer, my test) **queues** on the single runner slot (`OLLAMA_NUM_PARALLEL=1`)
5. My 27-token test call waited **108s** behind one agent call; GIN log shows `POST /v1/chat/completions → 2m27s`

deer-flow agent LLM calls today: **30–172s each**, ~15 per run → 10–30 min per run. The GPU itself was never slow (37–42 t/s gen) — the wall time was queue + spilled prefill.

## Evidence trail

| # | Finding | Source |
|---|---|---|
| 1 | FreeRAM 0.3–0.48GB of 29.6GB; commit 45.7/63.6GB; 900 page-reads/5s | diag1/diag2 |
| 2 | llama-server WS 18.3–19.09GB (CPU spill) | diag1/diag3 |
| 3 | nemotron 12.99GB VRAM / 24.05GB total = 54% GPU | diag1/diag3 `ollama ps` |
| 4 | Evictions at 18:06:32 + 18:13:09 with `system_free=1.2GiB` | diag2 (server-1.log) |
| 5 | 27-token test queued 108s; agent call = 93s prefill @195 t/s + 54s gen | diag4 (live log) |
| 6 | Fresh-token auth → 200 + real matter data via nginx | diag3 |
| 7 | 81 nginx 401s = probes/logins only; 0 browser-UA 401s | diag6 |
| 8 | Adapter `_relogin_if_401` live in container (6 hits) | diag6 |
| 9 | Cloud direct ping 200 in 1.1–1.9s | diag3/diag4 |
| 10 | Runs table: 14 runs today, all success/interrupted, 0 errors | diag6 |
| 11 | hermes-web crash loop active (RestartCount 244, dies ~27s) | diag2 |
| 12 | Clock skew 0.85s (rules out JWT clock issues) | diag1 |
| 13 | KV-cache churn: "erased invalidated context checkpoint… forcing full prompt re-processing" | diag4 |

## Fix applied (pre-authorized, LOCAL-ONLY)

Per `HANDOFF-PUSH-AND-REBUILD-0.1.25.md`: *"GPU decision: stay on (a) nemotron-30b for general purposes. If this machine hangs again, switch this local machine only to gemma4-12b — do NOT make that a pushable/committable change."* The hangs **provably recurred** (13 evictions in 2.5h), so the fallback was applied:

**`pacgate-ai/deploy/client-bundle/deer-flow-config.yaml`** (bind-mounted, live):
- Default = `gemma4-12b-local` → tag **`gemma4:12b-it-q8_0`** (NOT qat — openviking VLM + pacgate-api tiers already use q8_0 on this box → one shared runner slot, zero cross-lane swaps)
- nemotron demoted to picker option with honest description (24GB/16GB VRAM tradeoff documented)
- `nemotron-30b-memory` → `gemma4-12b-memory` (same-tag pin, no swap)
- `nemotron-30b-summarizer` → `gemma4-12b-summarizer` (same-tag pin)
- `model_routing.local_model` + `cloud_model` → `gemma4-12b-local` (escalation = no-op by design; no automatic path can pull nemotron behind the user's back)
- Fixed a latent YAML bug: stray `stream_chunk_timeout: 300` was live by accident (attached to ornith-35b entry); commented out

**`pacgate-ai/deploy/client-bundle/ollama-models.txt`**: added `gemma4:12b-it-q8_0` with LOCAL-ONLY annotation (audit-model-tags.ps1 caught the drift — now 0 warnings).

## Verification (post-fix)

| Check | Result |
|---|---|
| YAML valid in container, all refs resolve | ✅ (venv python yaml check) |
| deer-flow restart clean | ✅ 3.7s |
| gemma4 q8_0: **12.33/12.33GB = 100% in VRAM** | ✅ `ollama ps` |
| FreeRAM 0.45 → **4.92GB** (+4.5GB) | ✅ |
| llama-server RAM 18.3 → **12.16GB** | ✅ |
| Evictions since restart | ✅ **0** |
| E2E chat run (new thread, explicit model) | ✅ PASS — exact reply, `success` in runs table, 61,413 input tokens |
| Warm-path run (same thread, cache_read 61,408) | ✅ PASS — 110.6s wall |
| audit-model-tags.ps1 | ✅ 0 warnings |

**Honest tradeoff**: gemma4 generates at ~18.8 t/s vs nemotron's 41.9 t/s — but nemotron's wall time was dominated by 108s queue waits + 93s spilled prefill, so **real-world latency improves dramatically**. First call after idle pays a 17s cold load (KEEP_ALIVE=10m keeps it warm after that). Also note gemma4's tokenizer counts ~1.9× more tokens for the same prompt (61k vs 32.7k) — watch the 64k context window on long threads; summarization (trigger 5000/keep 4000) is live and will bound it.

## Remaining actions (not blocking)

1. **hermes-web crash loop** (RestartCount 244, dies every ~27s): repair ACL on `C:\Users\pacga\github-pr\hermes-agent\data\SOUL.md` (owner `PACGATE-AI01\pacga`) or move it aside. Noise, not causal — but it churns Docker.
2. **Cloud 429s**: ollama.com Pro rolling limit — wait for reset or add credits at ollama.com/settings. Not a machine defect.
3. **If nemotron is needed** (1M-ctx workloads): pick it deliberately in the model picker; expect 2–3min first-token under RAM pressure. Consider closing RAM-heavy apps first (the 29.6GB box runs VS Code ×4, Edge, Notion, RustDesk, Docker + 26 containers).
4. **AIPC2 comparison** (to confirm the differential): on AIPC2, check `ollama ps` (nemotron VRAM split), FreeRAM under load, and the Ollama log eviction census. Prediction: AIPC2 shows the same 54% VRAM split but **more free RAM** (fewer competing containers) → fewer evictions → fewer queue stalls. If AIPC2 also shows evictions, the fallback applies there too.
5. **Upstream candidates** (separate from this local fix): frontend model-picker filter for `[internal]` entries; retry-loses-file-context bug (already documented 2026-10-10).

## Scripts kept for reuse

- `runtime/diag1-env-1010.ps1` → env/GPU/clock/containers/Ollama/network snapshot
- `runtime/diag2-ram-401-1010.ps1` → RAM pressure detail + Ollama log scan + 401 trace
- `runtime/diag3-401-perf-1010.ps1` → 401 isolation (nginx vs direct) + perf repro
- `runtime/diag4-queue-401src-1010.ps1` → live Ollama log (FileShare read) + queue proof
- `runtime/diag5-401src2-1010.ps1` → adapter env + eviction census (partial — killed at turn boundary)
- `runtime/diag6-401census-1010.ps1` → 401 census by path + runs table + adapter liveness
- `runtime/diag7-smoke-1010.ps1` → post-fix smoke (VRAM/RAM/evictions)
- `runtime/e2e-fallback-1010.py` / `e2e-warm-1010.py` → E2E chat verification
- `runtime/validate-config-1010.py` → YAML validation inside container
