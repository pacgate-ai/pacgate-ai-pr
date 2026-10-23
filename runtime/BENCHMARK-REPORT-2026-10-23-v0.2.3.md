# Benchmark report — AIPC1, pacgate-ai 0.2.3

**Date:** 2026-10-23
**Machine:** AIPC1 (Windows, 31 GB RAM, AMD RX 7600 XT 16 GB VRAM)
**Stack:** `ghcr.io/jzkk720/*:0.2.3`, revision `d33553e2ed65`
**Method:** every number below is measured on the live stack, not estimated.

---

## 0. Headline

| Question | Answer |
| --- | --- |
| Is the lead LLM cloud deepseek? | **No.** It is local `gemma4-legal:12b-chat`. |
| Does document generation work on the local model? | **No** — 8/10 assertions, `list_documents` instead of `generate_docx`. |
| Does it work on cloud deepseek? | **Yes** — 20/20, 0 failures in 8 consecutive runs. |
| Is the stack otherwise healthy? | **Yes** — smoke 19/0, PDF lane green, data at baseline. |

The document-generation failure is a **model-capability limit, not a wiring
defect**. This report is the measurement that proves it.

---

## 1. Which model is the lead LLM?

`deer-flow` model picker, in order (first entry is the default):

| # | name | model tag | kind |
| --- | --- | --- | --- |
| 0 | `gemma4-12b-local` | `gemma4-legal:12b-chat` | **local (default)** |
| 1 | `gemma4-12b-memory` | `gemma4-legal:12b-chat` | local (internal) |
| 2 | `ornith-1.5-9b-local` | `ornith-1.5:9b` | local |
| 3 | `deepseek-v4.1-flash-cloud` | `deepseek-v4.1-flash:cloud` | cloud |
| 4 | `glm-5.3-flash-cloud` | `glm-5.3-flash:cloud` | cloud |

`pacgate-api` workflow tiers (`.env`):

```
PACGATE_MODEL_MAIN=gemma4-legal:12b-chat     <- the lead LLM for workflows
PACGATE_MODEL_MID=qwen3.8-legal:27b-mid
PACGATE_MODEL_LOW=gemma4-legal:12b-chat
```

So the lead LLM is **local**, and cloud deepseek is a picker option that is
**not** the default. Cloud models are reachable — `deepseek-v4.1-flash:cloud`
answered a probe in 441 ms — so this is a configuration choice, not a
connectivity limit.

---

## 2. Full smoke test

```
scripts/smoke-full-stack.ps1
  passed: 19   failed: 0   skipped(cannot-check): 2
  elapsed: 50 s
```

| Lane | Result |
| --- | --- |
| pacgate-api `/version` | PASS — `0.2.3` / `d33553e2ed65` |
| pacgate-api `/health` | PASS — 200 on the compose network |
| pacgate-api auth | PASS — anon refused 401 |
| pacgate-mcp tools | PASS — 19 tools, image == source |
| pacgate-mcp 401-retry fix | PASS — present in the running image |
| deer-flow MCP config | PASS — 18 servers enabled |
| deer-flow auth gateway | PASS — setup-status 200 |
| deer-flow-frontend | PASS — 200, branded (47 files) |
| openviking `/health` | PASS — 200, healthy |
| ocr-service | PASS — imports, baked weights det+rec+cls |
| qm-pacgate portal | PASS — 200 |

The two SKIPs are lanes the script cannot reach without a session; both were
closed manually in §3 and §5 below.

---

## 3. PDF upload → extract

Fixture: a real 3-page A4 PDF, Chinese + Latin, embedded `msyh.ttc` so the
glyphs actually rasterise.

| Stage | Latency | Result |
| --- | --- | --- |
| `POST /api/documents` | **62 ms** | document row created |
| `POST /api/documents/:id/extract` | **3 879 ms** | 651 chars, 3 pages, 24 spans, `incomplete=false` |

Extracted text (verbatim sample):

```
项目概况表一尽职调查报告第1页 | 目标公司：北京示例科技有限公司 |
统一社会信用代码：91110105MA01ABCD2X | 法定代表人：张三身份证号：11010519491231002X |
联系电话：13800138000 电子邮箱：zhangsan@example.com | 注册资本：人民币1000万元整
```

**A fixture trap worth recording.** The first fixture used reportlab's
`UnicodeCIDFont('STSong-Light')`, which is *not embedded*. The PDF had a valid
text layer (227 chars/page by `pypdf`) but rasterised to **pure white**
(luminance min=max=255), so PaddleOCR correctly reported
`page N produced no text lines; marking incomplete`. That is the fail-closed
contract working, not a defect. Always verify a fixture renders before reading a
zero-text result as a stack failure:

```python
from pdf2image import convert_from_path
p = convert_from_path(path)[0].convert("L")
assert p.getextrema() != (255, 255), "fixture is blank"
```

---

## 4. Document generation — the decisive comparison

Workflow `00000000-0000-0000-0000-000000001002` (项目概况表编制), which declares
`tool: generate_docx`.

### 4.1 Local `gemma4-legal:12b-chat` (the default)

```
scripts/test-document-generation-e2e.ps1
  [FAIL] a step actually invoked the document-generated tool
         tools_used: list_documents
  [FAIL] the run CREATED a document row in the matter
  RESULT: 8 passed, 2 failed
  elapsed: 42.4 s
```

The model called `list_documents` and stopped. No document was written.

### 4.2 Cloud `deepseek-v4.1-flash:cloud`

```
scripts/test-document-generation-e2e.ps1
  [PASS] a step actually invoked the document-generated tool
         tools_used: list_documents, kb_search, generate_docx, read_document
  [PASS] the run CREATED a document row in the matter
         00_项目说明及文件目录_项目概况表.docx
  [PASS] the generated file EXISTS on disk
         4185 bytes
  [PASS] the file is a real OOXML package (has word/document.xml)
  [PASS] Chinese text survived the round trip into the .docx
         CJK sample: '项目概况表'
  RESULT: 19 passed, 0 failed
  elapsed: 17.2 s
```

### 4.3 Soak — 8 consecutive runs, cloud

```
run 1/8 .. 8/8 : HTTP 200
failures: 0 of 8
RESULT: 20 passed, 0 failed
elapsed: 154.2 s  (19.3 s per run)
```

### 4.4 Comparison

| | local 12B | cloud deepseek |
| --- | --- | --- |
| Assertions | 8 / 10 | **20 / 20** |
| `generate_docx` called | no | **yes** |
| Document created | no | **yes, 4 185 bytes** |
| CJK round-trip | n/a | **pass** |
| Latency per run | 42.4 s | **17.2 s** (19.3 s under soak) |
| Failure rate | 1 / 1 | **0 / 8** |

**Conclusion.** The generation path is wired correctly end to end — the same
workflow, same YAML, same tools, same storage root. The only variable is the
model. A 12B model cannot reliably choose `generate_docx` out of eleven tools
and serialise its arguments; a cloud model can. This confirms the finding in
`runtime/DOCGEN-TOOL-CHOICE-FINDINGS-2026-10-22.md` and is exactly what the
deterministic fix in `runtime/docgen-deterministic-fix.patch` removes — it takes
the tool *choice* away from the model and derives it from the workflow YAML.

---

## 5. Agent → MCP invocation (the smoke SKIP, closed)

A real deer-flow agent turn, default local model:

```
prompt: "Call the pacgate_list_matters tool and tell me how many matters exist."
  -> tool call: pacgate_list_matters
  -> tool result: real rows from pacgate-db
  -> answer: "There are 10 matters currently existing in the system."
```

The DB holds 11 matters. The agent said 10 — **correct**: 10 belong to the
admin's tenant `d64908b0…`, 1 belongs to `722dbdd8…`. Tenant scoping is working.

---

## 6. Data integrity

Unchanged before and after every test in this report:

| Table | Count |
| --- | --- |
| matters | 11 |
| documents | 102 |
| kb_chunks | 2 055 |
| kb_chunks with embedding | 2 055 |
| document_extractions | 26 |
| sanitizer_jobs | 42 |
| redaction_ledger_rows | 30 |
| document_spans | 274 |
| users | 5 |

All benchmark matters were deleted after measurement; the counts above are the
post-cleanup state and match the pre-benchmark baseline exactly.

---

## 7. Reproduce

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai

# smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-full-stack.ps1

# docgen on the default (local) model
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-document-generation-e2e.ps1

# docgen on cloud deepseek: set PACGATE_MODEL_MAIN, recreate, run, restore
#   PACGATE_MODEL_MAIN=deepseek-v4.1-flash:cloud
#   docker compose -f deploy/client-bundle/compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api
#   ... run the gate ...
#   PACGATE_MODEL_MAIN=gemma4-legal:12b-chat   (restore)
```

`PACGATE_MODEL_MAIN` is read at process start, so a recreate is required — an
`up -d` alone will not pick up the change.
