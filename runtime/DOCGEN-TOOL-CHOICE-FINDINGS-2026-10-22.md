# Document-generation tool choice — findings (AIPC1, 2026-10-22)

Status: **open, upstream fix required.** No local image rebuild is deployed; the
stack runs the pinned upstream `ghcr.io/jzkk720/*:0.2.1` images.

## Symptom

`scripts/test-document-generation-e2e.ps1` fails on the 项目概况表编制 workflow
(`00000000-0000-0000-0000-000000001002`):

```
[FAIL] a step actually invoked the document-generated tool
       tools_used across steps: 'list_documents'
[FAIL] the run CREATED a document row in the matter
```

The step declares `tool: generate_docx` and its `system_prompt` says
"输出为Word文档（表格形式）". The model calls `list_documents` instead, the route
still returns HTTP 200, and no document is written.

## What was ruled out

Measured against the live stack and directly against Ollama.

| Hypothesis | Result |
|---|---|
| Quantization | `gemma4:12b-it-qat` and `gemma4:12b-it-q8_0` both fail |
| Context size | 32768 / 65536 / 131072 all fail |
| Temperature | 0.0, 0.1, 0.2, 1.0 all fail |
| Tool ordering in the schema | no effect |
| `tool_choice` | not in `ChatRequest`, and Ollama ignores it |
| Prompt ordering (step-first vs base-first) | no effect |
| Rewriting the "always call list_documents first" line | no effect |
| Stripping unavailable tool names from the base prompt | no effect |
| Prompt length | stochastic; no clean threshold |

## Root cause

Two independent defects, both in `pacgate-agent`.

### 1. The step's declared tool was never used to narrow the tool surface

`WorkflowStep.tool` was only logged and copied into the result. The model was
offered all eleven tools on every step, so it was free to pick a different one.
The base system prompt actively pushes it the wrong way:

`crates/pacgate-agent/src/system_prompt_base.txt:51`
```
- Always call read_document or list_documents at the start of a task to discover what is available.
```

### 2. `generate_docx` rejects a `structure` sent as a JSON string

Models serialise their own argument blob, so `structure` arrives as a *string*.
`DocxBuilder::from_json` calls `.get("sections")` on it, which is always `None`
for a string, and the call fails with `structure must have 'sections' array`.
The document is never written and the step still reports a tool call.

A third, related failure: the string is sometimes **truncated** by the tier's
`max_tokens` (8192 on Mid), producing
`EOF while parsing an object at line 1 column 3684`.

## Model capability is the binding constraint

With the surface narrowed to `generate_docx` alone:

| Model | Size | Residency on this box | Calls `generate_docx` |
|---|---|---|---|
| `gemma4-legal:12b-chat` (Main) | 13 GB | 100% GPU, 131072 ctx | **0 / 5** — emits `list_documents`, and sometimes invents names never offered (`print_files`, `list_files`, `get_matter_summary`) |
| `gemma4:12b-it-qat` | 7.2 GB | — | 0 / 3 |
| `ornith-1.5:9b` | 8.4 GB | 100% GPU | **3 / 3** with 1 tool, **0 / 4** with all 11 |
| `qwen3.8-legal:27b-mid` (Mid) | 17 GB | **30% CPU / 70% GPU** | **3 / 3** with 1 tool |

The 27B is correct but does not fit: 17 GB against a 16 GB card, spilling 30% to
CPU, with 31 GB system RAM of which ~1 GB was free. It is **not** a viable
default on AIPC1 and was reverted.

The 12B is the only model that both fits and is the configured Main tier, and it
cannot follow a tool directive at all.

## Fix prepared (not deployed)

`crates/pacgate-agent/src/lib.rs`
- `run_with_router_and_tools(..., required_tool)` — narrows the offered tool
  surface to the step's declared tool. Falls back to the full surface (with a
  warning) when a step names a tool the agent does not implement.
- `parse_structure_string()` — accepts `structure` as a JSON string, and repairs
  a truncated one by closing open containers and dropping the incomplete
  trailing element.

`crates/pacgate-agent/src/workflow_executor.rs`
- passes `Some(step.tool.as_str())` so the narrowing actually applies.

`scripts/test-document-generation-e2e.ps1`
- `storage_path` is relative to the `/data` mount, not to `DATA_DIR`; the gate
  was building `/data/tenants/tenants/...` and failing on a file that existed.
- Windows PowerShell 5.1 decodes a JSON response as Latin-1 when the server omits
  a charset, so a Chinese `storage_path` came back as `é¡¹ç®æ¦åè¡¨_v1.docx`.
  Now read through `curl.exe` + `ConvertFrom-Json`.

The Rust changes compile cleanly (`cargo build --release --bin pacgate-server`,
no new warnings) but **do not close the gate on their own** — the 12B still
picks the wrong tool. They are a prerequisite, not a fix.

## What would actually close it

1. **Upstream a model that can follow the directive.** `ornith-1.5:9b` fits
   (8.4 GB, 100% GPU) and follows it when the surface is narrowed. Making it the
   Main tier, or adding a per-step tier, would close the gate without a 27B.
2. **Or** make the step's tool call deterministic in code — construct the
   `generate_docx` arguments from the step's `parameters` instead of asking the
   model to choose and serialise them. This removes the model from the decision
   entirely and is the only option that is robust across models.

Option 2 is the durable fix and belongs upstream, so the stack can stay pinned
to GHCR and be updated by pulling.

---

## Update 2026-10-23 — state on the pinned 0.2.2 stack

The stack now runs `ghcr.io/jzkk720/*:0.2.2`. The docgen gate still fails, and
the reason is unchanged: the fix is not in any published image.

What changed since the note above:

- The Rust changes described under "Fix prepared" were **reverted** from the
  tree. They compiled cleanly but did not close the gate, and keeping them made
  `test-release-provenance.ps1` fail correctly — two files that can reach a
  built image differed from the published `v0.2.2` revision, so a rebuild from
  the tag would not have matched what clients pull. Carrying an unshipped fix in
  the tree is worse than not carrying it: it makes the provenance gate lie.
- `v0.2.2` does **not** contain the fix (`run_with_router_and_tools` and
  `parse_structure_string` are absent from `v0.2.2:pacgate-agent/src/lib.rs`).
- The gate's own two defects were fixed and are committed: `storage_path` is
  resolved against the `/data` mount rather than `DATA_DIR`, and the document is
  read through `curl.exe` so Windows PowerShell 5.1 does not decode CJK as
  Latin-1. Those were masking the real failure with false ones.

Current gate output on 0.2.2:

```
[FAIL] a step actually invoked the document-generated tool
       tools_used across steps: 'list_documents'
[FAIL] the run CREATED a document row in the matter
RESULT: 8 passed, 2 failed
```

The recommendation is unchanged and now firmer: **construct the `generate_docx`
arguments from the step's `parameters` in code** rather than asking the model to
choose a tool and serialise its arguments. That removes the model from the
decision entirely, works on any model that fits the card, and belongs upstream so
this machine can keep pulling images instead of building them.