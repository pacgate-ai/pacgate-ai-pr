# Upstream Handoff — AIPC1 deltas that upstream `main` does not have

> **For:** the maintainer of `JZKK720/pacgate-ai-pr`, or an agent working in that repo.
> **From:** AIPC1 (`pacgate-law`, compose project `pacgate-ai-bundle`), pinned to
> release **`0.2.7`**.
> **Date:** 2026-10-30.
> **Status:** AIPC1 is running and verified. This document is the **delta inventory
> plus verdict records** — it is not a request to re-do AIPC1's work, it is the list
> of things AIPC1 proved locally that upstream cannot see.

---

## Part 0 — System prompt for the upstream agent

Paste this into the upstream dev machine's agent before it touches anything.

```text
You are working in JZKK720/pacgate-ai-pr (upstream). AIPC1 — a separate deployment
machine — has been running this stack on release 0.2.7 and has accumulated a set of
local deltas that upstream main does NOT contain. Your job is to evaluate each one
and decide whether to adopt it upstream, not to re-derive it.

Ground rules:

1. EVIDENCE FIRST. Every claim in the handoff document you were given carries a
   file path, a commit, or a measured number. Verify it before acting. If you
   cannot reproduce a claim, say so and stop — do not "fix" something you could
   not confirm.

2. DO NOT TRUST THE VERSION NUMBER. AIPC1 briefly carried a local 0.2.8 that had
   no upstream release behind it. It was reverted. Upstream's newest tag is
   v0.2.7. If you see 0.2.8 anywhere, it is a mistake.

3. THE TWO HISTORIES ARE UNRELATED. `git diff upstream/main..HEAD` in the AIPC1
   repo reports every file as changed. Never use it. Compare content by blob SHA:
       git rev-parse upstream/main:<path>   vs   git rev-parse HEAD:<path>
   SAME means the swap will lose the delta.

4. AIPC1's `pacgate-ai/` subtree maps to YOUR repo root. AIPC1's
   `pacgate-ai/deploy/client-bundle/patches/x.py` is your
   `deploy/client-bundle/patches/x.py`.

5. SOME AIPC1 STATE IS MACHINE-LOCAL AND MUST NOT BE PORTED. The live MCP
   connector config (`deer-flow-extensions-config.json`) is gitignored and holds
   credentials. The 60 skills live in the deer-flow repo on branch
   `pacgate-layer`, not in this repo. Do not copy either into upstream.

6. WHEN YOU ADOPT A PATCH, ADOPT ITS GATE TOO. Every fix below ships with a
   PowerShell gate that fails when the fix is absent. A patch without its gate
   regresses silently — that is exactly how the defects in Part 2 were found.

7. PATCHES MUST STAY LF. `core.autocrlf=true` is set on the AIPC1 box; a .patch
   committed with LF is checked out with CRLF and `git apply` then fails against
   upstream's LF sources. `.gitattributes` pins `*.patch`/`*.diff` to `-text`.

8. A MOUNT MUST GO IN BOTH COMPOSE FILES. `test-workflow-compose-wiring.ps1` A5
   asserts patch-mount parity between compose.bundle.yaml and compose.prod.yaml,
   and install.ps1 uses compose.prod.yaml. A bundle-only mount leaves the fix
   absent on the deployment path.

Start with Part 1 (what is missing), then work Part 2 (verdict records) in
severity order. Part 3 is a design gap, not a bug — treat it as a proposal.
```

---

## Part 1 — What upstream `main` does not have

Measured 2026-10-30 by blob-SHA comparison of AIPC1 `HEAD` against `upstream/main`.

### 1.1 File-level delta

| Category | Upstream | AIPC1 | Delta |
|---|---|---|---|
| Files differing from upstream | — | — | **91** |
| Files present only on AIPC1 | — | **34** | 34 |
| Patch mounts in `compose.bundle.yaml` | **23** | **27** | **+4** |
| MCP servers in the connector config | **3** (template) | **30** (18 enabled) | **+27** |
| Skills (`skills/public/*/SKILL.md`) | **0** | **60** | **+60** |
| Playbooks (`playbooks/*.md`) | **0** | **1** | **+1** |
| `subagents:` block in `deer-flow-config.yaml` | **absent** | **present** (10 agents) | +1 |

### 1.2 The four patches upstream does not have

These are the load-bearing ones. Each is a frozen full copy of a deer-flow module,
bind-mounted read-only over the pinned image.

| Patch | Mount target | What it fixes |
|---|---|---|
| `deer-flow-mcp-path-args.py` | `deerflow/mcp/tools.py` | MCP tool **arguments** never had `/mnt/user-data` resolved |
| `deer-flow-sandbox-tools.py` | `deerflow/sandbox/tools.py` | `read_file` on a binary told the model to use `pandoc` |
| `deer-flow-memory-updater.py` | `deerflow/agents/memory/updater.py` | memory-update lane (self-learning) |
| `deer-flow-uploads-middleware.py` | `deerflow/agents/middlewares/uploads_middleware.py` | uploads middleware |

### 1.3 The 34 AIPC1-only files

```text
deploy/client-bundle/patches/deer-flow-mcp-path-args.py
deploy/client-bundle/patches/deer-flow-memory-updater.py
deploy/client-bundle/patches/deer-flow-sandbox-tools.py
deploy/client-bundle/patches/deer-flow-uploads-middleware.py
deploy/client-bundle/playbooks/nda-playbook.md
scripts/test-mcp-path-args.ps1
scripts/test-officecli-set-contract.ps1
scripts/test-prompt-contract.ps1
scripts/test-recursion-budget.ps1
scripts/test-skill-tool-declarations.ps1
scripts/test-t4-hold.ps1
... (plus 23 agent/instruction docs and CJK-named client assets)
```

### 1.4 The 27 MCP servers upstream cannot see

The live connector config is **gitignored** (`pacgate-ai/.gitignore:60`), so this
inventory exists only on AIPC1. Upstream's template carries 3 servers
(`openviking`, `pacgate`, `officecli`).

| Group | Servers | Enabled |
|---|---|---|
| Core (also in upstream template) | `openviking`, `pacgate`, `officecli` | 3/3 |
| 元典 yuandian | `yuandian-law`, `yuandian-case`, `yuandian-company`, `yuandian-securities` | 4/4 |
| 北大法宝 pkulaw | `pkulaw-law-search`, `pkulaw-law-keyword`, `pkulaw-case-semantic-search`, `pkulaw-case-keyword`, `pkulaw-law-item-keyword`, `pkulaw-law-recognition`, `pkulaw-case-number-recognition`, `pkulaw-citation-validator`, `pkulaw-doc-link` | 9/9 |
| 企查查 qcc | `qcc-company`, `qcc-risk`, `qcc-ipr`, `qcc-operation`, `qcc-history`, `qcc-executive`, `qcc-legal-regulation`, `qcc-legal-case`, `qcc-tender`, `qcc-document`, `qcc-document-mcp` | 0/11 (configured + authenticated, deliberately off) |
| Other | `firecrawl`, `vaquill`, `ansvar` | 2/3 |
| **Total** | **30** | **18 enabled / 12 disabled** |

**This is the single biggest upstream gap.** Upstream ships a 3-server stub; AIPC1
runs 30. Any upstream change to the connector template will silently wipe the 27
legal-database connectors on AIPC1 — see verdict **V-07**.

---

## Part 2 — Verdict records

Each record: what was claimed, what was measured, the verdict, and what upstream
should do. Severity is about **upstream impact**, not AIPC1 impact.

---

### V-01 — MCP tool arguments are never path-translated · **CRITICAL**

**Claim (AIPC1 user):** "officecli is not working."

**Measured.** The MCP server was healthy — handshake OK, `tools/list` OK, gate
`test-officecli-mcp.ps1` 13/13. The failure was in the **argument path**:

```text
officecli_officecli({"command":"create /mnt/user-data/outputs/x.docx"})
  -> ToolException: Could not find a part of the path
```

`deerflow/mcp/tools.py` passed `arguments` to `session.call_tool()` verbatim.
`replace_virtual_path` existed only in `sandbox/tools.py`, so **bash** commands were
rewritten but **MCP tool arguments were not**.

**Root cause, second layer.** The obvious fix — `get_thread_data(runtime)` — does
not work for MCP tools. They are `StructuredTool` instances with an explicit
`args_schema`, so LangChain never inspects a Python signature for a `Runtime`
annotation and `runtime` is **never injected**. `bash` and `read_file` are plain
functions and do get it. This is why a first patch attempt silently no-op'd.

**Fix.** `deer-flow-mcp-path-args.py` adds `_thread_data_from_runtime()` which falls
back to `Paths.sandbox_{work,uploads,outputs}_dir(thread_id, user_id)` — the same
derivation `ThreadDataMiddleware` uses — plus `_rewrite_virtual_paths_in_args()`
wired at the call site.

**Live proof.** Thread `360aca0d`: agent called officecli on `/mnt/user-data/...`
four times; logs show `MCP argument path rewrite applied`; file created;
`Validation passed: no errors found`; CJK intact; **zero pandoc calls**.

**Damage this caused before the fix.** The model fell back to `pandoc` via `bash`
(whose command string *is* rewritten), producing a docx that failed
`officecli validate` with 16 schema errors (`w:nsid val='A990'` is not 4-byte
hexBinary; `w:b` in the wrong `rPr` order). Thread `7b05b461` recorded it.

**Upstream action.** Adopt `deer-flow-mcp-path-args.py` + `test-mcp-path-args.ps1`
(19 assertions). This is not AIPC1-specific — **every** MCP server that takes a file
path is broken upstream today.

---

### V-02 — `read_file` on a binary misroutes the model to `pandoc` · **HIGH**

**Measured.** `read_file` on a finished `.docx` returned a hint telling the model to
use `bash`/`pandoc`. The model complied and shipped a document that fails
`officecli validate`. Measured cost on thread `4de2965b`: **~75 super-steps** spent
on the detour *after* the work was already done.

**Fix.** `deer-flow-sandbox-tools.py` replaces the hint with `officecli validate` /
`officecli get ... --json`.

**Second defect found while verifying.** The patch existed in `patches/` but was
mounted in **neither** compose file — the fix was inert. Added to both (A5 parity).

**Upstream action.** Adopt the patch **and** the mount in both compose files.

---

### V-03 — The recursion budget was a FLOOR, not a ceiling · **HIGH**

**Claim (AIPC1 user):** "递归预算 500 对多步文档 skill 不够."

**Measured.** `deer-flow-run-recursion-cap.py` had:

```python
config: dict[str, Any] = {"recursion_limit": 100}   # hardcoded
```

while the comment block above it claimed "the DEFAULT is the ceiling". The chat UI
sends `recursion_limit: 1000` per run, so the ceiling clamped the UI — but the
**API/IM path sends no config at all** and inherited the hardcoded **100**. Thread
`4de2965b` / run `27e0916c` died at "Recursion limit of 100 reached" **after both
deliverables were written and validated**.

**Why 100 is not 100 model calls.** LangGraph charges **~9.8 super-steps per LLM
call** in this graph, because nine middleware `after_model`/`before_model` hooks are
each their own node. A 100-step budget is ~10 model calls.

**Measured deepest non-looping workloads:** `d35307ec` 5767, `f7f240f6` 3154,
`dcced4b5` 1589 super-steps. A 500 ceiling is below all three.

**Fix.** Default = ceiling (`_PACGATE_MAX_RECURSION_LIMIT`), and
`DEERFLOW_MAX_RECURSION_LIMIT` raised `500 → 4000` in both compose files. Real loops
are stopped by `LoopDetectionMiddleware` layer 1/2 and the idle/stall detectors,
which are independent of this number.

**Gate.** `test-recursion-budget.ps1` — was **4 failed / 7 passed**, now **11/11**.

**Upstream action.** Adopt the default-equals-ceiling change. The `100` is a live
bug upstream for every non-web caller.

---

### V-04 — `officecli set` rejects the selector syntax `get` accepts · **HIGH (upstream defect)**

**Measured 2026-10-30.** officecli is internally inconsistent:

| Command | `body/p[1]` | `/body/p[1]` |
|---|---|---|
| `get` | ✅ resolves | ✅ resolves |
| `set` | ❌ `No elements matched selector` | ✅ works |

But deer-flow's `validate_local_bash_command_paths` rejects **any** `/`-prefixed
token on a bash command line as an unsafe absolute path:

```text
Error: Unsafe absolute paths in command: /tr[1]/tc[1]. Use paths under /mnt/user-data
```

**The only form `set` accepts is the one the sandbox forbids.** An agent following
the obvious path burns its whole budget discovering this — measured: thread
`7c68c8a8` spent **599 s and produced zero deliverables**, then reported the tool as
"unusable".

**Workaround (verified).** Put the commands in a JSON file and use
`officecli batch <file> --input <json>` — the `/` then lives in file content, never
in the command string. Measured 4/4 commands, `validate` clean, CJK intact.

**Gate.** `test-officecli-set-contract.ps1` — **8/8**. Its **S2 assertion
deliberately asserts the defect still exists**, so an officecli upgrade that fixes
the inconsistency fails the gate and tells you to delete the workaround.

**Upstream action.** Report to `iOfficeAI/OfficeCLI` as an upstream bug. Do **not**
patch officecli locally. Keep the `batch --input` guidance in the playbook.

---

### V-05 — 14 skills declared tools that resolve to nothing · **MEDIUM**

**Measured.** `filter_tools_by_skill_allowed_tools` **unions** all `allowed-tools`,
so a dead declaration is invisible (162 in / 162 kept / 0 dropped) until the surface
narrows. Three skills declared tools that do not exist:

| Skill | Dead declaration | Why it is dead |
|---|---|---|
| `diligence-issue-extraction` | `markitdown` | it is a CLI, reachable via `bash` (already declared) |
| `tabular-review` | `markitdown` | same |
| `skill-reviewer` | `review_skill_package` | no such tool anywhere |

**Deliberately left alone:** the 11 `qcc-*` declarations. Those servers are
configured **and authenticated** (200, 60 tools) and merely `enabled: false`, so the
declarations are correct — they activate when the servers are switched on.

**Gate.** `test-skill-tool-declarations.ps1` — PASS (3 passed, 3 legitimate
warnings, 0 defects).

**Upstream action.** Adopt the gate. It is the only thing that catches this class.

---

### V-06 — `audit-model-tags.ps1` failed on false positives · **LOW**

**Measured.** The tag scan matched `^\s*model:\s*(\S+)` over the **whole** YAML,
catching `subagents:` model *names* (e.g. `gemma4-12b-local`) and appending
`:latest`. Two false positives, gate exit 1.

**Fix.** Scope the scan to the `models:` block (stop at the next top-level key).
Now exits 0.

**Upstream action.** Adopt — the gate is unusable upstream as written.

---

### V-07 — The connector template is a 3-server stub that wipes 27 connectors · **CRITICAL (operational)**

**Measured.** `install.ps1`'s render step regenerates
`deer-flow-extensions-config.json` from
`deer-flow-extensions-config.template.json`, which carries **3** servers
(`openviking`, `pacgate`, `officecli`). AIPC1's live config carries **30**.

Running `install.ps1` on AIPC1 therefore **silently wipes the 27 legal-database
connectors** (firecrawl, 4× yuandian, 9× pkulaw, 11× qcc, vaquill, ansvar) and
reports only `MCP servers REMOVED: firecrawl - check the template`.

**Why upstream cannot see it.** The live config is gitignored
(`pacgate-ai/.gitignore:60`), so the 30-server inventory exists only on AIPC1.

**Upstream action.** Either (a) ship the 27 connectors in the template with
placeholder credentials, or (b) make the render step **merge** rather than
overwrite, and fail loudly when it would remove a server. Option (b) is safer —
it cannot leak credentials into the repo.

---

### V-08 — `thinking_enabled` defaults to ON · **MEDIUM (open, needs a rebuild)**

**Measured.** `frontend/src/core/threads/hooks.ts`:

```ts
thinking_enabled: context.mode !== "flash",
```

`DEFAULT_LOCAL_SETTINGS.context.mode` is `undefined`, so `undefined !== "flash"` is
**true** — thinking is ON for every first-turn run unless the user explicitly picks
Flash. A second site compounded it: `getResolvedMode()` in `input-box.tsx` returned
`"pro"` whenever the model supported thinking, and its effect runs on mount.

**Why it matters.** `deer-flow-config.yaml` carries
`when_thinking_disabled: {reasoning_effort: none}` for every thinking-capable model,
but `deer-flow-model-factory.py` applies it **only when `thinking_enabled` is
false**. With thinking on, the suppression never fires and the reply budget is
shared with the invisible reasoning channel.

**Measured impact.** 14 empty assistant messages across 2423 unique messages; 12 of
them `deepseek-v4.1-flash` with `finish_reason=length` and 8192/8192 tokens spent
entirely on reasoning.

**Honest caveat — the blank reply did NOT reproduce on re-measure.** Same model,
`max_tokens=200`, one-word prompt:

| Setting | content | reasoning | `finish_reason` |
|---|---|---|---|
| thinking ON | `OK` | 134 chars | `stop` |
| `reasoning_effort: none` | `OK` | 0 chars | `stop` |

Both answered. The 0-char result needs a prompt long enough to exhaust the whole
budget on reasoning, so the defect is **conditional on prompt size**, not
unconditional. At `max_tokens=8192` thinking works (29.5 s, 148 chars content,
2793 chars reasoning on a 3-clause review).

**Status on AIPC1: REVERTED, OPEN.** The fix lives in
`deploy/frontend-patches/files/`, which is **build-time source** — the frontend
image ships compiled output only and has no source mount, so the change cannot take
effect without rebuilding `deer-flow-frontend-pacgate`. AIPC1 is pinned to upstream
ghcr images and must not rebuild. The override file is left byte-identical to the
pinned image.

**Upstream action.** This is the one item that genuinely belongs upstream: change
the default so an unset mode does **not** enable thinking. Upstream owns the
frontend build, so upstream can ship it.

---

### V-09 — A local `0.2.8` was invented and reverted · **PROCESS (do not repeat)**

**What happened.** AIPC1 built three `0.2.8` images locally and bumped the version
across `README*`, both handbooks, `DEPLOYMENT-GUIDE.md`,
`SETUP-AND-OPERATIONS*.md`, `Cargo.toml`, `Cargo.lock` and both compose files.

**Why it was wrong.** There is no upstream `v0.2.8` — upstream's newest tag is
`v0.2.7`. The three images were **never used by any container**. Every fix was
already a bind-mounted patch over the pinned image; no rebuild was ever needed.

**Reverted** in commit `45a3203`. Images deleted. Compose pins back on `:0.2.7`.

**Also relevant:** `huggingface.co` is a **build-time-only** dependency
(`pacgate-ai/Dockerfile`, stage `ner-model`). The NER weights are already baked into
the published image (`/app/models/ner/model.safetensors`, 406,763,404 B), so a
deployment machine never needs HuggingFace. It is unreachable from AIPC1 — which is
the correct stop signal, not a problem to route around.

**Upstream action.** None. Recorded so the next agent does not repeat it.

---

## Part 3 — The design gap: skills, playbooks, and self-learning

This is not a bug. It is the difference between "the agent has tools" and "the agent
does legal work the way this firm does it."

### 3.1 Upstream has zero skills

| | Upstream | AIPC1 |
|---|---|---|
| `skills/public/*/SKILL.md` | **0** | **60** |
| `playbooks/*.md` | **0** | **1** |

The 60 skills live in the **deer-flow repo**, branch `pacgate-layer`, not in
`pacgate-ai-pr`. Remotes: `fork` = `pacgate-ai/deer-flow` (push target),
`origin` = `JZKK720/deer-flow`, `upstream` = `bytedance/deer-flow`.

**Upstream action.** Decide where skills belong. Right now they are in a third repo
that upstream `pacgate-ai-pr` does not reference, so a fresh upstream clone has no
skills at all and the agent cannot do legal work.

### 3.2 The NDA skill needs a Playbook, and the Playbook was missing

**Measured.** `nda-review/SKILL.md` Step 0 reads
`/mnt/playbooks/nda-playbook.md`. That file **did not exist anywhere**. A live NDA
run therefore stopped at `ask_clarification` and never wrote the deliverable — which
is what the user reported as "NDA-review.md cannot be generated".

**Fix.** Created `playbooks/nda-playbook.md` (R1–R8 RED, Y1–Y8 YELLOW, G1–G7 GREEN,
12-clause checklist, source grading, delivery rules) and published it read-only at
`/mnt/playbooks` via `sandbox.mounts` in `deer-flow-config.yaml`.

**Second defect.** Six skills pointed at `.deer-flow/playbooks`, which is the
**gateway's** directory and is **not visible to the sandbox**. Rewritten to
`/mnt/playbooks/...`; 0 stale refs remain.

**Live proof.** Thread `4de2965b`: `NDA-redline.docx` (5,581 B, 0 validation errors,
citing R1/R2/R3/R6) + `NDA-review.md` (1,509 B, RED triage, per-clause table,
disclaimer + 供律师复核草稿 watermark).

### 3.3 The Playbook is the missing abstraction

AIPC1 has **one** playbook and **six** skills that read it. The other five
(`contract-review`, `ma-agreement-review`, `vcpe-financing-suite`,
`dd-report-assembly`, `cold-start-interview`) reference playbooks that **do not
exist yet** — verified 2026-10-30:

```text
/mnt/playbooks/contract-playbook-<type>.md   MISSING
/mnt/playbooks/ma-playbook.md                MISSING
/mnt/playbooks/vcpe-playbook.md              MISSING
/mnt/playbooks/dd-practice-profile.md        MISSING
/mnt/playbooks/<matter-type>-profile.md      MISSING
/mnt/playbooks/nda-playbook.md               EXISTS
```

So **5 of 6** playbook references are dangling. Only `nda-review` can actually run
its Step 0 today.

**This is the highest-value upstream contribution available.** A playbook is the
firm's red-line standard in machine-readable form: which clauses are non-negotiable,
which are negotiable, which are fine, and what the fallback position is. Without it
a skill is a prompt; with it a skill is a policy.

**Upstream action (proposal).** Adopt the playbook pattern:
1. `playbooks/` as a first-class directory, published read-only at `/mnt/playbooks`.
2. One playbook per document type, with stable clause IDs (`R1`, `Y3`, `G6`) that
   skills cite and deliverables reference.
3. A gate that fails when a skill references a playbook that does not exist — the
   exact defect that made NDA-review ungeneratable.

### 3.4 Self-learning: what exists and what does not

**Exists.** `memory.enabled: true` with a dedicated `gemma4-12b-memory` model;
`deer-flow-memory-updater.py` patch; `skill-creator` and `skill-reviewer` skills;
`find-skills` for discovery.

**Does not exist.** No mechanism turns a completed matter into a new playbook or a
new skill. `skill-creator` is a manual, human-driven workflow. The memory lane
stores facts, not procedure.

**Honest assessment.** "Self-learning" in this stack currently means *memory of
facts*, not *acquisition of skill*. Claiming otherwise would be the kind of
overclaim this document exists to avoid.

**Upstream action (proposal, not a bug).** If self-learning is a goal, the smallest
useful increment is: after a RED-triage matter closes, propose a playbook diff for
lawyer approval. That keeps the red line — every AI output is a draft for lawyer
review — while letting the system accumulate firm knowledge.

---

## Part 4 — What must NOT be ported

| Item | Why |
|---|---|
| `deer-flow-extensions-config.json` | gitignored; holds 27 connector credentials |
| `pacgate-ai-assets/.../OPERATOR.md` | **tracked and public** in `pacgate-ai-pr` despite its own header claiming otherwise — active credential incident, rotation outstanding |
| `MCP授权/法律数据库MCP.md` | legal-DB unified login + password |
| `MCP授权/境外法律数据库和网站.md` | overseas legal-DB accounts |
| `百宸AI系统资源接入清单V2.docx` | resource access inventory |
| `deer-flow/` skills | separate repo, branch `pacgate-layer` |
| `.deer-flow/` | contains Sylvie SOUL.md + agent config with secrets |
| `config.yaml`, `extensions_config.json`, `.env` | gitignored machine-local config |

**Verify before any push:**

```powershell
git check-ignore -v "pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md"
```

If that prints nothing, **STOP** — the root cause is unfixed.

> Three of the four exposed files have **Chinese filenames**. Checking them by
> string comparison **silently fails** on Windows: PowerShell 5.1 decodes git's
> UTF-8 output using the GBK console codepage, so CJK paths become mojibake and
> never match — producing a *false* "not tracked" result. Use the byte-level script
> `runtime/AUTHORITATIVE-credential-check.ps1`.

---

## Part 5 — Verification upstream can run

Every gate below is in `scripts/` and runs on Windows PowerShell 5.1.

| Gate | Asserts | AIPC1 result |
|---|---|---|
| `test-mcp-path-args.ps1` | MCP arguments are path-translated (19 assertions) | **19/19** |
| `test-recursion-budget.ps1` | default = ceiling; ceiling clears real workloads | **11/11** |
| `test-officecli-set-contract.ps1` | `set`/`batch --input` contract | **8/8** |
| `test-skill-tool-declarations.ps1` | no skill declares a tool that resolves to nothing | **PASS** |
| `test-officecli-mcp.ps1` | officecli MCP handshake + real document round-trip | **13/13** |
| `test-workflow-compose-wiring.ps1` | A5 patch-mount parity across both compose files | **PASS (27 patches)** |
| `test-stack-version-coherence.ps1` | every service runs its compose pin | **14/14** |
| `audit-model-tags.ps1` | every requested local tag is pre-pulled | **PASS** |

**PS 5.1 gotchas that will bite you:**

- `@($json | ConvertFrom-Json)` collapses a 19-element array to **1**. Use
  assign-then-wrap: `$parsed = ConvertFrom-Json -InputObject $s; $actual = @($parsed)`.
- `git ls-files` octal-escapes CJK paths unless `core.quotepath=false`.
- `docker inspect -f '{{index .Config.Labels "..."}}'` breaks with escaped quotes.
  Use single-quoted format strings.
- A `.ps1` containing CJK literals needs a **UTF-8 BOM** or PS 5.1 misparses it.
- `docker cp` into a container **masks** a bind mount. Prove a mount is live with
  `mount | grep <path>` (expect `9p`/`ro`), and apply it with
  `up -d --force-recreate --no-deps <svc>` — `up -d` alone does not recreate on an
  env-only or mount-only change.

---

## Part 6 — Suggested order of work

1. **V-01** (MCP argument paths) — breaks every MCP server that takes a file path.
2. **V-07** (connector template) — one `install.ps1` run destroys 27 connectors.
3. **V-03** (recursion default) — every non-web caller dies at 100 super-steps.
4. **V-02** (read_file hint) — costs ~75 super-steps per document run.
5. **V-08** (thinking default) — upstream owns the frontend build; AIPC1 cannot fix it.
6. **V-05 / V-06** (gates) — cheap, and they prevent silent regression.
7. **V-04** (officecli) — report upstream, keep the workaround.
8. **Part 3** (playbooks) — the design gap; highest long-term value, lowest urgency.

---

## Appendix — AIPC1 state at handoff

```text
Repo        pacgate-law (git root), branch main, HEAD 3c1bedc
Subtree     pacgate-ai/ == upstream repo root (plain subtree, NOT a submodule)
Release     pinned 0.2.7 (ghcr.io/jzkk720/*:0.2.7)
Compose     pacgate-ai-bundle, deploy/client-bundle/compose.bundle.yaml
Services    deer-flow, deer-flow-frontend, pacgate-api, pacgate-mcp,
            ocr-service, pacgate-db, pacgate-nginx, openviking — all healthy
Env         DEERFLOW_MAX_RECURSION_LIMIT=4000
Mounts      27 patch mounts, /mnt/playbooks (ro)
Working     tree clean
```

Recent commits:

```text
3c1bedc fix(nda): regenerate the docx set clean and pin the officecli set contract
45a3203 fix(deer-flow): keep the stack on the pinned 0.2.7 images
901162a docs(audit): correct the playbook's own path and record the mount proof
869f727 fix(deer-flow): resolve MCP tool argument paths and publish the NDA playbook
9f1dcb7 fix(deer-flow): make the 0.2.7 recursion cap actually bite
```

Full audit with per-defect evidence:
`runtime/AUDIT-2026-10-30-mcp-skills-nda.md`.
