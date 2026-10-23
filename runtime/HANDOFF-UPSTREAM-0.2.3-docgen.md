# Upstream handoff — deterministic document generation (for 0.2.3)

**From:** AIPC1 (`pacgate-law` working copy)
**To:** JZKK720 / `pacgate-ai-pr`
**Date:** 2026-10-23
**Base:** `v0.2.2` (`ddbb70ec571e`)
**Patch:** `runtime/docgen-deterministic-fix.patch` (2 files, +269/−6)

---

## 1. The defect

`POST /api/workflows/:id/execute` returns **HTTP 200 with an empty result** for
every document-generation workflow. No document is written. Nothing errors.

Reproduced on the pinned `0.2.2` stack, workflow `00000000-0000-0000-0000-000000001002`
(项目概况表编制), which declares `tool: generate_docx` and whose `system_prompt`
says "输出为Word文档（表格形式）":

```
[FAIL] a step actually invoked the document-generated tool
       tools_used across steps: 'list_documents'
[FAIL] the run CREATED a document row in the matter
```

This is the gate `scripts/test-document-generation-e2e.ps1`, which has been red
on every release since it was written.

## 2. Root cause

The model is asked to do **two** things: choose a tool out of eleven, and
serialise that tool's arguments. On the Main-tier model it can do neither.

Measured on `gemma4-legal:12b-chat` (the configured Main tier, 13 GB, 100% GPU):

| Offered tool surface | Runs that called `generate_docx` |
|---|---|
| all 11 tools | **0 of 5** — every run called `list_documents` |
| `generate_docx` only | **0 of 5** — still `list_documents`, and sometimes invented names that were never offered (`print_files`, `list_files`, `get_matter_summary`) |

Ruled out, each by measurement:

| Hypothesis | Result |
|---|---|
| Quantization | `gemma4:12b-it-qat` and `gemma4:12b-it-q8_0` both fail |
| Context size | 32768 / 65536 / 131072 all fail |
| Temperature | 0.0 / 0.1 / 0.2 / 1.0 all fail |
| Tool ordering in the schema | no effect |
| `tool_choice` | not in `ChatRequest`, and Ollama ignores it |
| Prompt ordering (step-first vs base-first) | no effect |
| Rewriting the base prompt's "always call list_documents first" line | no effect |
| Stripping unavailable tool names from the base prompt | no effect |
| Prompt length | stochastic; no clean threshold |

The 27B (`qwen3.8-legal:27b-mid`) **does** follow the directive — 3 of 3 — but it
is 17 GB and spills 30% to CPU on a 16 GB card (`ollama ps`: `30%/70% CPU/GPU`),
so it is not a viable default on this hardware.

**Conclusion: this is a model-capability limit, not a wiring defect.** No prompt
change fixes it, and no model that fits the card fixes it.

## 3. The fix

Remove the tool *choice* from the model. Keep the model for the part only it can
do — authoring the content.

`AgentLoop::run_generation_tool` (`crates/pacgate-agent/src/lib.rs`):

1. Ask the model for **one** thing: the document structure as JSON, with **no
   tools offered at all**. A model with no tools cannot pick the wrong one, and
   cannot spend the turn gathering context instead of writing.
2. Extract the outermost balanced `{...}` from the reply (`extract_json_object`),
   so a code fence or a "Here is the document:" prefix does not break it.
3. Call the tool **directly** with `{matter_id, filename, structure}`.
4. If the reply carries no parseable structure, **fall back** to the existing
   agent loop — a model that cannot produce JSON degrades to the previous
   behaviour rather than writing an empty document.

`WorkflowExecutor` routes a step through this path when `is_generation_tool(step.tool)`
is true (currently `generate_docx`). Every other step is unchanged.

`step_filename` derives the filename from `parameters.filename` when present,
otherwise from the step name, and forces a `.docx` extension so a step cannot ask
`generate_docx` for a name the tool will reject.

### Why this is the right shape

The model still writes the document. What is removed is the decision — and the
decision is the part that has a deterministic answer, because the workflow YAML
already states it. Asking a model to re-derive a fact the caller already knows is
where the failure lives.

## 4. Verification on AIPC1

Built from `v0.2.2` + this patch, deployed to the live stack, then:

```
scripts/test-document-generation-e2e.ps1
  RESULT: 19 passed, 0 failed

scripts/test-document-generation-e2e.ps1 -FailureRateRuns 8
  failures: 0 of 8
  RESULT: 20 passed, 0 failed

6 consecutive real workflow executions
  run 0..5 : generate_docx
  6 OK / 0 FAIL, 6 documents created
```

The gate now asserts the whole chain and passes it: a document row exists, the id
resolves through `GET /api/documents/:id`, the file exists on disk, it is a real
OOXML package with `word/document.xml`, the body is non-empty, and Chinese text
survived the round trip (`CJK sample: '项目概况表'`).

Before the patch, the same gate on the same stack: `8 passed, 2 failed`.

## 5. What this does NOT change

- No new tool, no schema change, no migration.
- Chat is untouched: `run_with_router` is unchanged and still offers all 11 tools.
- Non-generation workflow steps are untouched.
- The fallback means a model that cannot emit JSON behaves exactly as it does
  today — the patch cannot make anything worse than the current state.

## 6. Suggested release

`0.2.3`, built from `v0.2.2` + this patch. Only `pacgate-api` changes; the other
four images can be rebuilt unchanged so all five stay on one revision.

After publishing, AIPC1 pulls and the gate goes green with no local build.

## 7. Files

| File | Change |
|---|---|
| `crates/pacgate-agent/src/lib.rs` | `is_generation_tool`, `generation_output_contract`, `extract_json_object`, `AgentLoop::run_generation_tool` |
| `crates/pacgate-agent/src/workflow_executor.rs` | route generation steps through `run_generation_tool`; `step_filename` |

Both compile clean against `v0.2.2` (`cargo build --release --bin pacgate-server`,
no new warnings).
