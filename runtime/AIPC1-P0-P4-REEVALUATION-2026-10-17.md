# AIPC1 — P0–P4 Re-evaluation (2026-10-17)

**Supersedes the fix-plan section of** `AIPC1-LATENCY-ROOT-CAUSE-2026-10-16.md` **and corrects
several claims in it.** Method: live measurement on the running stack + fresh-context adversarial
review (`doubt-driven-development`). Every number below is reproducible with the probe scripts
listed in §7.

**Review status:** this document's claims survived one adversarial cycle. Six substantive defects
were found in the *draft* of this analysis and are recorded in §6 — including two where the draft
had the mechanism wrong while the conclusion happened to be right.

---

## 1. Headline corrections

| # | Prior claim | Corrected finding |
|---|---|---|
| 1 | The RCA treats "the local 12B chat model" as the session bottleneck | **The live chat path is the CLOUD model.** 95 runs on `deepseek-v4.1-flash-cloud` vs 7 on `gemma4-12b-local` (last 2026-10-11). `model_routing` is bypassed because an explicit model is requested. |
| 2 | "153 tool schemas inflate every prompt to **~19 k tokens**" | **Schemas alone measure 69,313 tok.** The real bound prompt is **80,791–90,225 tok**. Decomposition: 71,678 (all 162 tools) + 3,107 (system prompt) + 8,151 (dynamic-context reminder) ≈ **82,936** — matches measurement. The 19 k figure is a *local-runner* number; `:cloud` requests never appear in `Ollama\server.log`. |
| 3 | "Repeated checkpoint erasure means no prefix reuse — every step pays 30 s" | **On the cloud path, cache reuse is 84–100 %** (`cache_read` 75,520–86,912 of 80,791–90,225; `cache_read=0` on 2 of 18 calls). The RC9 prefill claim describes the **local** runner only. |
| 4 | "P1 — the memory updater burns a slot turn" | Correct on the symptom, **wrong on the system.** The live memory backend is an **HTTP adapter to pacgate-api**, not the in-repo `deermem` module. |
| 5 | "P3 — VACUUM + WAL checkpoint" | **VACUUM alone reclaims 0 bytes.** `freelist_count = 0`. 73 % of the file is stale thread data; deletion must come first. |
| 6 | "P4 — background roles compete with chat on the single slot" | Chat no longer uses the local slot. The local runner serves **background roles + an embedding consumer**, competing with each other. |

---

## 2. P0 — tool surface (routing / "hyperswitch")

### 2.1 The premise is CORRECT — the tool surface is the dominant prompt cost

Measured inside the live container (`langchain_core.utils.function_calling.convert_to_openai_function`):

```
all bound tools            = 162   tok = 71,678
  of which MCP             = 153   tok = 69,313   <- 83% of the real prompt
  of which sandbox/builtin =   9   tok =  2,366
```

`tool_search.enabled = false` in the live config, and the connector file
(`deer-flow-extensions-config.json`) has **no `routing:` and no per-tool `tools:` overrides** —
its only keys are `args, command, description, enabled, env, headers, type, url`.

**The build-time skill filter drops nothing.** Verified live: 162 tools in → 162 out, MCP 153 → 153.
The prefix-aware patch (`patches/deer-flow-tool-policy.py`) makes bare server declarations
(`pacgate`, `pkulaw`, `yuandian-law`, `qcc-company`, …) match every MCP tool name, so
`filter_tools_by_skill_allowed_tools` keeps the entire catalog.

### 2.2 The mechanism exists in-repo but is inert for TWO independent reasons

`build_mcp_routing_middleware` (`tools/builtins/tool_search.py:255-275`) bails at its **first guard**
when `deferred_setup.catalog_hash is None` — which is the case whenever `tool_search.enabled` is
false. It also builds an empty index (→ `None`) unless a tool carries
`mode == "prefer"` **and** non-empty `keywords`.

```
index populated only by:  McpServerConfig.routing          (server-level)   -> absent
                          McpServerConfig.tools.<name>.routing (per-tool)   -> absent
                          and mode must be literally "prefer"               -> default is "off"
```

So **flipping `tool_search.enabled: true` alone reproduces the 2026-09-12 failure**, exactly as the
config comment says: with an empty routing index there is no auto-promotion, so models call
unpromoted MCP tools. The remedy is a **two-part** change, and the second part is the one that was
missing:

```yaml
# deer-flow-config.yaml
tool_search:
  enabled: true
  auto_promote_top_k: 5      # clamp range is 1..5
```
```json
// deer-flow-extensions-config.json — per server that the due-diligence path needs
"pkulaw-law-search": { "enabled": true,
  "routing": { "mode": "prefer", "priority": 90,
               "keywords": ["法条", "法规", "statute", "legal provision"] } }
```

### 2.3 The live image is NOT the repo — the runtime skill-policy layer is missing

```
docker exec deer-flow grep -n 'SkillToolPolicyMiddleware|McpRoutingMiddleware' \
  /app/backend/packages/harness/deerflow/agents/lead_agent/agent.py
  -> (no matches; only DeferredToolFilterMiddleware at :437)
live agent.py = 646 lines   (repo copy is longer and installs both)
```

The live lead agent uses only the **build-time** `filter_tools_by_skill_allowed_tools` (which drops
nothing), not the runtime `SkillToolPolicyMiddleware`. Any plan that assumes runtime skill scoping
already narrows the surface is planning against code that is not deployed.

### 2.4 Where the saving actually lands — and where it does not

| Path | Deferral benefit |
|---|---|
| **Cloud** (`deepseek-v4.1-flash`) | Prompt shrinks ~83 %, **but** cache reads already cover 84–100 % of the current prompt. Benefit is real for *uncached* turns (~10–86 k of new tokens) and for cost/context headroom, **not** for the ~30 s prefill figure. |
| **Local** (Ollama) | Prefill 69 k tok @ ~690 tok/s ≈ 100 s → names-only listing ≈ 1,547 tok ≈ 2.2 s. **This is where the 30 s → ~10 s expectation is real** — and where per-slot prefix-cache invalidation currently forces a full re-prefill. |

`<available-deferred-tools>` costs only **1,547 tok** (153 names), so the deferred surface is
~3.9 k tok (listing + `tool_search` tool + a ~5-schema discovery payload) vs 69,313 — a
**~67.8 k tok / step** reduction.

### 2.5 Risks to plan for

- **Upstream #2968 (OPEN):** promotion is sticky for the session, so the prompt **grows back**
  toward 153 schemas within a long run. Two fix PRs open (#3046, #6977). Patch locally or wait.
- **New failure mode:** `assemble_deferred_tools` is **fail-closed** — enabling deferral while MCP
  candidates exist but none is deferrable raises `RuntimeError` and refuses to bind schemas.
- **Latency trade:** on the local runner at 16.6 tok/s generation, an extra `tool_search` round-trip
  costs real wall-clock. Prefer keyword auto-promotion (free, no round-trip) over model-initiated
  discovery.

---

## 3. P1 — memory (re-scoped)

### 3.1 The live memory system is not the one in the repo

```
/app/backend/packages/harness/deerflow/agents/memory/
  __init__.py  message_processing.py  prompt.py  queue.py (287 lines)
  storage.py   summarization_hook.py  updater.py
find /app/backend -path '*deermem*'   -> (empty)
import deerflow.agents.memory.manager -> ModuleNotFoundError
```

Live config resolves to `storage_class: pacgate_deerflow_adapter.storage.PacgateMemoryStorage`
— an **HTTP adapter to pacgate-api** (`GET /api/matters/<id>/memory`). Memory already persists, by
construction, in `pacgate-db`.

**Consequence:** the research conclusion "deermem's retrieval is SQLite FTS5, not vectors, and its
eviction is LLM-free" describes **code that never imports**. There is **no semantic index layer in
the live system at all** — which is precisely the gap the user asked about.

### 3.2 What the local runner is actually spending

From the run ledger (`deerflow.db runs.token_usage_by_model`), local `gemma4` per run:

| run | local input | local output |
|---|---|---|
| 14:35 | 19,599 | 10,029 |
| 13:53 | 7,998 | 6,348 |
| 12:35 | 37,886 | 26,624 |
| 12:04 | 43,411 | 16,869 |
| 10:33 | 40,617 | **41,608** |
| 08:55 | 47,048 | **40,578** |
| 08:17 | 52,369 | 32,080 |

Output of 32–41.6 k tokens per run cannot come from a 4096-cap summarizer alone — it is the
**aggregate of the background roles** (memory + title + summarizer) called repeatedly. At
16.6 tok/s, 41.6 k output ≈ **42 minutes** of slot time per run. **That is the real local cost**,
not the RCA's "124 s per step".

### 3.3 Defects that remain (verified against the LIVE queue)

| Property | Status |
|---|---|
| Write path async (daemon `threading.Timer`) | ✅ present (`queue.py:153-161`) |
| Graceful drain on shutdown | ❌ the live 287-line `queue.py` has **no `flush_sync`** (the repo copy does) |
| Durable spool | ❌ in-memory only — a crash/SIGKILL loses pending extractions |
| Retry / backoff after extraction failure | ❌ item is popped before processing and dropped |
| Dead-letter queue / poison handling | ❌ a permanently-failing thread retries forever (the 11/11 loop) |
| Idempotency key | ❌ |
| Reasoning-burn fix | ⚠️ **deployed, unverified** — no run since the 2026-10-16 16:19Z restart |
| Idle gating | ❌ background LLM calls contend on the single slot regardless of user activity |

### 3.4 Recommended shape

1. **Verify the reasoning fix** with one live run and assert zero `Failed to parse LLM response`
   lines. Nothing else should be concluded about P1 until this passes.
2. **Add idle-gating + circuit breaker** — do not issue the extraction call while a run is active,
   and stop after N consecutive failures instead of retrying every session.
3. **Durable spool + DLQ** — persist pending contexts and park poison payloads for replay.
4. **Put the semantic index where memory actually lives** — inside `pacgate-api`'s store, not
   deer-flow. Options that need no server process: `sqlite-vec` (pure C, no deps, pre-v1) with
   `sqlite-lembed` for in-process GGUF embeddings so index builds never touch the inference slot.
   Do **not** add Qdrant/pgvector/Neo4j on a box already at the memory wall.
5. **Consider moving extraction off the local runner.** The storage layer is already an HTTP
   adapter, so extraction could live in pacgate-api (or a cloud model) — mindful of the standing
   no-egress-by-side-effect red line for matter content.

---

## 4. P2 / P3 / P4

### P2 — truncation at 2048

Partly stale. The roles each carry **their own** cap (`memory` 2048, `title` 2048, `summarizer`
4096, `chat` 8192) and the memory cap is now moot at the source via `reasoning_effort: none`. The
"every long generation hits 2048 exactly" evidence came from the **background** roles, not the chat
path. Re-measure after the first post-fix run; do not treat this as a chat-path defect.

### P3 — checkpoint DB (re-scoped; VACUUM alone is a no-op)

```
file 2.215 GiB   page_size 4096   page_count 580,560
freelist_count = 0        -> 0.0 MiB reclaimable by VACUUM *today*
auto_vacuum = 0           -> deleting rows will NOT shrink the file
journal_mode = wal        wal_autocheckpoint = 1000 (≈4 MiB)   WAL on disk = 123.6 MiB
checkpoints 1,974 MiB     writes 291 MiB      9,085 rows / 56 threads
```

| Thread | Rows | Bytes | Share | App metadata |
|---|---|---|---|---|
| `d9d0fe54-…` | 1,043 | **1,418 MiB** | **72.2 %** | "AI Agent Security Feasibility Report", idle since **2026-09-13** |
| 3 more stale | — | 215 MiB | — | all idle since ≤ 2026-09-15 |

**4 stale threads = 1,633 MiB = 73 % of the database.** Remainder: 616 MiB / 52 threads.

Correct sequence — **delete first, then VACUUM**:

1. Delete stale threads **thread-atomically across `checkpoints` AND `writes`**. There is no
   DB-level FK, but `checkpoint_lineage.py` walks `checkpoint_id` / `parent_checkpoint_id`, so
   row-age deletion leaves dangling lineage.
2. Prefer the app's REST `DELETE /api/threads/{id}` so directories and `threads_meta` are handled —
   **but note it reports `success=True` even when checkpoint deletion throws**
   (`routers/threads.py:734-745`), so verify bytes actually dropped.
3. Edge case: thread `80abf375-…` has checkpoints but **no `threads_meta` row**, so
   `require_existing=True` blocks the app path — it needs a direct, thread-atomic delete.
4. Then `VACUUM` (needs ≈1× the DB in free disk; cannot run while another connection holds a read
   lock — expect `SQLITE_BUSY` risk with the app's own `AsyncSqliteStore` on the same file).
5. **Prevent recurrence:** a scheduled task (deer-flow `scheduler`, already enabled) that deletes
   threads idle > N days. The driver is LangGraph writing a checkpoint per superstep; one
   abandoned thread produced 1.4 GiB of it.

### P4 — concurrency (re-framed)

The premise "background roles compete with chat" no longer holds: **chat is cloud**
(`deepseek-v4.1-flash-cloud`, 95 runs). The local slot (`OLLAMA_NUM_PARALLEL=1`,
`OLLAMA_CONTEXT_LENGTH=131072`, no model currently resident) serves:

- the background roles (memory / title / summarizer) — 6 k–41.6 k output tok per run, and
- an **embedding consumer**: 3 local model loads at `n_ctx_slot = 2048` resolve to the
  `nomic-embed-text` blob (`970aa74c…`). (`deermem` retrieval is not deployed, so this is a
  different consumer — worth identifying.)

So the real decision is **policy among local consumers**, not chat-vs-background. Note also that
`gemma4:12b-it-q8_0` — the **uncapped 262144-context base tag** whose spill caused the original
memory wall — still appears in the run ledger, i.e. another lane still pins the tag the context-cap
fix replaced.

---

## 5. Revised priority

| Priority | Action | Expected effect |
|---|---|---|
| **P0** | `tool_search.enabled: true` **plus** `routing.mode: prefer` + `keywords` on the ~6 due-diligence servers | Local prompt 69 k → ~4 k tok schemas (~100 s → ~2 s prefill); cloud prompt 83 k → ~14 k |
| **P0b** | Port/verify the runtime skill-policy + routing middleware into the live image | Without it, the deferred path cannot auto-promote |
| **P1** | Verify the reasoning fix (1 run) → then idle-gate + DLQ + durable spool | Stops ~42 min/run of background slot burn and the unbounded retry loop |
| **P2** | Re-measure truncation post-fix; treat as background-role config, not a chat defect | — |
| **P3** | Delete stale threads thread-atomically → VACUUM → scheduled retention | 2.215 GiB → ~0.6 GiB |
| **P4** | Enumerate local consumers (roles + embedding + other compose projects) before choosing a scheduling policy | Bounds contention correctly |
| **P5 (new)** | Put the semantic index inside pacgate-api (`sqlite-vec` + `sqlite-lembed`) | The requested persistent semantic layer — it does not exist today |

---

## 6. Corrections found by adversarial review of the first draft

Recorded for honesty; each was verified against the live stack before accepting.

1. **Draft claimed the 153 schemas were NOT bound** (inferred from the local log's 19,021-token
   maximum). **Wrong mechanism, wrong conclusion for the live path.** `:cloud` requests never reach
   the local runner, so a local maximum cannot bound the cloud prompt. The 80,791–90,225 measurement
   shows the schemas **are** bound and dominate. The "9 tools" figure was a *sub-selection I
   constructed*, not a filter outcome — misread as the live bound surface.
2. **Draft claimed enabling `tool_search` was "one config line".** **Wrong** — the live image does
   not install the routing middleware, and with an empty routing index the flip reproduces the
   2026-09-12 failure.
3. **Draft cited `deermem` internals** (`queue.py` 472 lines with `flush_sync`, FTS5 retrieval,
   LLM-free eviction) as the live system. **The module is not deployed and does not import.**
4. **Draft headline "VACUUM cannot reclaim meaningful space" overreached.** `freelist_count = 0` is a
   *pre-deletion* measurement; VACUUM is exactly the required step *after* deletion. Also
   `writes` has **no** FK clause, so the stated referential-integrity risk was the wrong risk —
   logical lineage is.
5. **Draft miscounted the embedding loads** ("14 loads at 2048") by conflating `new prompt` lines
   with model loads. Actual: **10 model loads, 3 of them `nomic-embed-text` at 2048**, plus 11
   prompt events.
6. **Draft's "factory.py only emits a disable directive when `has_thinking_settings` is true" is
   false as a general statement** — `when_thinking_disabled` alone emits one
   (`patches/deer-flow-model-factory.py:138-141`); only the alternative disable paths are gated.
   The fix works; the propagated explanation did not.

Also noted: deer-flow logs are **UTC** while `Ollama\server.log` is **+08** — the two clocks are
interleaved and must be labelled when ordering matters.

---

## 7. Reproduce

Probe scripts (run against the live container) live beside this file:

```powershell
docker cp runtime\_measure_real_prompt.py  deer-flow:/tmp/ ; docker exec deer-flow /app/backend/.venv/bin/python /tmp/_measure_real_prompt.py
docker cp runtime\_db_reclaim.py           deer-flow:/tmp/ ; docker exec deer-flow /app/backend/.venv/bin/python /tmp/_db_reclaim.py
docker cp runtime\_token_split.py          deer-flow:/tmp/ ; docker exec deer-flow /app/backend/.venv/bin/python /tmp/_token_split.py
```

```powershell
# real bound prompt (authoritative for the cloud path)
docker logs deer-flow --since 72h 2>&1 | Select-String 'LLM token usage'
# who does the work
#   deerflow.db runs.model_name / token_usage_by_model
# local runner ground truth
Select-String -Path "$env:LOCALAPPDATA\Ollama\server.log" -Pattern 'task\.n_tokens|n_ctx_slot'
# connector routing metadata (expect: zero matches)
Select-String -Path "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.json" -Pattern 'routing|keywords'
```

## 8. Verification plan for the changes

1. `task.n_tokens` on a local run drops below 8 k; `<available-deferred-tools>` present.
2. Cloud `input` on a fresh thread drops from ~83 k to ~15 k; cache reuse stays ≥80 %.
3. Zero `Failed to parse LLM response for memory update` lines after one live run.
4. At least one `Run created` followed by a completion line.
5. `checkpoints.db` < 700 MiB and `freelist_count` ≈ 0 after VACUUM.
6. `ollama ps` shows no CPU/GPU split during a session.
