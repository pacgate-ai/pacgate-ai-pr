# AUDIT + REMEDIATION 2026-10-30 — deer-flow MCP / skills / NDA-review

**Scope:** the live `pacgate-ai-bundle` stack, deer-flow 0.2.7
(`ghcr.io/jzkk720/deer-flow-pacgate:0.2.7`).
**Status:** audit complete; fixes implemented and verified live.

---

## Part 1 — the four claims that prompted this audit

| Claim | Verdict | Proof |
|---|---|---|
| 元典 (yuandian) MCP not reachable | **FALSE** | 4/4 endpoints return 200 to a real MCP `initialize`; `tools/call` returned live statute text |
| 北大法宝 (pkulaw) MCP not reachable | **FALSE** | 9/9 endpoints return 200; `get_article` returned 第九条 with `timeliness: 现行有效` |
| officecli is not working | **PARTLY TRUE** — server healthy, *path contract* broken | MCP gate 13/13 PASS, but the tool rejected `/mnt/user-data/...` |
| skills cannot be loaded | **FALSE** | 60 skills load; `/api/skills` returns 60; slash activation fires |
| NDA-review.md cannot be generated | **FALSE** — caused by a missing Playbook | the run stopped at `ask_clarification` and never wrote the deliverable |

A bare unauthenticated `curl` to the yuandian / pkulaw URLs returns **401**,
which is the correct answer for a request with no `Authorization` header. With
the configured header both work. That is the likely origin of "not reachable".

---

## Part 2 — root causes found and FIXED

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

---

## Part 3 — remaining items (not fixed; ranked)

1. **Recursion budget vs. multi-step document runs.** Thread `4de2965b` hit
   `GRAPH_RECURSION_LIMIT` at 500 after 6 mandated steps on `gemma4-12b-local`.
   Both deliverables were produced first, so this is a budget ceiling, not a
   correctness bug. Options: raise `DEERFLOW_MAX_RECURSION_LIMIT` for document
   skills, or make the skill's step list shorter.
2. **Interactive thinking default.** `frontend/src/core/threads/hooks.ts:2269`
   computes `thinking_enabled: context.mode !== "flash"`, and
   `DEFAULT_LOCAL_SETTINGS` sets `mode: undefined` — so thinking is **on**
   unless the user picks Flash. On `gemma4:12b-it-qat` that lets the model spend
   the reply budget in the `reasoning` channel and return **empty content**
   (measured: 94 content / 674 reasoning chars with thinking on; 191 / 0 with
   `reasoning_effort: none`). The background models already carry
   `when_thinking_disabled.reasoning_effort: none`; the interactive path does not.
3. **Pre-existing NDA docx set fails validation.** The 2026-10-29 deliverables in
   thread `d35307ec` show 65 / 89 / 89 `officecli validate` errors — the same
   hand-built-XML / pandoc class this audit fixed going forward. They need
   regeneration, not repair.

---

## Part 4 — verification

| Gate | Result |
|---|---|
| `test-mcp-path-args.ps1` (new) | **19/19 PASS** |
| `test-skill-tool-declarations.ps1` (new) | **PASS** (3 passed, 0 defects, 3 legitimate warnings) |
| `test-officecli-mcp.ps1` | 13/13 PASS |
| `test-tool-search-deferral.ps1` | 25/25 PASS |
| `test-deferred-tool-runtime.ps1` | 17/17 PASS |
| `test-workflow-compose-wiring.ps1` | PASS — A5 patch-mount parity across the same **26** patches in both compose files |
| `test-mcp-tool-surface.ps1` | 6/6 PASS |
| `audit-model-tags.ps1` | **was FAIL → now PASS** (exit 0) |

Live runs:

| Thread | Model | Outcome |
|---|---|---|
| `360aca0d` | gemma4-12b-local | officecli on `/mnt/user-data/...` → created, validate clean, CJK intact, no pandoc |
| `4de2965b` | gemma4-12b-local | Playbook read; `NDA-redline.docx` (0 validation errors, R1/R2/R3/R6) + `NDA-review.md` (RED, per-clause table, disclaimer) |

## Files changed

```text
pacgate-ai/deploy/client-bundle/patches/deer-flow-mcp-path-args.py   new  (frozen mount base)
pacgate-ai/deploy/client-bundle/playbooks/nda-playbook.md           new
pacgate-ai/deploy/client-bundle/compose.bundle.yaml                 +mount
pacgate-ai/deploy/client-bundle/compose.prod.yaml                   +mount (A5 parity)
pacgate-ai/deploy/client-bundle/deer-flow-config.yaml               +sandbox.mounts ->/mnt/playbooks
pacgate-ai/scripts/test-mcp-path-args.ps1                           new gate
pacgate-ai/scripts/test-skill-tool-declarations.ps1                 new gate
pacgate-ai/scripts/audit-model-tags.ps1                             scope tag scan to models:
deer-flow/skills/public/{nda-review,contract-review,ma-agreement-review,
  vcpe-financing-suite,dd-report-assembly,cold-start-interview}/SKILL.md
                                                                     /mnt/playbooks paths
deer-flow/skills/public/{diligence-issue-extraction,tabular-review}/SKILL.md
                                                                     drop dead markitdown
deer-flow/skills/public/skill-reviewer/SKILL.md                      drop dead review_skill_package
```

The Playbook is published from `deploy/client-bundle/playbooks/` into
`data/deer-flow/playbooks/` (the bind-mounted `.deer-flow`). A redeploy copies
it; `install.ps1` does not manage that directory.
