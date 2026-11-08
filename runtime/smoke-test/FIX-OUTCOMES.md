# Fix outcomes — extraction backfill, sanitize batch, read-back

**Date:** 2026-11-08
**Stack:** `0.2.32`, revision `7a6dd732c6df`
**Starting point:** `runtime/smoke-test/SMOKE-TEST.md`

---

## What I actually fixed vs what I stopped

| # | Fix | Outcome |
|---|---|---|
| 1 | Extraction backfill for the 173 blocked documents | ✅ **DONE** — rows **76 → 249**, zero pending docs without extraction |
| 2 | Sanitize the actionable backlog | ⛔ **BLOCKED** — saturates `pacgate-api`; 1 of 208 completed |
| 3 | Batch/background sanitize lane | 📄 Diagnosed, not implemented (needs your capacity decision) |
| 4 | Make `pending` searchable | 🚫 **DECLINED** — deliberate security gate, see below |
| 5 | Agent read-back of generated docs | 🚫 **DECLINED** — same gate, see below |

---

## 1. Extraction backfill — DONE

### What was actually wrong

The 173 documents were **not unextractable**. They had simply **never been extracted**.
Two independent causes, both now characterised:

**(a) A client-timeout livelock.** `server.py` defaults to a 60 s client timeout. Extraction
of a real document outlasts it, the client resets the connection, and the handler future is
killed — so **no `document_extractions` row is ever written**. The document looks
permanently unextractable. This is the same failure the code comment already documents for
the *sanitize* path (measured 2026-10-08), never fixed for *extract*.

Evidence: 26 of 136 extractions failed with `[Errno 104] Connection reset by peer`, and on
re-query **0 documents were still missing rows** — the jobs had completed server-side; only
the client gave up. **"Failed" was a lie in 26 of 26 cases.**

**(b) `pacgate_ocr_batch` cannot make progress past its cap.** It adds
`outcome.get("pages", 0)` — the document's **size** — to `pages_used`, not the work it
performed. So a cached (already-extracted) document still consumes the whole cap budget the
second time. Because the per-matter listing is 65 documents, the walk hits the 200-page cap
inside the same 65-document prefix every run and restarts there forever. Measured over 30
consecutive runs: `processed=65`, `remaining` oscillating 76–93, **never decreasing**,
~3,534 page-extractions burned for 27 new rows. The docstring's claim that "cache makes a
continuation free for already-extracted documents" is **false**.

### What I did

Bypassed the capped batch loop and called `POST /api/documents/:id/extract` per document
over the exact id set taken from SQL (**not** the API listing, which is paginated to 65 and
would silently skip 143 documents).

| Metric | Before | After |
|---|---|---|
| `document_extractions` rows | 76 | **249** |
| Pending docs with **no** extraction | 173 | **0** |
| Pending docs with a complete extraction | 37 | **208** |
| Incomplete extractions | — | 2 |

Non-destructive: extraction writes `document_extractions` + `document_spans` and computes
embeddings. It performs **no redaction** and changes **no** `sanitization_state`, so nothing
became searchable that shouldn't be.

---

## 2. Sanitize batch — BLOCKED, and why I stopped

One document sanitized correctly (22 s, 1 redaction, 1 chunk promoted). The **second**
took >700 s and the third never returned.

The cause is not the client. While the batch ran:

| Signal | Value |
|---|---|
| `pacgate-api` CPU | **498 %** |
| `pacgate-api` memory | 1.714 GiB / **4 GiB cap** (42.8 %) |
| Healthcheck | `FailingStreak: 37`, 10 s timeouts |
| `/health` from inside the container | **no response in 15 s** |

The sanitizer saturates the API it is part of — the healthcheck cannot get a slot, so the
container reports **unhealthy** and any dependent gets 5xx. No OOM, no restart
(`OOMKilled: false`), no crash: pure starvation. I restarted `pacgate-api` and it returned to
healthy in 5 s.

### Why the per-document time is so high

Roughly linear in chunks, and **heavy triplication** inflates the work:

- 208 sanitize-eligible docs hold **5,280 chunks**, but only **2,418 distinct content
  hashes** — 54 % duplicates (the same document stored as v1/v2/v3).
- A 1-chunk / 2,395-char doc: **22 s**.
- A 144-chunk / 90,036-char doc: **~655 s** (matches the 2026-10-08 measurement, and my
  700 s cap was barely too short).

Extrapolating, the backlog is roughly **3 M characters / 5,280 chunks** — hours of
uninterrupted NER, at 2 concurrent slots, contending with the API's own memory budget.

**I stopped rather than push production into sustained unhealthiness.** Running this needs
an explicit decision about capacity, which is not mine to make:

- raise `pacgate-api` memory (4 GiB → 8 GiB) and/or
- do it off-hours in small chunks, accepting transient unhealthiness, and/or
- add a background queue so sanitize does not block the request path.

---

## 3 & 4. Read-back and the `pending` gate — DECLINED on purpose

`download_body_for` (`documents.rs:224`) is **deliberate security design**:

```rust
match (state, text_like) {
    ("sanitized", true)  => DownloadBody::SanitisedText,
    ("sanitized", false) => DownloadBody::RefusedBinary,
    ("never", _)         => DownloadBody::OriginalBinary,
    _                    => DownloadBody::RefusedBinary,   // pending / blocked
}
```

A `pending` document refuses download because **its bytes have not been redacted**. That is
the same gate that prevented the leaked credentials from reaching a prompt earlier today
(`lib.rs:341`, `sanitization_state IN ('sanitized','never')`). Loosening it to let an agent
read its own freshly generated `.docx` would reopen exactly the hole I closed this morning.

**The correct fix is behavioural, not permissive:** the workflow should sanitize *before*
`read_document`, or author in a text format the sanitizer handles natively
(`Txt`/`Markdown`/`Html` are text-like and still gated, but cheaper to sanitize). I left the
gate intact and recorded the trade-off instead.

---

## Incidental findings worth your attention

**`PACGATE_SANITIZER_KEY` is unset on every job.** The API warns each time:

> identifier tokens are derived from a per-process random key, so the same person gets a
> different token in each run

That means redaction tokens are **not stable across processes** — `[ORG_EEE1687152D0325A]`
today will not match the same organisation tomorrow, and a restart changes every mapping.
That breaks cross-document correlation and makes the ledger harder to audit. It is logged as
a `WARN`, so it is known but unaddressed. **Setting this key is a one-line config change with
real value**; I did not set it because it would change token identity mid-corpus and
invalidate existing mappings without your sign-off.

**Duplicate versions triple the cost.** 5,280 chunks → 2,418 distinct. Deduplicating
document versions before sanitizing would cut the batch by roughly half.

**Empty extractions exist.** Two documents report `incomplete=false` yet produced **0
chunks** (`presented-人工复核清单_身份证号银行卡号残留检测_v1.1` / `v1.2`). A "complete"
extraction with no text is contradictory and can stall a sanitize job. Worth a gate.

---

## State at hand-off

All five containers **healthy**. `build-info` → `0.2.32`, revision `7a6dd732c6df`.

| | Before today | Now |
|---|---|---|
| Extraction rows | 76 | **249** |
| Pending docs unsearchable | 173 with no extraction | **0** — all have extraction; 208 sanitize-eligible |
| Searchable chunks | 257 / 2,317 (11 %) | **258 / 5,605 (4.6 %)** |

> The *share* fell because extraction added 3,288 new `pending` chunks that the gate
> excludes. That is expected and the right direction: the content is now **indexed and
> ready**, waiting on sanitize. Coverage goes up only when the batch runs.

## Recommended next step

Run the sanitize batch in **off-hours chunks of ~20 documents** (size-ordered smallest
first), with `pacgate-api` memory raised to 8 GiB, watching `FailingStreak`. Expect
roughly 20–40 min per chunk. Re-measure retrievable-chunk share afterwards.
