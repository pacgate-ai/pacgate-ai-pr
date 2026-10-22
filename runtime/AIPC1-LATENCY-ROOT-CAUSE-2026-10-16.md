# AIPC1 — Session Hang / Latency Root-Cause Analysis

**Date:** 2026-10-16
**Trigger:** client trials — multi-step, multi-tool sessions hung, ran extremely long, produced no output.
**Method:** `systematic-debugging` Phase 1–3 against live logs (deer-flow container, `Ollama\server.log`, `checkpoints.db`).
**Status:** root causes identified and evidenced. **No fixes applied yet** — see §4 for the ranked plan.

> ⚠️ **PARTIALLY SUPERSEDED 2026-10-17 — read `AIPC1-P0-P4-REEVALUATION-2026-10-17.md` first.**
> Re-measurement against the live stack corrected this document on several load-bearing points:
> the live chat path is the **cloud** model (95 runs on `deepseek-v4.1-flash-cloud` vs 7 on
> `gemma4-12b-local`), so the **~19 k prompt and 30 s prefill figures are local-runner numbers
> and do not describe the real chat prompt** — the bound prompt measures **80,791–90,225 tok**,
> of which MCP tool schemas are **69,313**. Checkpoint DB: `freelist_count = 0`, so the §4-P3
> VACUUM would reclaim **nothing** until 73 % stale thread data is deleted first. The live memory
> backend is an HTTP adapter to pacgate-api, **not** the in-repo `deermem` module (that module
> does not import in the deployed image). See the re-evaluation's §6 for the full correction list.


---

## 0. Direct answers to the two questions

| Question | Verdict | Basis |
|---|---|---|
| **Model regression?** | **NO** | 49/49 layers on GPU, 12.07 GiB weights, 16.6 tok/s = **72 % of the card's bandwidth ceiling** |
| **Prompt bottleneck?** | **YES — primary cause** | 18.8–19.0 k token prompts, **30.4–30.9 s prefill**, paid on every step |

The model is performing at its hardware limit. The workload is what is broken.

---

## 1. Evidence

### 1.1 The model is healthy — regression ruled out

```
load_tensors: offloaded 49/49 layers to GPU
load_tensors:   CPU_Mapped model buffer size =  1020.00 MiB
load_tensors:        ROCm0 model buffer size = 12067.72 MiB
llama_kv_cache:      ROCm0 KV buffer size =  1088.00 MiB
llama_kv_cache:      ROCm0 KV buffer size =   255.00 MiB
sched_reserve:       ROCm0 compute buffer size =   448.80 MiB
llama_context: n_ctx                 = 131072
llama_context: n_ctx_seq (131072) < n_ctx_train (262144)
```

VRAM in use: 12067.72 + 1088 + 255 + 448.80 = **13,859.5 MiB of 15.98 GiB** → fits, no spill.
The 2026-10-16 context cap is **working** (`n_ctx = 131072`, not 262144).

**Throughput sanity check.** RX 7600 XT = 128-bit GDDR6 @ 18 Gbps = **288 GB/s**.
12.4 GB of Q8_0 weights ÷ 288 GB/s = **23.2 tok/s theoretical ceiling**.
Measured **16.6 tok/s = 72 % of ceiling** — normal-to-good for ROCm. **No regression.**

### 1.2 Prompt prefill is the bottleneck

| `task.n_tokens` | `prompt eval time` | rate |
|---|---|---|
| 19,021 | 30,863 ms | 616 tok/s |
| 18,877 | 30,597 ms | 617 tok/s |
| 18,816 | 30,386 ms | 619 tok/s |
| 8,909 | 12,287 ms | 683 tok/s |
| 3,236 | 4,414 ms | 733 tok/s |
| 1,029 | 1,487 ms | 692 tok/s |

Prefill ≈ **1.45 ms/token ≈ 690 tok/s**. A 19 k prompt costs **~30 s before the first output token**.

### 1.3 Generation is slow and always hits the cap

```
eval time = 123103.40 ms / 2048 tokens (16.63 tok/s)
eval time = 123753.43 ms / 2048 tokens (16.54 tok/s)
eval time = 121744.10 ms / 2048 tokens (16.81 tok/s)
eval time =  95826.78 ms / 1212 tokens (12.64 tok/s)
eval time =  77761.10 ms / 1354 tokens (17.40 tok/s)
```

44 `eval time` lines; generation clusters at **10–24 tok/s**. The 2048-token runs are hitting
`max_tokens: 2048` **exactly** — i.e. truncated mid-output, not finished.

### 1.4 153 MCP tools are loaded into every prompt

```
deerflow.tools.tools - INFO - Total tools loaded: 7, built-in tools: 2, MCP tools: 153, AC...
deerflow.tools.tools - INFO - Using 153 cached MCP tool(s)
deerflow.mcp.tools   - INFO - Initializing MCP client with 18 server(s)
```

153 tool schemas is the dominant fixed cost of the ~19 k prompt.

### 1.5 One runner slot — everything serializes

```
srv load_model: initializing, n_slots = 1, n_ctx_slot = 131072, kv_unified = 'false'
OLLAMA_NUM_PARALLEL = 1
```

Chat, memory updater, summarizer and title generator **all queue on the same single slot**.

### 1.6 The memory updater burns a full slot turn and returns nothing

```
11× deerflow.agents.memory.updater - WARNING - Failed to parse LLM response for memory update:
      No valid memory update JSON object found: line 1 column 1 (char 0)
 9× deerflow.agents.memory.queue   - WARNING - Memory update skipped/failed for thread ...
12× deerflow.agents.memory.queue   - INFO    - Processing 1 queued memory updates
 9× deerflow.agents.lead_agent.agent - INFO  - Create Agent(default) -> thinking_enabled: True
```

`line 1 column 1 (char 0)` = the response body was **empty**. `gemma4-12b-memory` carries
`max_tokens: 2048`; with thinking enabled the reasoning tokens consume the whole budget and
leave **zero content tokens**. Each failed attempt still costs a **~124 s** generation on the
single slot. 11 failures ≈ **23 minutes of slot time producing nothing.**

### 1.7 Checkpoint DB is oversized

| | |
|---|---|
| `checkpoints.db` | **2,376,687,616 B (2.3 GiB)** |
| `checkpoints.db-wal` | **124 MB** |
| `checkpoints` rows | 9,085 |
| `writes` rows | 13,883 |

Every superstep writes a checkpoint; the WAL is never checkpointed down.

### 1.8 Runs are created and never complete

```
10:33:41 Run created: run_id=08ac0857... thread_id=d8585b43...
12:04:48 Run created: run_id=733202e6... thread_id=e7cd8c4e...
12:35:59 Run created: run_id=8f3534d8... thread_id=e7cd8c4e...
13:53:38 Run created: run_id=8e1e8e8c... thread_id=a5f6e4f0...
14:35:18 Run created: run_id=189b8587... thread_id=a5f6e4f0...
```

**Five runs created in 8 h, zero completion or failure lines.** This is the reported "hung".

### 1.9 Prompt cache is being invalidated continuously

```
srv load_model: prompt cache is enabled, size limit: 8192 MiB
srv load_model: context checkpoints enabled, max = 32, min spacing = 8192
slot operator(): erased invalidated context checkpoint (... size = 170.013 MiB)   × many
```

Repeated checkpoint erasure means **no prefix reuse** — every step pays the full 30 s prefill.

---

## 2. Root causes (ranked)

| # | Root cause | Evidence | Impact |
|---|---|---|---|
| **RC1** | **153 MCP tool schemas inflate every prompt to ~19 k tokens** | §1.4, §1.2 | +30 s prefill **per step** |
| **RC2** | **16.6 tok/s generation × 2048-token outputs = 124 s per step** | §1.3 | dominant per-step cost |
| **RC3** | **Single runner slot serializes chat + memory + summarizer + title** | §1.5 | background work blocks the user |
| **RC4** | **Memory updater returns empty (thinking eats the 2048 budget) yet still burns a slot turn** | §1.6 | ~23 min of wasted slot time |
| **RC5** | **2.3 GiB `checkpoints.db` + 124 MB WAL** | §1.7 | per-superstep write amplification |
| **RC6** | **Step cost × step count exceeds the 1200 s idle timeout** | §1.8, §3 | run killed → no output |

---

## 3. The arithmetic that produces the "hang"

Measured per agent step:

```
prefill   19,000 tok @ 690 tok/s  =  27.5 s
generate   2,048 tok @ 16.6 tok/s = 123.4 s
                                    ─────────
                            ≈ 151 s per step
```

- A **10-step** tool-using session = **≈ 25 minutes** of pure inference, before any MCP network latency.
- Plus **12 queued memory updates × 124 s = 24.8 min** of stolen slot time.
- `DEERFLOW_STREAM_IDLE_TIMEOUT_S=1200` (20 min) kills any run that emits nothing for 20 min.

**This is exactly the mechanism already documented in `deer-flow-config.yaml`** for run
`ad509d43` (thread `96a4f39e`), killed at 420 s after its last chunk. The 2026-10-16 context
cap fixed the *memory wall*; it did not change *step cost*, so the latency failure mode survived.

---

## 4. Fix plan (ranked, not yet applied)

### P0 — Cut the tool surface (largest single lever)
18 MCP servers → 153 tools. Disable the servers the legal workflows do not call.
`deer-flow-extensions-config.json` already has 12 of 30 disabled; the remaining 18 are the
live set. Target: the ~6 servers actually used by the due-diligence path.
**Expected:** 19 k → ~6–8 k prompt ⇒ prefill 30 s → ~10 s.

### P1 — Stop the memory updater burning slot turns
- Disable thinking for `gemma4-12b-memory` (or raise its `max_tokens`), so the 2048 budget
  is not consumed by reasoning and the JSON actually completes.
- Consider `memory.enabled: false` during trials — it is a background nicety, not a
  user-visible feature, and it currently costs more than it returns.

### P2 — Stop truncating at 2048
Every long generation hits the cap exactly. Either the cap is too low for the task or the
model is looping. Distinguish by inspecting one full response body.

### P3 — Checkpoint DB maintenance
`VACUUM` + WAL checkpoint on `checkpoints.db` (2.3 GiB / 124 MB WAL), and a retention policy
for the 9,085 checkpoints.

### P4 — Concurrency
`OLLAMA_NUM_PARALLEL=1` is correct for VRAM, but it means background roles must not compete
with chat. Either serialize them deliberately (queue) or move them off the local runner.

---

## 5. Verification plan

1. Re-run one multi-step trial; confirm `task.n_tokens` drops below 8 k.
2. Confirm `prompt eval time` < 12 s.
3. Confirm zero `Failed to parse LLM response for memory update` lines.
4. Confirm at least one `Run created` is followed by a completion line.
5. Confirm `checkpoints.db` < 500 MB.

---

## 6. Reproduce

```powershell
# deer-flow run lifecycle
docker logs deer-flow --since 8h 2>&1 | Select-String 'Run created|Run completed|Run failed'

# tool surface
docker logs deer-flow --since 8h 2>&1 | Select-String 'Total tools loaded|MCP tool'

# memory updater failures
docker logs deer-flow --since 8h 2>&1 | Select-String 'memory update'

# inference timings (ground truth)
Select-String -Path "$env:LOCALAPPDATA\Ollama\server.log" -Pattern 'prompt eval time|eval time|n_ctx_slot|offloaded'

# checkpoint DB
docker exec deer-flow python /tmp/_probe.py
```
