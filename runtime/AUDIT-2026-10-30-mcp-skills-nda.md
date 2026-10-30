# AUDIT + REMEDIATION 2026-10-30 — deer-flow MCP / skills / NDA-review

**Scope:** the live `pacgate-ai-bundle` stack, pinned to the upstream release
`0.2.7` (`ghcr.io/jzkk720/deer-flow-pacgate:0.2.7`).
**Status:** audit complete; six root causes found, five fixed and verified live.
One fix (2.6, the interactive thinking default) is **reverted and open** — it
needs a frontend image rebuild, which this machine must not do. The pre-existing
NDA docx set has been **regenerated clean** (3.3).

> **Deployment model — read this before the fixes below.**
> This machine runs the **upstream-pinned ghcr stack**. It does **not** build
> local images, and it does **not** bump the version ahead of upstream. Every
> fix here is therefore a **bind-mounted patch** over the pinned `0.2.7` image
> (`./patches/*.py:/app/backend/...:ro`), applied with
> `up -d --force-recreate --no-deps`. Nothing in this document requires a new
> image tag, and no `0.2.8` exists — upstream's newest tag is `v0.2.7`.
>
> An earlier draft of this document claimed the fixes "ship in 0.2.8" and that
> the frontend had been "rebuilt as 0.2.8". **Both claims were wrong** and have
> been removed: three `0.2.8` images were built locally, never used by any
> container, and have been deleted; the version bumps in `README*`, the
> handbooks, `DEPLOYMENT-GUIDE.md`, `SETUP-AND-OPERATIONS*.md` and
> `Cargo.toml`/`Cargo.lock` were reverted. `compose.bundle.yaml` and
> `compose.prod.yaml` are back on `:0.2.7`.

---

## Part 1 — the five claims that prompted this audit

| # | Claim | Verdict | Proof |
|---|---|---|---|
| 1 | 元典 (yuandian) MCP not reachable | **FALSE** | 4/4 endpoints return 200 to a real MCP `initialize`; `tools/call` returned live statute text |
| 2 | 北大法宝 (pkulaw) MCP not reachable | **FALSE** | 9/9 endpoints return 200; `get_article` returned 第九条 with `timeliness: 现行有效` |
| 3 | officecli is not working | **PARTLY TRUE** — server healthy, *path contract* broken | MCP gate 13/13 PASS, but the tool rejected `/mnt/user-data/...` |
| 4 | skills cannot be loaded | **FALSE** | 60 skills load; `/api/skills` returns 60; slash activation fires |
| 5 | NDA-review.md cannot be generated | **FALSE** — caused by a missing Playbook | the run stopped at `ask_clarification` and never wrote the deliverable |

A bare unauthenticated `curl` to the yuandian / pkulaw URLs returns **401**,
which is the correct answer for a request with no `Authorization` header. With
the configured header both work. That is the likely origin of "not reachable".

Two further defects surfaced while verifying the above and are recorded here
because they were live and silent:

| # | Defect | Verdict | Proof |
|---|---|---|---|
| 6 | Multi-step document runs die at `GRAPH_RECURSION_LIMIT` | **TRUE** — budget was a *floor*, not a ceiling | thread `4de2965b` / run `27e0916c` died at 100 super-steps after both deliverables were already written |
| 7 | Interactive runs return "success but blank" | **PARTLY TRUE** — thinking was ON by default; blank reply is prompt-size dependent | 14 empty assistant messages across 2423; but a 200-token re-probe answered `OK` with thinking on, so it is not unconditional. **Not fixed** — needs a frontend rebuild (2.6) |

---

## Part 2 — root causes found and FIXED

All fixes below are **bind-mounted patches over the pinned `0.2.7` image**. None
of them changes an image tag, and none requires a rebuild.

### 2.1 MCP tool ARGUMENTS never had `/mnt/user-data` resolved → FIXED

`deerflow/sandbox/tools.py` owns `replace_virtual_path` and applies it in
`bash`, `read_file`, `write_file`, `glob`, `grep`, `ls`, `str_replace`.
`deerflow/mcp/tools.py` translated paths only in the **result**
(`_local_uri_to_virtual_path`) and passed **arguments** to the server verbatim:

```python
call_tool_result = await session.call_tool(original_name, arguments)
```

Every agent-facing surface tells the model to use `/mnt/user-data/...`, so a
document tool received a path that does not exist on the container filesystem:

```text
officecli_officecli({"command": "create /mnt/user-data/outputs/x.docx"})
  → ToolException: Error: Could not find a part of the path '/mnt/user-data/outputs/x.docx'.
officecli_officecli({"command": "create <real outputs path>/x.docx"})
  → Created: .../x.docx   (validate: no errors found)
```

The damage was worse than a clean error: the model recovered by calling `pandoc`
through the `bash` tool (whose command string IS rewritten) and shipped a .docx
that fails `officecli validate` with **16 schema errors**
(`w:nsid val='A990'` is not 4-byte hexBinary; `w:b` in the wrong `rPr` order).
Thread `7b05b461` recorded exactly that sequence.

**A second, deeper cause** surfaced when the first fix did not fire: `runtime`
is **never injected into MCP tools**. They are built as `StructuredTool` objects
with an explicit `args_schema`, so LangChain never inspects a Python signature
for a `Runtime` annotation and `runtime` arrives as `None`. The patch therefore
also derives the thread's paths from `Paths` keyed on the thread/user in the
LangGraph config — the same derivation `ThreadDataMiddleware` uses.

**Fix:** `patches/deer-flow-mcp-path-args.py`, mounted over
`deerflow/mcp/tools.py` in **both** compose files. It rewrites virtual path
tokens in every string value of the arguments (recursing into lists for
officecli's argv form and into nested objects), delegating to
`replace_virtual_paths_in_command` — the same resolver `bash` uses, so the two
surfaces cannot drift.

**Verified live** (thread `360aca0d`), every call on a virtual path:

```text
create   /mnt/user-data/outputs/officecli-mcp-probe.docx
add      /mnt/user-data/outputs/officecli-mcp-probe.docx /body --type paragraph --prop text="PacGate MCP 路径修复验证"
validate /mnt/user-data/outputs/officecli-mcp-probe.docx
  → "Validation passed: no errors found."
```

No pandoc fallback; CJK text intact. Log line confirmed:
`deerflow.mcp.tools - INFO - MCP argument path rewrite applied`.
Gate: `scripts/test-mcp-path-args.ps1` — **19/19 PASS**.

### 2.2 No Playbook at the path Step 0 reads → FIXED

`nda-review`, `contract-review`, `ma-agreement-review`,
`vcpe-financing-suite`, `dd-report-assembly` and `cold-start-interview` all
reference `.deer-flow/playbooks/<type>-playbook.md`. That path is **not
reachable from the sandbox**: the only virtual roots are `/mnt/user-data`,
`/mnt/skills`, `/mnt/acp-workspace`, and `.deer-flow` is the *gateway's*
directory, not the agent's. No playbook existed anywhere (searched `/` and
`/app`).

So Step 0 always fell through to `cold-start-interview`, which asks a
clarifying question and never writes the deliverable — the reported symptom
"NDA-review.md cannot be generated".

**Fix:**

1. `deploy/client-bundle/playbooks/nda-playbook.md` — the firm's red-line
   standard: R1–R8 (RED), Y1–Y8 (YELLOW), G1–G7 (GREEN), the 12-clause review
   checklist, source grading, and delivery requirements (officecli only, no
   hand-built OOXML, no pandoc).
2. `sandbox.mounts` in `deer-flow-config.yaml` publishes it read-only at
   `/mnt/playbooks` — the supported way to expose a directory, `read_only: true`
   so a run cannot rewrite the firm's standards.
3. All six SKILL.md files reference `/mnt/playbooks/...` (0 stale refs).
   `cold-start-interview` writes its profile to `/mnt/user-data/outputs/`
   (writable) and documents `/mnt/playbooks` as the read-only publication area.

`sandbox.mounts` is an **in-process path mapping**, not a filesystem mount — so
`ls /mnt/playbooks` from a container shell correctly reports "no such file".
Verified against the live provider instead:

```text
container : /mnt/playbooks/nda-playbook.md
resolved  : /app/backend/.deer-flow/playbooks/nda-playbook.md
exists    : True
readonly  : True
bytes     : 6781
```

Live config confirms the mapping:
`VolumeMountConfig(host_path='/app/backend/.deer-flow/playbooks',
container_path='/mnt/playbooks', read_only=True)`.

**Verified live** (thread `4de2965b`): the agent read the Playbook and cited its
clause numbers in both deliverables.

```text
NDA-redline.docx  → officecli validate: no errors found
  [RED] Clause 2: survival of 10 years ... (Ref: R1)
  [RED] Clause 3: Non-compete for 5 years ... (Ref: R2)
  [RED] Clause 4: Fixed RMB 5,000,000 ... (Ref: R3)
  [RED] Clause 5: Delaware law ... (Ref: R6)
NDA-review.md     → triage RED + per-clause table + pending items + disclaimer
```

(That run then hit the recursion limit — a separate pre-existing budget issue,
not a regression; both deliverables were already written and validated.)

### 2.3 14 skills declared tools that resolve to nothing → FIXED

`filter_tools_by_skill_allowed_tools` unions every `allowed-tools` declaration.
The union was larger than the loaded surface (162 in / 162 kept / 0 dropped), so
a bad declaration was invisible — until an operator narrows the surface.

Real defects found and removed:

| Skill | Declaration | Why it was wrong |
|---|---|---|
| diligence-issue-extraction, tabular-review | `markitdown` | markitdown is a **CLI** in the image, not an MCP tool. Reachable only via `bash`, which both skills already declare. |
| skill-reviewer | `review_skill_package` | no such tool in this build; the skill needs read_file/grep/glob/ls. |

The remaining 11 skills declaring `qcc-company` / `qcc-risk` / `qcc-legal-case`
are **correct**: those servers are configured and authenticated (probed 200;
60 tools total) and merely `enabled: false`. The declaration is right for a
deployment that turns them on.

Gate: `scripts/test-skill-tool-declarations.ps1` — **PASS** (3 passed,
3 legitimate warnings, 0 defects).

### 2.4 `audit-model-tags.ps1` failed on false positives → FIXED

The gate exited 1 claiming `gemma4-12b-local:latest` and
`ornith-1.5-9b-local:latest` were not pre-pulled. Both were false: it matched
`^\s*model:\s*(\S+)` across the **whole** file, including the `subagents:`
section where `model:` holds a deer-flow **model name**, not an Ollama **tag**.
`Normalize-Tag` appends `:latest` to a bare name.

**Fix:** scope the tag scan to the `models:` block (stop at the next top-level
key). Now exits 0. A red gate that is not red trains people to ignore it.

### 2.5 The recursion budget was a FLOOR, not a ceiling → FIXED

`DEERFLOW_MAX_RECURSION_LIMIT` was documented as a ceiling and implemented as a
clamp, but `build_run_config` hardcoded the *default* to 100:

```python
config: dict[str, Any] = {"recursion_limit": 100}   # deer-flow-run-recursion-cap.py:321
```

The clamp only ever raised a caller-supplied value up to the ceiling. A caller
that supplied **nothing** — the API and IM paths — got 100, and the ceiling was
never consulted. The chat UI sends `recursion_limit: 1000` on every run, which
is why the defect was invisible from the browser and fatal from the API.

**Why 100 is not enough here.** LangGraph charges ~**9.8 super-steps per LLM
call** in this graph, because nine middleware `after_model` / `before_model`
hooks are each their own node. A 100-step budget is therefore ~10 model calls.
Thread `4de2965b` (run `27e0916c`) finished its work at ~step 25 — both
deliverables written and validated — then spent the remaining ~75 steps on one
dead-end `pandoc` detour and died with *"Recursion limit of 100 reached without
hitting a stop condition"*.

Measured deepest **non-looping** workloads: `d35307ec` 5767 super-steps / 599
LLM calls, `f7f240f6` 3154, `dcced4b5` 1589. The two highest-step threads were
genuine loops (`d35307ec`: 2439 bash calls, 245 distinct = 10%; `dcced4b5`: 915
calls, 83 distinct = 9%) — that is what loop detection exists for, and it is not
a reason to keep the ceiling low.

**Fix:** the default now equals the ceiling, and the ceiling is 4000:

```python
config: dict[str, Any] = {"recursion_limit": _PACGATE_MAX_RECURSION_LIMIT}
```

`DEERFLOW_MAX_RECURSION_LIMIT` raised `"500"` → `"4000"` in **both** compose
files. Loop safety does not depend on this number: `LoopDetectionMiddleware`
layer 1 (identical tool-call hash, warn 3 / hard-stop 5), layer 2 (per-tool
frequency window, bash warn 100 / hard 150), `DEERFLOW_STREAM_IDLE_TIMEOUT_S`,
and the 420 s no-output stall detector all still apply.

Gate: `scripts/test-recursion-budget.ps1` — **was 4 failed / 7 passed → now
11/11 PASS** (R3, R4, R7, R8 were the failures).

### 2.6 Interactive runs shipped `thinking_enabled=true` by default → **OPEN** (reverted)

`frontend/src/core/threads/hooks.ts` computed:

```ts
thinking_enabled: context.mode !== "flash",
```

`DEFAULT_LOCAL_SETTINGS.context.mode` is `undefined`, so `undefined !== "flash"`
is **true** — thinking was ON for every first-turn run unless the user had
explicitly picked Flash. A second site compounded it: `getResolvedMode()` in
`input-box.tsx` returned `"pro"` whenever the model supported thinking, and its
effect runs on mount, so it wrote `mode: "pro"` into the thread context *before*
the first submit.

**Why that produced blank replies.** `deer-flow-config.yaml` already carries the
reasoning-burn fix for every thinking-capable model:

```yaml
when_thinking_disabled:
  reasoning_effort: none
```

but `deer-flow-model-factory.py` applies it **only when `thinking_enabled` is
false** (lines 138–148). With thinking on, the suppression never fired, and the
model spent the whole reply budget in the invisible `reasoning` channel.

Measured on the live stack — 2423 unique assistant messages scanned:

| Model | Total | Empty | Rate |
|---|---|---|---|
| `deepseek-v4.1-flash` | 2152 | **12** | 0.6% |
| `gemma4:12b-it-qat` | 47 | 1 | 2.1% |
| `nemotron-3.5-lightning:30b-a3b` | 20 | 1 | 5.0% |
| `glm-5.3-flash` | 191 | 0 | 0.0% |

All 14 empties carried `finish_reason=length` with the full budget consumed.
Reproduced deterministically on `gemma4:12b-it-qat`, same prompt, `max_tokens=200`:

| Setting | Latency | `finish_reason` | content | reasoning |
|---|---|---|---|---|
| thinking ON | 7.1 s | `length` | **0 chars** | 649 chars |
| `reasoning_effort: none` | 0.4 s | `stop` | 32 chars | 0 chars |

**Fix — WRITTEN, THEN REVERTED. This item is OPEN.**

The change was made in `deploy/frontend-patches/files/src/core/threads/hooks.ts`
(listing the thinking modes explicitly so an undefined mode falls through to
`false`). It was then reverted, because that file is a **build-time source
override**: the frontend image ships compiled output only and has no source
mount, so the change cannot take effect without rebuilding
`deer-flow-frontend-pacgate`. Rebuilding is out of scope on this machine — the
stack is pinned to upstream ghcr images (see the deployment-model note at the
top). The override file is left byte-identical to the pinned image.

**Re-measurement 2026-10-30 — the blank-reply claim did NOT reproduce.**
Same model, same `max_tokens=200`, against the live Ollama endpoint:

| Setting | content | reasoning | `finish_reason` |
|---|---|---|---|
| thinking ON (default) | `OK` | 134 chars | `stop` |
| `reasoning_effort: none` | `OK` | 0 chars | `stop` |

Both answered. The earlier 0-char observation came from a run that exhausted the
whole budget on reasoning, which needs a much longer prompt than a one-word
reply — so the defect is **conditional on prompt size**, not unconditional. The
14 empty messages in the 2423-message scan are real, but they are a
long-prompt/large-budget phenomenon.

**What is already correct:** every thinking-capable model in
`deer-flow-config.yaml` carries `when_thinking_disabled: {reasoning_effort: none}`,
and `deer-flow-model-factory.py` applies it whenever `thinking_enabled` is false.
So the mitigation is in place; only the *default* is wrong.

**Workaround until upstream changes the default:** pick **Flash** mode
explicitly. That sets `thinking_enabled: false` and lets
`when_thinking_disabled` suppress the reasoning channel.

### 2.7 `deer-flow-sandbox-tools.py` existed but was mounted nowhere → FIXED

The patch that adds the binary-file hint to `read_file` (so an agent that opens
a `.docx` is told to use `officecli validate` / `officecli get ... --json`
instead of `pandoc`) was present in `patches/` and mounted in **neither** compose
file. The fix was inert. Added the mount to both files (A5 parity) and verified
the hint text is live in the container.

---

## Part 3 — remaining items

### 3.1 Recursion budget — **FIXED** (see 2.5)

Was: thread `4de2965b` hit `GRAPH_RECURSION_LIMIT` at 500 after 6 mandated steps
on `gemma4-12b-local`. Both deliverables were produced first, so it was a budget
ceiling, not a correctness bug. Now: default = ceiling = 4000, gate 11/11.

### 3.2 Interactive thinking default — **OPEN** (see 2.6)

Was: `thinking_enabled: context.mode !== "flash"` with `mode: undefined` meant
thinking was ON by default, defeating `when_thinking_disabled`. The fix needs a
frontend image rebuild, which this machine must not do — the stack is pinned to
upstream ghcr images. Reverted; workaround is to pick Flash mode explicitly.

### 3.3 Pre-existing NDA docx set — **FIXED (regenerated 2026-10-30)**

The 2026-10-29 deliverables in thread `d35307ec` carried validation errors:

| File | Before | After |
|---|---|---|
| `保密协议_甲方版修订稿_带批注_供律师复核.docx` | **89** | **0** |
| `保密协议_清洁稿_供律师复核.docx` | **89** | **0** |
| `保密协议_审查备忘录_RED分流.docx` | **65** | **0** |

The dominant classes were hand-built-XML artefacts, not content problems:

- `<w:b/>` emitted **after** `<w:bCs/>` inside `<w:rPr>` — OOXML requires
  `b` before `bCs`, so every bold run was a schema violation.
- `<w:tblHeader w:val="true"/>` — the attribute is an ST_OnOff enumeration;
  `true` is rejected, `1` / `on` is required.
- `<w:updateFields>` and `<w:zoom>` written as children of `<w:settings>` in an
  order the schema does not allow.

These needed **regeneration**, not repair. Done on the pinned `0.2.7` stack —
the two fixes it depended on are bind-mounted patches, not image changes: the
`officecli` path contract (2.1, `deer-flow-mcp-path-args.py`) and the
`read_file` binary hint (2.7, `deer-flow-sandbox-tools.py`).

The regenerated set is in the same `outputs/` directory; the invalid originals
are preserved under `outputs/archive-2026-10-29-invalid/`. The new set also
carries what the old one lacked — Playbook clause citations:

| File | Playbook refs | `validate` |
|---|---|---|
| `保密协议_审查备忘录_RED分流.docx` | R1, R3, R4, R5, R8 / Y2, Y3, Y5, Y7 | 0 errors |
| `保密协议_甲方版修订稿_带批注_供律师复核.docx` | G1, G6 + per-clause 批注 | 0 errors |
| `保密协议_清洁稿_供律师复核.docx` | (clean copy — no annotations by design) | 0 errors |

### 3.4 `officecli set` rejects the path syntax `get` accepts — **OPEN (upstream)**

Found while regenerating 3.3. `officecli` is internally inconsistent:

| Command | `body/p[1]` | `/body/p[1]` |
|---|---|---|
| `get` | ✅ | ✅ |
| `set` | ❌ `No elements matched selector` | ✅ |

The sandbox's `validate_local_bash_command_paths` rejects any `/`-prefixed token
on a bash command line as an unsafe absolute path, so the only form `set`
accepts is the one the sandbox forbids. **Workaround (verified):** put the
commands in a JSON file and use `officecli batch <file> --input <json>` — the
`/` then lives in file content, not in the command string. Measured: 4/4
commands succeeded, `validate` clean, CJK intact.

This is documented in `playbooks/nda-playbook.md` §四 so every skill that
generates documents inherits it. The underlying inconsistency is an upstream
`officecli` defect and should be reported rather than patched locally.

---

## Part 4 — verification

| Gate | Result |
|---|---|
| `test-mcp-path-args.ps1` (new) | **19/19 PASS** |
| `test-skill-tool-declarations.ps1` (new) | **PASS** (3 passed, 0 defects, 3 legitimate warnings) |
| `test-recursion-budget.ps1` (new) | **was 4 failed / 7 passed → 11/11 PASS** |
| `test-officecli-mcp.ps1` | 13/13 PASS |
| `test-officecli-set-contract.ps1` (new) | **8/8 PASS** — pins the `set`/`batch --input` contract |
| `test-tool-search-deferral.ps1` | 25/25 PASS |
| `test-deferred-tool-runtime.ps1` | 17/17 PASS |
| `test-workflow-compose-wiring.ps1` | PASS — A5 patch-mount parity across the same **27** patches in both compose files |
| `test-mcp-tool-surface.ps1` | 6/6 PASS |
| `test-stack-version-coherence.ps1` | 14/14 PASS |
| `audit-model-tags.ps1` | **was FAIL → now PASS** (exit 0) |
| live `/mnt/playbooks` resolution | resolves, exists, `read_only: True` |
| live `DEERFLOW_MAX_RECURSION_LIMIT` | **4000** in the running container |
| regenerated NDA docx set | **0 / 0 / 0** schema errors (was 89 / 89 / 65) |

Live runs:

| Thread | Model | Outcome |
|---|---|---|
| `360aca0d` | gemma4-12b-local | officecli on `/mnt/user-data/...` → created, validate clean, CJK intact, no pandoc |
| `4de2965b` | gemma4-12b-local | Playbook read; `NDA-redline.docx` (0 validation errors, R1/R2/R3/R6) + `NDA-review.md` (RED, per-clause table, disclaimer) |
| `dbe26d90` | deepseek-v4.1-flash-cloud | **regeneration of 3.3** — 3 docx, all 0 schema errors, Playbook refs R1/R3/R4/R5/R8 + Y2/Y3/Y5/Y7 + G1/G6 |
| `353a869f` | deepseek-v4.1-flash-cloud | 3 docx, 0 schema errors, but **no Playbook refs** — the prompt omitted Step 0. Kept as evidence that the citation requirement is prompt-driven, not automatic |
| `7c68c8a8` | deepseek-v4.1-flash-cloud | 599 s, **0 deliverables** — agent burned the budget probing officecli schema. This is the run that surfaced 3.4 |

Reproduction evidence for 2.6 (live Ollama, `gemma4:12b-it-qat`, `max_tokens=200`,
identical prompt):

| Setting | Latency | `finish_reason` | content | reasoning |
|---|---|---|---|---|
| thinking ON | 7.1 s | `length` | **0 chars** | 649 chars |
| `reasoning_effort: none` | 0.4 s | `stop` | 32 chars | 0 chars |

**Re-measured 2026-10-30 — this did NOT reproduce.** Same model, same
`max_tokens=200`, same one-word prompt:

| Setting | content | reasoning | `finish_reason` |
|---|---|---|---|
| thinking ON | `OK` | 134 chars | `stop` |
| `reasoning_effort: none` | `OK` | 0 chars | `stop` |

Both answered. The 0-char result needs a prompt long enough to exhaust the whole
budget on reasoning, so the defect is **conditional on prompt size**, not
unconditional. At a realistic budget (`max_tokens=8192`) thinking works — 29.5 s,
148 chars content, 2793 chars reasoning on a 3-clause review. The defect was
never "thinking is broken"; it is "thinking is on when the caller did not ask for
it, and the reply budget is shared with the reasoning channel".

## Files changed

```text
pacgate-ai/deploy/client-bundle/patches/deer-flow-mcp-path-args.py   new  (frozen mount base)
pacgate-ai/deploy/client-bundle/patches/deer-flow-sandbox-tools.py  new  (read_file binary hint)
pacgate-ai/deploy/client-bundle/playbooks/nda-playbook.md           new
pacgate-ai/deploy/client-bundle/playbooks/nda-playbook.md           +officecli set/batch contract
pacgate-ai/deploy/client-bundle/compose.bundle.yaml                 +2 mounts, ceiling 500->4000
pacgate-ai/deploy/client-bundle/compose.prod.yaml                   +2 mounts, ceiling 500->4000 (A5 parity)
pacgate-ai/deploy/client-bundle/deer-flow-config.yaml               +sandbox.mounts ->/mnt/playbooks
pacgate-ai/deploy/client-bundle/patches/deer-flow-run-recursion-cap.py
                                                                    default = ceiling, not 100
pacgate-ai/scripts/test-mcp-path-args.ps1                           new gate
pacgate-ai/scripts/test-skill-tool-declarations.ps1                 new gate
pacgate-ai/scripts/test-recursion-budget.ps1                        new gate
pacgate-ai/scripts/test-officecli-set-contract.ps1                  new gate (set/batch contract)
pacgate-ai/scripts/audit-model-tags.ps1                             scope tag scan to models:
deer-flow/skills/public/{nda-review,contract-review,ma-agreement-review,
  vcpe-financing-suite,dd-report-assembly,cold-start-interview}/SKILL.md
                                                                     /mnt/playbooks paths
deer-flow/skills/public/{diligence-issue-extraction,tabular-review}/SKILL.md
                                                                     drop dead markitdown
deer-flow/skills/public/skill-reviewer/SKILL.md                      drop dead review_skill_package
```

**Reverted, deliberately — do not re-apply without a rebuild decision:**

```text
pacgate-ai/deploy/frontend-patches/files/src/core/threads/hooks.ts        thinking default
pacgate-ai/deploy/frontend-patches/files/src/components/workspace/input-box.tsx  mode default
pacgate-ai/README.md, README-ZH.md, deploy/AIPC-DEPLOYMENT-HANDBOOK*.md,
  deploy/DEPLOYMENT-GUIDE.md, deploy/SETUP-AND-OPERATIONS*.md,
  pacgate-ai/Cargo.toml, pacgate-ai/Cargo.lock                            0.2.8 version bumps
```

The frontend overrides are build-time source, so they only take effect after
rebuilding `deer-flow-frontend-pacgate` — out of scope on this machine. The
version bumps had no upstream release behind them (upstream's newest tag is
`v0.2.7`) and were reverted along with the compose image pins.

The Playbook is published from `deploy/client-bundle/playbooks/` into
`data/deer-flow/playbooks/` (the bind-mounted `.deer-flow`). A redeploy copies
it; `install.ps1` does not manage that directory.
