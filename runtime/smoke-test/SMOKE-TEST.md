# Smoke test — sanitizer batch latency & the "fake 200" workflow suspicion

**Date:** 2026-11-08
**Stack:** `0.2.32`, revision `7a6dd732c6df`
**Method:** measured against the live stack, not read from code. Every number below
came from a real HTTP call or a real SQL query.

---

## Q1 — Are the 222 workflows fake HTTP 200s?

**No. They do real work.** The suspicion is wrong, and the evidence is direct.

### Inventory (authoritative, from `GET /api/workflows`)

| Metric | Value |
|---|---|
| Workflows served | **222** |
| Distinct ids / names | 222 / 222 |
| Categories | **46** |
| Zero-step workflows | **0** |
| Total steps | 422 (min 1, max 3) |

My first count said 220 / 417 — that was a crude line parser over the YAML. The API is
authoritative; the 3 `_extra` files hold ~125 of them.

> Note on shape: **max 3 steps per workflow.** These are coarse, LLM-driven steps, not
> 20-step deterministic pipelines. That is a design choice, not a defect.

### Live execution — `项目档案初收（第一阶段）` (2 steps)

| Measurement | Value |
|---|---|
| HTTP | **200** |
| Wall time | **45.8 s** |
| Response body | 5,264 bytes, 2 step results |
| Step 1 tool | `kb_search` → **6 tool calls** (`kb_search` ×3, `list_documents`) |
| Step 2 tools | `kb_search`, `list_documents`, `legal_search` ×4, `generate_docx`, `read_document` |

The step `content` was **substantive**, not a stub — it enumerated the queries it ran,
reported zero hits, and **refused to fabricate**:

> "I cannot report any standard or claim list content. Per my accuracy rules, I will not
> reconstruct a 'unified archive directory standard' from general knowledge and present it
> as if it came from this matter's archive — that would be fabrication."

### The generated artifact is real

| Check | Result |
|---|---|
| DB row | `08735c83…`, version 1, `sanitization_state=pending` |
| File on disk | 9,778 bytes |
| Magic bytes | `PK` — **valid Office zip** |
| OOXML parts | `word/document.xml` = **47,177 bytes**, settings, styles, rels |
| Extracted text | **6,312 chars** |
| Content | 42-row claim table across 5 practice areas; cites 《律师业务档案立卷归档办法》《归档文件整理规则》(DA/T 22—2015), GB/T 18894—2016; carries a draft disclaimer ("不构成最终法律意见") |

**Verdict: the 200s are real.** Output is verifiable at the byte level.

### But two real defects surfaced during the run

**(a) `read_document` cannot read a document the agent just generated.**
Step 2 called `generate_docx` then `read_document`, which returned
*"no sanitised text available."* If the agent cannot read its own output, it cannot
self-verify — and the agent correctly said so in its own words
(*"内容校验未能完成"*). Root cause: downloads serve sanitized text only, and the document
was still `pending`. **Self-verification of generated documents is structurally blocked
until the sanitize step runs.**

**(b) The knowledge base for a fresh matter is empty.** Step 1 found 0 chunks and the
agent fell back to `legal_search`. Both are correct behaviour, but it means a workflow run
against a new matter is not grounded in that matter's documents.

---

## Q2 — Is the sanitizer batch too long?

**Yes for a full batch — but the batch is mostly impossible, not slow.** The real finding
is worse than latency.

### Per-document latency (measured)

| Run | Document | Result | Time |
|---|---|---|---|
| 1 | 9,778-byte DOCX | `verdict=pass`, 4 redactions, 2 mappings, **8 chunks promoted** | **50.93 s** |
| 2 | 4 concurrent | 1 × 200, 3 × 500 | 79.4 s wall |

The redaction is genuine — `[ORG_EEE1687152D0325A]` and `[ORG_09B3416A948E1A5C]` replaced
`司律通` and `国家档案局` in the stored text, and the ledger recorded
`input_sha256 ≠ output_sha256`.

### Concurrency is capped at 2, and fails closed

```rust
pub const SANITIZE_MAX_CONCURRENT: usize = 2;   // state.rs:21
```

Static assert: `2 × 393 MB < 1 GiB` (detector memory). Exhausting the slots returns **503
`sanitize capacity`** — deliberately, so a job is rejected rather than silently dropped.

So a batch of N documents costs **N/2 × 51 s**:

| Backlog | Sequential cost |
|---|---|
| 37 actionable docs | ~16 min |
| 211 pending docs (if all were actionable) | **~90 min** |
| Full corpus (242) | ~103 min |

Two synchronous calls take ~9.8 min — already past a typical gateway or client timeout.
**There is no batch endpoint**; it is one document per HTTP call.

### The actual blocker: 173 of 211 pending docs cannot be sanitized at all

```
pending docs:                              211
  no extraction row    → 409 conflict     173
  complete extraction  → actionable        37
```

Both attempted documents returned **HTTP 409** immediately:

> `extraction is incomplete (the scan could not be read in full), so the document cannot be
> sanitized. Re-run extraction with the OCR engine, or upload a clearer scan.`

Fast-fail, no wasted time — which is correct — but **82% of the backlog is blocked on
extraction, not on sanitizer throughput.** Batch tuning would not move it.

### The consequence: 86% of the knowledge base is invisible

The RAG retrieval gate (`pacgate-rag/src/lib.rs:341`) requires
`sanitization_state IN ('sanitized','never')`. Current corpus:

| State | Chunks | Share | Retrievable |
|---|---|---|---|
| `pending` | **1,997** | **86.5%** | ❌ no |
| `sanitized` | 257 | 11.1% | ✅ yes |
| `blocked` | 63 | 2.7% | ❌ no |

**257 of 2,317 chunks (11%) are searchable.** Verified live via `pacgate_kb_search`:
common queries still return 4–5 results (`合同审查`, `保密协议`, `尽职调查`, `基金备案`,
`归档文件整理规则`), so it is not an outage — but the firm's KB is answering from roughly
**one ninth** of its indexed content.

### Concurrency is not what breaks it

I suspected the concurrent embedding calls caused the 500s. **They do not** — 4 parallel
`/api/embed` calls to Ollama all succeeded in 1.0 s, and serial ×4 took 0.1 s. The 500 was
`failed to ingest extracted text: embedding error` after **79 s**, i.e. a failure on the
ingest/embed path, *not* an embedding-service capacity limit. **Not reproduced in
isolation; left open.**

---

## Verdicts

| Claim | Verdict |
|---|---|
| "The 222 workflows are fake HTTP 200s" | **FALSE.** 222 real workflows, 422 steps, 46 categories, 0 empty. Executed one: 45.8 s, real reasoning, real 9,778-byte DOCX with 6,312 chars of content. |
| "The sanitizer batch is too long" | **TRUE for a full batch** (N/2 × 51 s, no batch endpoint, 2 slots), **but the binding constraint is extraction**: 173/211 are 409 and cannot be sanitized at all. |
| Real production impact | **86% of KB chunks (1,997) are unsearchable** because they are still `pending`. Common queries still answer, so it degrades silently rather than failing. |
| Self-verification | **Broken for generated docs.** `read_document` refuses a document the agent just wrote until it is sanitized. |

## Highest-value fixes, in order

1. **Backfill extraction for the 173 documents** — this is the blocker, not throughput. Until
   it runs, no amount of sanitizer tuning helps.
2. **Sanitize the 37 actionable docs** (~16 min at the current rate) — recovers real KB
   coverage immediately.
3. **Run sanitize as a background job with a progress endpoint**, instead of a synchronous
   call capped at 2 slots. A 90-minute corpus pass cannot be driven by synchronous HTTP.
4. **Decide whether `pending` should be searchable at a lower data level.** Today 86% of the
   index is dark; that is a product decision, not a bug.
5. **Let the agent read its own generated document** (sanitize on write, or serve the raw
   bytes for the authoring turn) so `generate_docx` → `read_document` verification works.

## Evidence

- `runtime/smoke-test/execute-response.json` — full workflow execution response
- `runtime/smoke-test/sanitize-response.json` — full sanitize job outcome
- Scripts: `login.ps1`, `list-workflows.ps1`, `execute-workflow.ps1`, `sanitize-one.ps1`
  (credentials read from `.env` by key name; `.token` and `.matter` are gitignored)
