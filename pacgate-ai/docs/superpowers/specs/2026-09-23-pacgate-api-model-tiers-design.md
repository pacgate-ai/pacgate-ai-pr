# pacgate-api model tiers select an uninstalled model — design + options

**Date:** 2026-09-23
**Status:** DIAGNOSED. Fixes prepared, **NOT APPLIED** — waiting on a user decision.
**Found by:** `scripts/test-e2e-features.ps1` (added this session)
**Severity:** HIGH — every LLM-backed feature in `pacgate-api` fails.

---

## 1. The defect

`pacgate-api` resolves its three LLM tiers from **hardcoded model names** that do not
exist in the local Ollama. Result: every workflow run, chat turn, and agent execution
returns HTTP 500.

Live reproduction (no ambiguity — the error names the model and the URL):

```
POST /pacgate/api/chat                     -> 500
POST /pacgate/api/workflows/<id>/execute   -> 500

{"error":{"code":"internal_error","message":
 "LLM error: LLM HTTP status: model=nemotron3:33b
  url=http://host.docker.internal:11434/v1/chat/completions
  error=HTTP status client error (404 Not Found)"}}
```

### Root cause chain

1. `pacgate-api` boots with
   `pacgate_core::ModelConfig::default_local_with_base_url(&ollama_url)`
   — `crates/pacgate-api/src/main.rs` L88-89.
2. That function hardcodes the model names
   — `crates/pacgate-core/src/lib.rs` L132 / L141 / L150:

   | Tier | Hardcoded model | Installed here? |
   |---|---|---|
   | Main | `nemotron3:33b` | ❌ (Ollama `/api/show` → 404) |
   | Mid  | `qwen3.6:27b`   | ❌ (404) |
   | Low  | `qwen3.5:9b`    | ❌ (404) |

3. `OLLAMA_BASE_URL` is honoured — **the model NAMES are not overridable by env.**
4. The only switch is per-tenant:
   `tenants.config_json.model_overrides` → `AppState::router_for_tenant()`
   (`crates/pacgate-api/src/state.rs` L28-57). When that list is empty, the router
   falls back to the dead defaults.
5. **The live tenant's `config_json` is `{}`** → zero overrides → the dead defaults win.

### Why nobody noticed

Two independent model systems exist, and only one is wired to the config the operator
edits:

| Consumer | Configured by | Live state |
|---|---|---|
| deer-flow (agent chat UI) | `deer-flow-config.yaml` `models:` + `model_routing:` | ✅ works, local default |
| **pacgate-api** (workflows / chat / tools) | tenant `config_json.model_overrides` | ❌ **dead defaults** |
| qm harness | `PI_MODEL` env | ✅ `glm-5.3-flash:cloud` |

The workflow **library** serves correctly (222 workflows, 46 categories over HTTP + MCP).
Only **execution** fails. A library that lists 222 workflows but cannot run one is the
exact "starts green, is quietly not the thing you think it is" failure shape this repo
has been bitten by before.

---

## 2. Options (needs a decision)

Recommended model: **`gemma4:12b-it-q8_0`** for all three tiers — the only local model
verified to handle the `json_schema`/tool-call grammar this engine needs, and it answers
correctly on this machine (`LOCAL-OK` in 33 s cold).

### Option A — seed the tenant `model_overrides` (config only, applies today)

No code change, no rebuild, reversible.

```sql
UPDATE tenants
SET config_json = jsonb_set(
      config_json,
      '{model_overrides}',
      '[
        {"tier":"main","provider":{"ollama":{"base_url":"http://host.docker.internal:11434"}},
         "model_name":"gemma4:12b-it-q8_0","max_tokens":16384,"temperature":0.1},
        {"tier":"mid","provider":{"ollama":{"base_url":"http://host.docker.internal:11434"}},
         "model_name":"gemma4:12b-it-q8_0","max_tokens":8192,"temperature":0.1},
        {"tier":"low","provider":{"ollama":{"base_url":"http://host.docker.internal:11434"}},
         "model_name":"gemma4:12b-it-q8_0","max_tokens":4096,"temperature":0.2}
      ]'::jsonb,
      true)
WHERE slug = 'pacgate-law';
```

- **Shape verified** against `pacgate-core`: `ModelConfig { tier, provider, model_name,
  max_tokens, temperature }`; `LlmTier` and `LlmProvider` are both
  `#[serde(rename_all = "snake_case")]`, so `main`/`mid`/`low` and
  `{"ollama":{"base_url":...}}` are correct.
- Takes effect **per request** (`router_for_tenant` is called per run) — no restart.
- ❌ **Per-machine and per-tenant.** A fresh install / new machine starts broken again.
  This is the same class of silent gap that already bit us.

### Option B — make the tiers read from the environment (durable)

Add env overrides in `pacgate-core` (alongside the existing
`default_local_with_base_url`), consumed by `main.rs`:

| Env var | Default |
|---|---|
| `PACGATE_LLM_MODEL_MAIN` | `gemma4:12b-it-q8_0` |
| `PACGATE_LLM_MODEL_MID`  | `gemma4:12b-it-q8_0` |
| `PACGATE_LLM_MODEL_LOW`  | `gemma4:12b-it-q8_0` |

Then set them in `.env` and add them to `compose.bundle.yaml` / `compose.prod.yaml`
under `pacgate-api`.

- ✅ Matches the user's recorded standing directive: **local model choice belongs to the
  user and can change per machine.** Only this option makes that true.
- ✅ Consistent with how deer-flow and qm already take their model from `.env`.
- ✅ A fresh clone + `install.ps1` comes up correct with no manual DB step.
- ❌ Needs a Rust change + rebuild + republish of the `pacgate-api` image (1 of 5).
- ❌ `AGENTS.md` requires explicit user confirmation before writing Rust source.

### Option C — A now, B properly  ← *recommended*

Unblock the machine today with A, and land B so every future machine is correct
without a manual step. The two are not redundant: A fixes *this* deployment now,
B fixes *the next* one automatically.

---

## 3. Separate finding — the sanitizer lane is PDF-only (measured per format)

**Reported, not fixed** (needs an ocr-service change, not a config change).

> **Correction to an earlier draft of this document.** It claimed Word files could
> not be uploaded/read at all. **That was wrong** — the mistake was testing
> pacgate-api's machine-to-machine API and assuming it was the user path. In the real
> user path (browser → deer-flow) **`.docx` works and is converted to markdown**.
> The claim is corrected below to what is actually measured.

### There are TWO document lanes, and only one of them handles Word

| Lane | Entry | Word support | Measured |
|---|---|---|---|
| **A. Upload / read (user-facing)** | `POST /api/threads/{id}/uploads` → deer-flow | ✅ **yes** | `.docx` → 200, `markdown_file=s3c-sample.md` produced automatically |
| **B. Sanitization gate (the red line)** | `POST /pacgate/api/documents` → pacgate-api → ocr-service | ❌ **no** | `.docx` → extract `incomplete=true, text_len=0` → sanitize **500** |

Lane A uses deer-flow's own converter (`markitdown` + `pymupdf4llm`, supporting
`.docx/.pptx/.xlsx/.pdf`) — `deerflow/utils/file_conversion.py`,
`CONVERTIBLE_EXTENSIONS`. Lane B is a different service and does **not** use it.

### Measured, per format (both through the sanitizer lane)

| Input | upload | extract | incomplete | text_len | sanitize |
|---|---|---|---|---|---|
| real `.pdf` | 200 | 200 | `false` | 797 | **200** ✅ `verdict=pass` |
| real `.docx` | 200 | 200 | **`true`** | **0** | **500** ❌ `extraction incomplete; document stays pending` |
| `.txt` (`pacgate_sanitize_text`) | 200 | 200 | `true` | 0 | **500** ❌ |

### Mechanism

`crates/pacgate-api/src/extract.rs` L125 uploads the bytes as
`file_name("document")` — **no extension**. ocr-service then defaults the suffix to
`.pdf` (`app.py`: `os.path.splitext(...)[1] or ".pdf"`), takes its pdf2image branch,
and rasterisation fails → the page is marked failed → `incomplete: true`. For a
non-PDF that still carries a suffix, `_prepare_pages` falls through to
`return [(1, tmp_path)]` — i.e. it hands the raw file to **PaddleOCR as if it were an
image**, OCR throws, the page is marked failed, and `text` comes back **empty**. Either
way `pacgate-api`'s fail-closed guard rejects it:

```
// Fail closed: an OCR error must not yield text we treat as complete.
"ocr-service returned {status}; extraction is incomplete, document stays pending"
```

The document is then pinned at `incomplete=true` and **can never be sanitized**.

### Impact — and the second defect this exposes

`pacgate_sanitize_text` is the MCP bridge tool that sanitizes **raw text**. It uploads
its input as `sanitize-ephemeral.txt` (`pacgate-mcp/server.py` L678) — a non-PDF — so
**it fails 100% of the time**, and it is the only tool that could sanitize text the
agent already holds (e.g. markdown converted from a Word file in lane A).

Net effect: **a Word document can be uploaded, converted and read by the agent, but the
sanitization gate cannot process it — nor any plain-text content.** Only PDFs can be
sanitized today. Since due-diligence intake is mostly `.docx`, this is a real gap.

Closing it needs either an ocr-service text path (`python-docx`, or reuse the
markitdown already present in the deer-flow image) plus an image rebuild, or — cheaper
and immediate — teaching `extract.rs` to bypass OCR for text formats and read the bytes
directly. A defensive minimum is to reject unsupported formats at upload with a clear
message instead of failing silently later.


---

## 4. Verification

```powershell
# whole-surface feature smoke (adds this session)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-e2e-features.ps1

# the two lanes that expose the model defect directly
curl.exe -sS -o NUL -w '%{http_code}' -X POST -H "Authorization: Bearer <jwt>" ^
  -H 'Content-Type: application/json' --data-binary '@body.json' ^
  http://localhost:8089/pacgate/api/workflows/00000000-0000-0000-0000-000000001001/execute
```

`test-e2e-features.ps1` distinguishes **PASS / FAIL / SKIP / KNOWN**; SKIP and KNOWN are
never counted as passes. After either fix, the two `api chat` / `workflow execute` lines
must turn green.

## 5. What was NOT done, and why

- **Option A was not applied** — no model change was made without the user present.
- **Option B was not applied** — `AGENTS.md` requires confirmation before writing Rust
  source, and this changes platform behaviour.
- **The OCR gap was not fixed** — needs a dependency + rebuild.
- A standing repo rule applies here: *when the user is unavailable to answer clarifying
  questions, stop and wait; do not proceed autonomously.* This session honoured it.
