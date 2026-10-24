# Output evals — validating prompts and generations (baseline 2026-10-24)

**Decision this records:** document generation stays on `deepseek-v4.1-flash:cloud`
(MAIN). This is the validation layer that decision never had.

## 1. The gap this closed

The repo had **113 gate scripts**, **49 registered** in `run-all-checks.ps1`, and
**all 48 pre-existing gates asserted plumbing**: the mount is right, the file is
OOXML, the tool name appeared in `tools_used`, the row exists in the DB.

Measured before writing anything:

```
CITATIONS block mentioned in any gate ............ 0
gates asserting read_document after generate_docx . 0
grep 'citation|引用|草稿|fabricat|hallucin' ....... 2 hits,
                                                   both unrelated identity
                                                   warnings in
                                                   test-sync-capability.ps1
```

`test-document-generation-e2e.ps1` is the deepest existing gate. It stops at
"text is non-empty and CJK round-tripped". Nothing asserted the document was
*correct*.

That mattered because `system_prompt_base.txt`
(`crates/pacgate-agent/src/`) mandates three behaviours that were never checked:

| Base-prompt mandate | Enforced before | Enforced now |
|---|---|---|
| `<CITATIONS>` block, verbatim ≤ 25 words | parsed, never verified | `citation_integrity.py` |
| H1→H2→H3, no skipped levels, signature page | ❌ | still ❌ (see §7) |
| `read_document` after `generate_docx` | ❌ | still ❌ (see §7) |

`extract_citations()` in `pacgate-agent/src/lib.rs:873` **parses** the verbatim
field and passes it to `CitationRef.verbatim`, which reaches the HTTP response.
Nothing compared it to the source document. **A fabricated quote was structurally
indistinguishable from a real one** — both are non-empty strings in a field nobody
verified.

## 2. What was built

Five scripts under `scripts/eval/`, plus one gate wrapper.

| File | Kind | What it asserts |
|---|---|---|
| `prompt_contract_lint.py` | static code grader | every document-producing prompt carries the draft / citation / uncertainty clause |
| `citation_integrity.py` | code grader (live) | every cited `verbatim` occurs in the document it names |
| `answer_substance.py` | code grader (live) | the fixture's planted facts are carried into the output |
| `generation_reliability.py` | code grader (live) | the producing step produces, measured as a **rate** |
| `build_fixtures.py` | fixture builder | deterministic synthetic corpus, no client data |
| `fixture_provisioning.py` | shared setup | matter + uploaded document, so evals do not measure an empty matter |
| `test_citation_integrity_grader.py` | self-test | the grader can FAIL |
| `test_answer_substance_matching.py` | self-test | the matcher cannot false-green |
| `run-evals.ps1` | suite runner | **separate from `run-all-checks.ps1`** |
| `scripts/test-prompt-contract.ps1` | gate wrapper | registers the static lint in the 49-gate suite |

## 3. The headline finding: the prompts do not carry the red line

Measured across **220 workflow prompts in 15 YAMLs** (219 of them on a
`generate_docx` step):

| Red-line clause | Prompts carrying it |
|---|---|
| `RED_LINE_DRAFT` — output is a draft for review | **4 / 219 (1.8%)** |
| `RED_LINE_CITATION` — every conclusion names its source | **103 / 219 (47.0%)** |
| `RED_LINE_UNCERTAIN` — an unfound source is reported, not filled | **13 / 219 (5.9%)** |

These are the 红线 from `SOUL_Sylvie_v1.0.md` §禁止事项:

> 不出具"最终法律意见"——我的一切法律产出都是供她复核的草稿
> 检索不到依据时如实报告，不得用模型自身知识或网络内容无声填补法律结论

A `generate_docx` prompt that omits them asks the model to produce exactly what
the charter forbids. **215 of 219 currently do.**

### Why this is structural, not sloppiness

`compose_combined_prompt()` (`workflow_executor.rs`) concatenates persona + DD +
step prompt with a bare `"\n\n"`. `build_system_prompt()` then injects that blob
under the heading:

```rust
sections.push(format!("## PRACTICE AREA INSTRUCTIONS\n\n{persona}"));
```

So a step prompt arrives labelled "PRACTICE AREA INSTRUCTIONS", competing with the
base prompt's citation mandate **at equal weight, with no precedence marker**. When
a step prompt says nothing about citations (116 of 219), the model is told to cite
by a rule whose priority relative to the step prompt is unstated.

## 4. The gate ratchets, and that is deliberate

219 prompts fail today. Failing every run makes the suite permanently red, which is
the documented way a gate stops being read — the same reasoning behind
`check-tracked-file-size.ps1` separating "newly staged" (FAIL) from
"already committed" (known debt).

So `scripts/eval/baseline-prompt-contract.json` records the accepted 219 and the
gate fails only on a **new** prompt shipping without a clause. The count prints on
every run so the debt stays visible. **The baseline is only allowed to shrink.**

**Mutation-tested:** appending a clause-free `generate_docx` workflow took
`REGRESSIONS` from 0 → 1 and exit 1. Reverted.

## 5. Live measurements

### Citation integrity — PASS

```
provisioned matter with document (equity-transfer-agreement fixture)
RESULT: PASS - all 19 verifiable citation(s) occur verbatim in their source
```

Real citations verified end-to-end, including one with an extraction-inserted
space (`查封 或其他`), which the whitespace-stripping normaliser absorbed. This is
why the normaliser exists: extraction re-wraps CJK mid-word.

### Answer substance — PASS

```
RESULT: PASS - all 6 planted fact(s) carried into the output.
This proves the FACTS survived, NOT that the legal analysis is sound.
```

Citation integrity alone is not enough. A memo can cite ten genuine sentences and
still state the wrong number:

```
document : "四十五（45）个自然日内一次性支付全部价款"
output   : "付款期限为三十（30）日 [3]"     <- real quote, wrong reading
```

Every other check passes that. `answer_substance.py` asks the second question.

### Generation reliability — 2/3 on the first sample, 3/3 after

```
run 1: http=200 tools=16 called_generate=False cap=True  docs 4->4 => CAPPED
run 2: http=200 tools=5  called_generate=True  cap=False docs 4->5 => PRODUCED
run 3: http=200 tools=5  called_generate=True  cap=False docs 4->5 => PRODUCED
produced : 2/3    capped : 1/3
```

**This is the documented 1-in-3 failure, reproduced.** The `generate_docx` step hit
its tool-round cap after 16 calls, returned empty content, produced no document —
and the route still answered **HTTP 200**. `test-document-generation-e2e.ps1` runs
the route once, so a single-shot gate passes this stack about two times in three.
`generation_reliability.py` is the only thing that reports it.

### A second finding: an empty matter gives a silent empty success

The first version of the reliability probe created a matter with **no document**.
Result on **3 of 3 runs**:

```
run 1: http=200 tools=3 called_generate=False cap=False docs 0->0 => SILENT-EMPTY
run 2: http=200 tools=2 called_generate=False cap=False docs 0->0 => SILENT-EMPTY
run 3: http=200 tools=0 called_generate=False cap=False docs 0->0 => SILENT-EMPTY
```

HTTP 200, zero tool calls, no document, **no `max_rounds_reached` flag, no error**.
Indistinguishable from success unless the documents table is checked. This is the
D3 class again: a workflow asked to generate from nothing reports success and
produces nothing.

The harness now provisions a document (`fixture_provisioning.py`) so this is not
misattributed to the model. **The empty-matter behaviour itself is a real defect
and is not yet fixed** — see §7.

## 6. Why the evals are a SEPARATE suite

- They are slow and cost a real generation each. The 49-gate suite is already
  ~20 minutes; mixing them in makes it slow enough that people stop running it.
- They answer a different question. A gate is binary and deterministic ("is the
  mount right"); an eval is a **rate** ("does generation work 2 times in 3").
  Conflating the two lets a probabilistic result block a release, or a binary
  gate inherit a probabilistic excuse.

Same exit-code contract as the live-stack gates: `0` pass, `1` real failure,
`2` CANNOT CHECK (no stack / no credentials), and `2` never fails the run.

## 7. Egress policy: no LLM judge, deliberately

Every eval here is a **code grader**. No model grades anything.

Grading cloud-generated output with a cloud judge would open a **second egress
path** that `test-chat-no-auto-egress.ps1` and `audit-sanitized-chunk-egress.ps1`
exist to close. Since MAIN is now cloud, output already leaves the box once for
generation; sending it again for grading doubles that for no deterministic gain.

A judge lane is possible later against the **local** `qwen3.8-legal:27b-mid`
(already on the box, 262k context, tools-capable) — but only on top of a
calibrated code-graded baseline, and it must stay local when it lands.

### Why the fixtures are synthetic

The repo had **zero** fixtures. The only real legal documents in the tree are
百宸 client material already tracked in a public repo (a 37.7 MB due-diligence
scan among them). Making those the test corpus would read client documents on
every run and widen an exposure that is already an open incident (AGENTS.md
"Credentials safety").

So fixtures are **built from text in `build_fixtures.py`**, following
`test-legal-journey.ps1`'s precedent of building its PDF in-container. A fixture
change shows up in a diff; no client document becomes test data.

## 8. Grader self-tests: three false-greens caught before they shipped

Both self-tests exist because this repo has twice shipped a grader unable to fail
(a silently skipped 60 of 832 files; a collapsed 19-element JSON array — both
reported green).

| Caught | Detail |
|---|---|
| `@()` collapses under PS 5.1 | already known from 2026-10-23; `run-evals.ps1` uses the assign-then-wrap form |
| **`45` matched inside `9145010000`** | the substance matcher used a plain substring test and reported the payment term PRESENT in an output whose only digits were an unrelated registration number |
| **vacuous mutation test** | the first prompt-gate mutation used a relative path, resolved from the wrong directory, never applied — so the "PASS" proved nothing. Re-run with an absolute path, it correctly failed |

The `45` false-green is now fixed with a **digit-boundary rule** (a fact starting
or ending with a digit must not be adjacent to another digit). 13 matching cases
pin the behaviour.

## 9. Current state

```
run-all-checks.ps1  ->  ALL 49 GATES PASSED (14 live-stack gates checked separately)
run-evals.ps1       ->  EVALS: 7 passed, 0 failed, 0 cannot check
```

The one `CANNOT CHECK` is `test-model-picker-e2e.ps1` (exit 2): no deer-flow
credential on this box. Not a failure.

## 10. What this does NOT cover

Stated so a green result is not read as more than it earned.

| Gap | Why it matters |
|---|---|
| **Legal analysis quality** | The evals prove facts and quotes survived. They cannot tell whether the reasoning is sound. That still needs a lawyer. |
| **H1→H2→H3 and signature page** | In the base prompt, unchecked. Mechanical to add to `citation_integrity.py`'s docx read; not done here. |
| **`read_document` after `generate_docx`** | In the base prompt, unchecked. `test-document-generation-e2e.ps1` checks the tool was called, not that it was called *after*. |
| **Citation count ≠ coverage** | 19 verified citations proves they are real, not that every claim needing one has one. |
| **Empty-matter silent success** | Reproduced 3/3 (§5). Not fixed. Should be its own gate. |
| **The 219 clause-free prompts** | Accepted as debt. The ratchet stops new ones; the existing ones still ship the behaviour the charter forbids. |
| **Draft label vs. actual draft behaviour** | `RED_LINE_DRAFT` at 1.8% is the largest gap. Adding the clause to the base prompt's step-prompt composition would fix all 219 at once — but it changes generated output, so it needs a deliberate decision, not a silent edit. |

## 11. Recommended next step, in priority order

1. **Fix the 1-in-3 generation cap** (§5). It is the highest-severity finding: HTTP
   200, no document, no error. A lawyer sees success and gets nothing.
2. **Make the empty matter fail loudly** instead of returning a silent 200.
3. **Decide the draft-label question deliberately.** Either add it to the base
   prompt so all 219 inherit it, or accept that 215 prompts do not ask for it.
   Do not leave it unstated.
4. **Add the docx structure checks** (H1→H2→H3, signature page) to
   `citation_integrity.py` — the file is already opened and parsed there.
5. **Only then** consider the local-judge lane for analysis quality, calibrated
   against this code-graded baseline.

## 12. Follow-up, same day: the prompt half is fixed and verified

Items 1 and 3 above were root-caused and acted on. This section records what
changed, including a regression I introduced and then fixed.

### 12.1 Root cause of the silent generation failure

`pacgate-agent/src/lib.rs:634` binds **all 44 tools every round**:

```rust
let tools = tool_definitions();
```

The step's declared tool is sent only as **prose** ("Call `generate_docx`…").
Nothing constrains the model to it. Measured on workflow `...0301`, step
`Generate review memo`:

```
tools_used: read_document, list_documents, kb_search, legal_search x17
max_rounds_reached: true      documents created: 0      HTTP: 200
```

`max_rounds: 10` is **rounds, not tool calls** — 20 calls across 10 rounds is
consistent, so the cap is correct. It is being *reached* because nothing stops
the model wandering.

Two further defects found while tracing:

| Defect | Location | Consequence |
|---|---|---|
| `citations: Vec::new()` on the break-out path | `lib.rs:794` | a run that cited 9 documents returns **zero** citations if it later hits the cap |
| `answered = closing.is_some()` | `lib.rs:788` | `Some("")` reports `answered=true` — **the log lied**, which is why this survived a release |

### 12.2 The prompt fix, and the regression it caused

`scripts/eval/inject_red_line_clauses.py` injects the three clauses into every
document-producing prompt. Idempotent, and it **replaces** a previously injected
block rather than stacking, so a wording change is safe to re-run.

Result: **219/219 prompts now carry all three clauses** (was 4 / 103 / 13), all
15 YAML files still parse (PyYAML), 220 workflows intact, library still served
(222 workflows / 46 categories).

**But the first wording caused a regression.** It said:

> 须标注来源（法律法规名称与条文号、案号或文件出处）

which reads as "produce a statute citation". The model went hunting for statutes
— `legal_search` **17 times** — hit the round cap, and never generated:

```
before injection : produced 3/3
after  injection : produced 0/3   (all CAPPED, tools=18-20)
```

Corrected wording names the **reviewed document** as the source, makes statute
citation conditional ("如需引用"), and adds an explicit anti-wander instruction
("完成必要的阅读后即调用 generate_docx 输出"). After the fix:

```
produced 3/3, capped 0/3, tool calls 3-5 (was 20)
```

**This is the strongest argument for the Rust fix:** a single ambiguous sentence
in a prompt cost the entire deliverable. Prompt wording is not a reliable
control surface.

### 12.3 The draft label now appears in real output

Three generated documents, read from disk:

```
股权转让协议-条款审查备忘录.docx              draft_label=True
股权转让协议-条款审查备忘录（受让方立场）.docx  draft_label=True
股权转让协议_条款审查备忘录_受让方立场.docx     draft_label=True
    -> 文件性质 草稿，供律师复核后使用，不构成最终法律意见
```

One also self-reports: "所引用的协议内容均标注协议条款号；所引用的法律法规均标注名称与条文号".

**This is still model-dependent.** The deterministic guarantee is a paragraph in
`pacgate-docx/src/builder.rs`, which needs a rebuild — see
`runtime/RUST-FIXES-SILENT-GENERATION-2026-10-24.md`.

### 12.4 A flaky eval, fixed

`answer_substance.py` failed once in a full-suite run and passed on re-run.
Diagnosed rather than re-run until green: it graded **step narration**, but the
deliverable is the **.docx**, and a summary legitimately omits detail the
document carries. Measured 2 of 3 runs reporting `RMB 48,000,000.00` missing
while the memo contained it.

Now grades the generated document (read via the same extract endpoint the
product uses), with narration only as a fallback. Stable across 3 consecutive
runs, and it prints which source it graded so the distinction is never silent.

### 12.5 The ratchet is now strict

`baseline-prompt-contract.json` went from **219 accepted failures to 0**. The
gate now fails on *any* prompt missing a clause. Mutation-tested after the
shrink: appending a clause-free workflow still produced `REGRESSIONS: 1`, exit 1.

### 12.6 Verified state

```
run-all-checks.ps1  ->  ALL 49 GATES PASSED (14 live-stack checked separately)
run-evals.ps1       ->  EVALS: 7 passed, 0 failed, 0 cannot check
```

### 12.7 Still open

| Item | Why it is not done |
|---|---|
| Tool restriction per step (root cause) | Rust; `docker.io` unreachable here, no `cargo`, API not bind-mounted. Spec: `runtime/RUST-FIXES-SILENT-GENERATION-2026-10-24.md` |
| Citations preserved on break-out | same |
| Honest `answered` flag | same |
| Deterministic draft label in the builder | same — and the wording needs 百宸 sign-off |
| Non-200 when a document step produces nothing | changes the API contract; needs a decision |
| Empty-matter silent success | reproduced 3/3, not fixed |
| H1→H2→H3 / signature page checks | not added |

