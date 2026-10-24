# Rust fixes for the silent-generation defect — NOT BUILT, NOT VERIFIED

**Status: unverified patch specification.** Written 2026-10-24 on a machine that
**cannot build it**. Read §0 before applying anything.

## 0. Why this is a spec and not a commit

`docker.io` / `registry-1.docker.io` is **unreachable from this box** (AGENTS.md
records this; re-verified 2026-10-24: `docker pull rust:1.94-bookworm` hangs
indefinitely, no `rust:` image is present locally, and `cargo` is not on the
host). `pacgate-api` is **not** bind-mounted for source — only `/data` and
`/app/workflows` — so a Rust change requires a full image rebuild.

Writing Rust I cannot compile would be unverifiable code presented as a fix. So
this file specifies the changes precisely enough to apply on a machine that can
build, and states what each one is for. **Nothing here has been compiled or run.**

## 1. Root cause (established, not guessed)

`pacgate-agent/src/lib.rs:634`:

```rust
let tools = tool_definitions();   // ALL 44 tools, every round
```

The step's declared tool is sent only as **prose** by `build_step_message`
("Call `generate_docx` to complete this step"). Nothing constrains the model to
it. Measured 2026-10-24 on workflow `...0301`, step `Generate review memo`:

```
tools_used: read_document, list_documents, kb_search, legal_search x17
max_rounds_reached: true
documents created: 0
HTTP: 200
```

`max_rounds: 10` is **rounds, not tool calls** — 20 calls across 10 rounds is
consistent, so the cap is behaving correctly. It is being *reached* because
nothing stops the model wandering.

## 2. Fix 1 — restrict tools per step (the root cause)

**`pacgate-agent/src/lib.rs`** — add an optional allow-list to the loop.

```rust
// line ~625, signature
pub async fn run_with_router(
    &self,
    router: &Arc<LlmRouter>,
    history: Vec<AgentMessage>,
    user_message: &str,
    persona_prompt: Option<&str>,
    matter_id: Option<&MatterId>,
    allowed_tools: Option<&[String]>,      // NEW
) -> Result<AgentTurnResult> {
```

```rust
// line ~634
let tools = match allowed_tools {
    Some(allow) if !allow.is_empty() => tool_definitions()
        .into_iter()
        .filter(|t| allow.iter().any(|a| a == &t.function.name))
        .collect(),
    _ => tool_definitions(),
};
```

**`pacgate-agent/src/workflow_executor.rs:184`** — pass the step's tool.

```rust
.run_with_router(
    router, vec![], &user_message, combined_prompt.as_deref(), matter_id,
    Some(std::slice::from_ref(&step.tool)),   // NEW
)
```

**Why this and not a bigger `max_rounds`:** raising the cap buys more duplicate
documents, not an answer. The existing comment at `lib.rs:683` already records
that the model called `generate_docx` **nine times** in one turn — the cap is the
wrong lever.

**Risk to check when building:** some steps legitimately need a read before the
write (`read_document` then `generate_docx`). A single-tool allow-list would
break those. Safer first cut: allow `[step.tool]` **plus** the read-only tools
(`read_document`, `list_documents`, `find_in_document`, `kb_search`) and exclude
the open-ended research tools (`legal_search`, `web_search`) that caused the
wander. Verify against `test-document-generation-e2e.ps1` and
`test-legal-journey.ps1` before shipping.

## 3. Fix 2 — preserve citations on the break-out path

**`pacgate-agent/src/lib.rs:794`**

```rust
citations: Vec::new(),   // <-- discards citations already extracted
```

A run that cited 9 documents in round 3 returns **zero** citations if it later
hits the cap. Track the last non-empty extraction and return it:

```rust
// before the loop
let mut last_citations: Vec<CitationRef> = Vec::new();

// inside the loop, after `let citations = extract_citations(...)` on the
// natural-close path, also update it each round where content is present:
if !citations.is_empty() { last_citations = citations; }

// at the break-out return
citations: last_citations,
```

## 4. Fix 3 — make `answered` honest

**`pacgate-agent/src/lib.rs:788`**

```rust
answered = closing.is_some(),
```

`Some("")` reports `answered=true`. This is why the container log said
`answered=true` while the step content was empty — **the log lied**, which is
why this survived a release. Change to:

```rust
answered = closing.as_deref().is_some_and(|s| !s.trim().is_empty()),
```

## 5. Fix 4 — fail loudly when a document step produces nothing

**`pacgate-api/src/workflows.rs`** — after the step loop, if a step's `tool` is a
document-producing tool and no document row was created for the matter, return a
non-200 or set an explicit `produced: false` on the response.

**This changes the API contract.** `test-document-generation-e2e.ps1` asserts
`POST /api/workflows/:id/execute returns a result` and any client relying on 200
would need updating. Decide deliberately — a lawyer must not see success and get
nothing, but a silent contract change is its own defect.

## 6. Fix 5 — deterministic draft label (the guarantee)

**`pacgate-docx/src/builder.rs:104`** — `render_document_xml` already emits the
title as `Heading1`. Prepend a fixed paragraph above it:

```rust
// before the title
body.push_str(&para_with_style(
    "Normal",
    "草稿 — 供律师复核，非最终法律意见",
));
```

**Why this and not only the prompt clause:** the prompt clause is
model-dependent. Measured 2026-10-24, after injecting the clause into all 219
prompts, 3 of 3 generated documents carried the label — but that is a
probability, not a guarantee. A red line should not depend on the model
remembering. This paragraph cannot be skipped.

**Wording needs 百宸 sign-off** — the string above is a placeholder, not
approved 免责 language.

## 7. What was already fixed WITHOUT a rebuild

The prompt-side half is **done and verified** (see
`runtime/OUTPUT-EVALS-BASELINE-2026-10-24.md` §12): the red-line clauses are
injected into all 219 document-producing prompts, `/app/workflows` is
bind-mounted so it took effect immediately, and generated documents now carry
the draft label.

**A wording mistake worth recording:** the first clause version said "须标注来源
（法律法规名称与条文号…）", which read as "produce a statute citation". The model
then called `legal_search` 17 times and never generated. Generation went 3/3 →
**0/3**. The corrected wording names the reviewed document as the source, makes
statute citation conditional, and adds an explicit anti-wander instruction.
After the fix: 3/3 produced, tool calls down from 20 to 3–5.

That is the strongest argument for Fix 1: prompt wording alone is fragile, and a
single ambiguous sentence can cost the whole deliverable.
