# DEFECT: the idle watchdog kills summarization on AIPC1 (runs reported as "hang, no output")

**Severity:** HIGH — the user's documents ARE produced and then the run is reported as failed,
so a completed deliverable looks like a hang.
**Status:** fixed 2026-10-15 (watchdog budget 420s → 1200s). Counter-fidelity documented.
Mechanism confirmed by reconstructing the terminal silent stretch (§6a): the original
run's was exactly 420s while no intermediate gap exceeded 314s.
**Next bound (open):** `recursion_limit` is hardcoded to 100 in `client.py:218` and is
not configurable — see §6b. Tune it together with this budget.
**Affects:** any run where a `DeerFlowSummarizationMiddleware` step exceeds
`DEERFLOW_STREAM_IDLE_TIMEOUT_S`. Reported on AIPC1 (16 GB VRAM, gemma4:12b-it-q8_0).

---

## 1. Reported symptom

> a test run is asking 撰写一篇关于pacgate-ai的博客文章 to generate docx/pdf output,
> but there is hang, still no outputs until now

The user waited hours. The chat showed no finished output.

**The documents existed the whole time.** They were written and copied at 16:00:56:

```
data/deer-flow/users/<uid>/threads/96a4f39e-.../user-data/outputs/
    pacgate-ai-blog.docx   18,081 b   valid OOXML, word/document.xml = 39,735 b
    pacgate-ai-blog.pdf   173,650 b   %PDF-1.7
```

A complete 5,509-char post. Nothing was lost.

## 2. Root cause

`deerflow.db` → `runs`:

```
run ad509d43  status=error
ERROR = "The agent graph stopped producing output and the run was aborted by the idle watchdog. Please retry."
msgs=17  in=504,054  out=8,344  llm_call_count=10
```

Timeline, and the 420s is exact:

```
16:00:56  last astream chunk; sandbox `cp ... outputs/` verdict=pass
16:07:56  ERROR "no astream output for 420s — aborting (stalled pregel loop)"
          = 16:00:56 + 420s
```

`worker.py:55`:

```python
_STREAM_IDLE_TIMEOUT_SECONDS = float(os.environ.get("DEERFLOW_STREAM_IDLE_TIMEOUT_S", "420") or 420)
```

`DEERFLOW_STREAM_IDLE_TIMEOUT_S` was **unset**, so 420s applied.

**Why the summarizer can never finish inside 420s**

The graph's last checkpoint routes to
`branch:to:DeerFlowSummarizationMiddleware.before_model`, and the run's final
`writes` row is `__error__ = CancelledError()`.

A summarization step is a **single `ainvoke` inside ONE superstep**, so LangGraph
emits **no astream chunk for its entire duration** — exactly the condition the
watchdog measures.

Measured on AIPC1 with the real trimmed prompt (`count_tokens_approximately`
reports 7,981 tokens):

```
prefill  17,018 real tok @ 124 tok/s = 136.8s
gen       1,102 tok      @   6.3 tok/s = 174.3s
                                        -------
                                         311.4s   (only 109s of headroom)
```

At the summarizer's own `max_tokens: 4096` the generation alone is ~650s, so the
step reaches **~787s — 1.9× the 420s budget**. Reproduced deterministically; not
flaky.

**A structural trap:** the counter undercounts by **2.13×**, not the ~2.7× that
the config comment estimated for a different sample:

```
count_tokens_approximately = 7,981   (what trim_tokens_to_summarize=8000 means)
real prompt_eval_count     = 17,018  (what the model actually processes)
```

So `trim_tokens_to_summarize: 8000` sends ~17k real tokens, and
`trigger: 5000` fires much earlier than its name implies.

**Aggravating factors (not causal)**

- Chat ran on `deepseek-v4.1-flash-cloud` while the summarizer is pinned to the
  **local** `gemma4:12b-summarizer` → a 19.4s cross-model reload and a
  124 tok/s prefill instead of the cloud path's speed.
- Ollama reports `loaded runners count=1` — one runner slot, so the summarizer
  and any other lane serialize.
- `tool_count_threshold: 200` meant routing never escalated.
- ~18 enabled MCP servers each inject tools every round.

**Proof it was cut off mid-call, not silently dead:** Ollama's log at the *same
second*:

```
16:07:56  aborting completion request due to client closing the connection
          (llama_server.go:1656)
```

## 3. Why the UI showed nothing (secondary defect)

`checkpoint_ns` was **empty** on all 134 checkpoints for the thread, while the
`writes` table stores fully-namespaced channels
(`branch:to:DeerFlowSummarizationMiddleware.before_model`, …). Consequently no
checkpoint held a pending task, `next` was empty, and `run_events` held 0 rows —
so the UI's polls of `POST /threads/{id}/history` and
`GET .../runs/{id}/messages` had nothing to render. The run looked frozen while
the work had in fact completed.

## 4. Fix applied

`DEERFLOW_STREAM_IDLE_TIMEOUT_S: ${DEERFLOW_STREAM_IDLE_TIMEOUT_S:-1200}` added to
the `deer-flow` service in **both** `compose.bundle.yaml` and `compose.prod.yaml`
(kept in step). **1200s is deliberately bounded:** above the ~787s worst case,
below the 3600s nginx `proxy_read_timeout`, so a genuinely dead graph is still
recycled before the edge gives up — raising it does not make a wedged run
immortal.

**Deliberately NOT changed:** the summarizer model pin. Routing the summarizer to
a `:cloud` tag would be much faster but the summarizer sees the *entire*
conversation, including matter facts, and `deer-flow-config.yaml` forbids egress
that the user did not choose:

> it does not accept egress as a side effect of prompt size, upload, or not touching the picker

Keep both models on the local tag. If the step must shrink, the safe lever is
`trim_tokens_to_summarize`, remembering it is a *counted* value worth ~2.13× more
real tokens.

## 5. Verification

- `docker compose config` on both files: `DEERFLOW_STREAM_IDLE_TIMEOUT_S: "1200"`,
  both still pin `name: pacgate-ai-bundle` (volume convergence preserved).
- Live container env: `DEERFLOW_STREAM_IDLE_TIMEOUT_S=1200`.
- Effective patched `worker.py:55` reads the env var (a bind-mounted patch
  overrides the image copy — confirm the *patched* file, not the image).
- Data plane unchanged across the recreate: matters=11, documents=102, tenants=2,
  users=5; `kb_chunks` pending/sanitized/blocked = 1843/126/86; MCP 30/18/12.
- Existing gates still green — **`test-compose-healthchecks.ps1` 0 failures**,
  **`audit-model-tags.ps1` 0 warnings** (model tags unchanged),
  **`test-ps51-native-stderr.ps1` 33 passed / 0 failed**.
- **End-to-end deliverable verified:** a bounded Chinese blog request returned
  HTTP 200, `status=success`, in **20.9s** with a real summary reply, producing
  `pacgate-short.docx` (11,412 b, magic `PK\x03\x04`, 910 CJK chars round-tripped)
  and `pacgate-short.pdf` (13,212 b, magic `%PDF-`) in `outputs/`.

## 6. Known gap

### 6a. Independent confirmation via the terminal silent stretch

The watchdog measures the gap between *stream chunks*, which is not directly
logged. It can be reconstructed from the checkpoint store, because every
non-terminal superstep writes a checkpoint carrying an aware UTC `ts`:

```
terminal silent stretch = runs.updated_at - max(checkpoint.ts)
```

| Run | limit | max inter-checkpoint gap | **final silent stretch** | killed by 420s? |
|---|---|---|---|---|
| `ad509d43` original | 420s | 314s | **420s** | **yes** |
| run 2 cold start | 1200s | 311s | 0s | no |
| run 3 demanding | 1200s | 227s | 0s | no |
| run 4 deliverable | 1200s | 8s | 0s | no |

Two facts fall out, and they confirm §2 independently of the error string:

1. The original run's **final silent stretch was exactly 420s** — the watchdog
   fired at its limit, so the reported "no astream output for 420s" is literal.
2. **No intermediate gap exceeded 420s** (max 314s). So the run was killed on the
   *first* stretch to cross 420s — and that stretch wrote **no checkpoint at
   all**, which is the signature of a superstep that never completed: the
   summarization step. This is exactly what §2 predicts.

The original run therefore died on its very first over-budget silent step, and
that step was the summarizer. Raising the budget to 1200s moves the ceiling past
every observed stretch (max 314s + the ~787s worst-case summarizer).

### 6b. A second, harder bound was exposed immediately after the fix

With 1200s in force, a demanding multi-tool reproduction ran **1,103s** (vs the
old 420s ceiling) and then failed for a *different* reason:

```
status=error   in=309,421   out=15,507   llm_call_count=22   103 checkpoints
error = "Recursion limit of 100 reached without hitting a stop condition."
```

**No idle-watchdog error** — the fix did what it was meant to do: the run was no
longer cut off for being *quiet*, it ran to a genuine structural bound.

But `recursion_limit` is hardcoded and **not configurable**:

```python
# harness/deerflow/client.py:218
recursion_limit=overrides.get("recursion_limit", 100)
```

There is **no config key, no env var, and no run-request field** that sets it
(`client.py` only mentions it in a docstring). LangGraph counts supersteps, and
this run's construction is expensive: ~130 tools from ~18 enabled MCP servers,
plus summarization/title/token-usage middlewares. Measured on this box, that
leaves about **4–5 real tool calls** before the ceiling, which is not enough for
a genuine research-and-generate task.

Fixing it requires changing `client.py` in the image (or adding a patch to
`deploy/client-bundle/patches/`) — **out of scope for this defect**, and it is
the kind of change that deserves its own analysis rather than a third speculative
edit. Note the two bounds are now *coupled*: raising the watchdog moves failures
onto the recursion limit, so they should be tuned together.

### 6c. What is and is not yet proven

- **Proven:** the 420s budget was arithmetically insufficient (§2); the original
  run's terminal silent stretch was exactly 420s while no intermediate gap ever
  exceeded 314s, so it died on its first over-budget step — the summarizer (§6a);
  the constant is now 1200s and live; the misleading "stopped producing output"
  cancellation no longer reproduces, and a demanding run that could never have
  exceeded 420s ran 1,103s (§6b); the deliverable path is verified end to end —
  run 4 produced `pacgate-short.docx` (valid OOXML, 910 CJK chars) and
  `pacgate-short.pdf` (`%PDF-`) in 20.9s with `status=success`.
- **Not yet proven:** a run in which the summarizer *itself* takes longer than
  420s and now *completes*. Both reproductions avoided the summarizer — run 3 hit
  the recursion limit first, run 4 finished in 21s. Producing that case requires
  either raising `recursion_limit` (§6b) or a conversation long enough to force a
  >420s summarization, and it is the remaining work. The mechanism is nonetheless
  pinned by §6a: the summarizer is the step that crossed 420s, and the only
  obstacle to observing it complete is the *second* bound.

### 6d. Agent construction is outside the watchdog

After `docker compose up -d --force-recreate`, `Create Agent(...)` took **309s**
of silence (cold MCP tool discovery over ~18 servers) with no watchdog risk. A
cold-start stall therefore does not present as this defect, and must not be
diagnosed as one — the giveaway is that `runs` has no `run_id` row yet, or the
run logs show no `Create Agent` line.

## 7. Related finding: the title role was local only by accident

Found while auditing which roles are pinned to local models (2026-10-15). Of the
four internal roles, three were explicitly pinned and **`title` was not**:

```python
# harness/deerflow/models/factory.py:105-106
if name is None:
    name = config.models[0].name
```

With no `title.model_name`, the title step inherited `models[0]` — which is
`gemma4-12b-local` only because it happens to be the first entry in the `models:`
block. **Reordering that block, or adding a `-cloud` entry at its head, would have
started egressing the first user message to ollama.com** with no config change and
no picker interaction — precisely the case the file's header forbids ("egress as a
side effect of … not touching the picker"). A silent, ordering-dependent leak.

Fixed: an explicit `title.model_name: gemma4-12b-title` pin plus a
`gemma4-12b-title` entry (same local tag, `max_tokens: 2048`, matching the sibling
internal roles), with the reasoning recorded in both places.

**Lane verification (2026-10-15).** Grepping the whole deployed config surface for
`:cloud` returns exactly **two** real tags — `deepseek-v4.1-flash:cloud` and
`glm-5.3-flash:cloud`, both picker-selectable **inference** entries; every other
hit is a comment. `.env` contains no cloud tag at all. So all four internal roles
plus OCR, embeddings, the OpenViking VLM and the pacgate-api workflow tiers are
local, and cloud is reachable only by explicitly choosing it in the picker.

**Still true and worth knowing:** the title generation path times out at
`DEERFLOW_TITLE_INVOKE_TIMEOUT_S=8`. Ollama logs a `500` at **7.998s** on that
path (observed 16:30:45, 16:32:22, 16:51:52, 17:06:30 — i.e. **pre-existing**, not
caused by the pin; the first predates it by 30+ minutes). The middleware falls
back to a local title on timeout, so this is a quality-of-title issue, not data
loss — but an 8s budget for a call on a **cloud** model is tighter than the
measured latency of one trivial cloud round trip (~8–11s), so the fallback likely
fires often rather than rarely. Not changed here: fixing it is a latency-budget
tuning question, not a correctness one.
