---
artifact_contract: "ce-handoff/v1"
created_at: "2026-10-09T04:20:00Z"
title: "Push local fixes + rebuild v0.1.25 from upstream — handoff"
summary: "Verified inventory of committable fixes on this machine (summarization trigger fix, tool-policy prefix patch, skill-storage fixture exclusion), the push topology for all three repos, credential-gate status, and the v0.1.25 release plan (next version after the live 0.1.24 stack); GPU stays on nemotron (option a) with gemma4-12b as the local fallback if hangs recur."
keywords: ["handoff", "push", "fork", "upstream", "v0.1.25", "release", "summarization", "tool-policy", "deer-flow", "pacgate-ai-pr"]
cwd: "c:/Users/pacga/github-pr/pacgate-law"
resume_focus: "Commit and push the verified local fixes to the fork, then cut release v0.1.25 (the next version after the live 0.1.24 stack)"
repository: "pacgate-law (wrapper) + pacgate-ai (nested) + deer-flow (pacgate-layer)"
branch: "wrapper: main | deer-flow: pacgate-layer"
head: "wrapper 68a5f55 | deer-flow 16d1a4de"
worktree_path: "c:/Users/pacga/github-pr/pacgate-law"
---

# Handoff — push local fixes, then rebuild v0.1.25 from upstream

> **✅ EXECUTED 2026-10-09 (this session)** — the push phase is DONE:
>
> | Push | Commit | Remote state |
> |---|---|---|
> | deer-flow `pacgate-layer` → fork | `19021f7f` fix(skills): prefix-aware allowed-tools matching + eval-fixture exclusion (40 files: tool_policy.py, skill_storage.py, 9-test file, 37 SKILL.md) | `16d1a4de..19021f7f` fast-forward, verified local==fork |
> | wrapper `main` → fork **new branch** `local-main-2026-10` | 3 commits: `2fbb144` fix(config) summarization+VRAM, `e2ac7ff` fix(deploy) patch mounts, `da8db34` docs(handoff) | new branch created, verified local==fork |
>
> Pre-commit verification: 9 new prefix tests + 25 skill tests PASS in the container;
> the 39 `test_skills_bundled` frontmatter failures are PRE-EXISTING in HEAD (every
> pacgate skill carries a `required-secrets` key the validator rejects) — not our
> regression. Credential gate re-passed (blob-SHA method, positive control OK).
>
> **Remaining for v0.1.25** (see "v0.1.25 release plan" below): the fork's
> `local-main-2026-10` branch holds the wrapper's 50 commits on an unrelated root —
> the deploy-side fixes (compose mounts + 2 patch files + config) must reach
> `fork/main` for the release build. Two paths: (a) cherry-pick the 3 fix commits
> onto main, or (b) open a PR from `local-main-2026-10` and let GitHub show the
> (large, unrelated-root) diff. Path (a) is cleaner for the release; the config
> model-roster hunks should be dropped during cherry-pick (local-only per the
> 2026-09-21 directive — keep only the summarization block).

> **Version correction (2026-10-09, user)**: the rebuild target is **v0.1.25**, not
> v0.1.15 (typo). v0.1.25 = the next release after the currently-live 0.1.24 stack,
> carrying today's fixes. The v0.1.15 section below is kept only as release-history
> context.

## User's stated intent (authoritative)

1. Build a handover log (this document).
2. Push and commit **everything fixable** from this machine's local repos to the upstream/fork.
3. Then **rebuild v0.1.25 from upstream `origin/main`** (corrected 2026-10-09; was mistyped v0.1.15).
4. GPU decision: **stay on (a) nemotron-30b for general purposes**. If this machine hangs again, switch **this local machine only** to gemma4-12b — do NOT make that a pushable/committable change.
5. The summarization fix ("good fix on A") is confirmed good.

## Verified repo topology (2026-10-09, from live git state)

> ⚠️ **Topology correction vs AGENTS.md**: the `pacgate-law` wrapper **IS a git repo**
> with `fork`/`upstream` remotes (HEAD `68a5f55`), and it **directly tracks**
> `pacgate-ai/deploy/client-bundle/*` (676 files). The nested `pacgate-ai/` has its
> own `.git` (nested repo, NOT a submodule — no `.gitmodules`). The **live bind-mounted
> config** (`deer-flow-config.yaml` → container `/app/backend/config.yaml`) is tracked
> by the **wrapper** repo. `C:\pacgate-ai-pr` is a separate clone with its own history.

| Repo | Path | Remotes | HEAD | State vs fork |
|---|---|---|---|---|
| **wrapper** | `c:\Users\pacga\github-pr\pacgate-law` | fork=`pacgate-ai/pacgate-ai-pr`, upstream=`JZKK720/pacgate-ai-pr` | `68a5f55` (main) | **47 ahead / 534 behind** fork/main (unrelated histories — local main is its own line rooted at `c4ba8b0`) |
| **nested** | `pacgate-law\pacgate-ai` | fork + upstream (same URLs) | `68a5f55` (main) | same 47/533 shape |
| **deer-flow** | `pacgate-law\deer-flow` | fork=`pacgate-ai/deer-flow`, origin=`JZKK720/deer-flow`, upstream=`bytedance/deer-flow` | `16d1a4de` (pacgate-layer) | **0/0 vs fork/pacgate-layer** (in sync); `origin/main` is an ancestor (+194 commits = the whole pacgate layer) |
| **C:\pacgate-ai-pr** | `C:\pacgate-ai-pr` | fork + origin | `66fb7cf` (main) | fork/main = upstream/main + 10 commits (sanitizer fixes, handoffs); clean tree except 4 probe files + backups |

**Key insight**: `fork/main` (f7c85ca) = `upstream/main` (e62fdfd) + 10 commits, 0 behind.
The fork is the push target; upstream (JZKK720) is the canonical source the developer pulls.

## The fixes to commit (verified this session)

### 1. Summarization trigger fix (the "good fix on A") — wrapper repo, UNCOMMITTED
- File: `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml` (wrapper-tracked, bind-mounted live)
- Change: `summarization.trigger: tokens 48000 → 12000` (keep=12000 unchanged), with a
  comment block explaining the root cause (trigger counts message tokens only; real
  per-call input is 83k; 48k was structurally unreachable).
- Verified live 2026-10-09 03:38–03:46: hook fired (`should=True`), summary executed,
  state rewritten, next model call input **32,770 (bounded)** vs 83k before.
- Evidence: `runtime/debug-1009/FINDINGS.md` (machine-local, wrapper repo).

### 2. Tool-policy prefix matching — deer-flow repo, UNCOMMITTED (modified) + compose patch (wrapper, untracked)
- `deer-flow/backend/packages/harness/deerflow/skills/tool_policy.py`: adds
  `_tool_matches_declaration()` — matches exact tool names OR
  `<normalized-declaration>_` prefixes, so bare server names (`pkulaw`,
  `yuandian-law`) cover prefixed tools (`pkulaw_*`, `yuandian_law_*`).
  Fixes the Oct-8 regression where 137 MCP tools → 0 after the skills mount.
- Wrapper patch copy: `pacgate-ai/deploy/client-bundle/patches/deer-flow-tool-policy.py`
  (untracked) + compose mount already in the modified `compose.bundle.yaml`.
- New test: `deer-flow/backend/tests/test_tool_policy_prefix_matching.py` (untracked, safe).

### 3. Skill-storage eval-fixture exclusion — deer-flow repo, UNCOMMITTED + wrapper patch
- `deer-flow/backend/packages/harness/deerflow/skills/storage/skill_storage.py`:
  excludes `*/evals/fixtures/` from skill discovery (5 phantom skills polluted the
  registry and the tool-policy union).
- Wrapper patch copy: `patches/deer-flow-skill-storage.py` (untracked) + compose mount.

### 4. SKILL.md allowed-tools expansion — deer-flow repo, 37 files UNCOMMITTED
- All `skills/public/*/SKILL.md` gained framework tools (`str_replace`, `grep`,
  `glob`, `ls`, `present_files`, `ask_clarification`) in `allowed-tools`.
- Mechanical, low-risk; part of the same tool-policy fix train.

### 5. compose.bundle.yaml — wrapper repo, UNCOMMITTED
- Adds the two patch mounts (tool-policy, skill-storage) with explanatory comments.

### 6. Already-committed work that is NOT yet on the fork
- Wrapper main has 47 commits ahead of fork/main (docs/audits, nginx memory-route fix,
  volume-pin fix, 0.1.24 sync, skills bind-mount fix `f446bef`, OCR cache volume, MCP
  401-reauth). **But histories are unrelated** — see "Push strategy" below.
- `C:\pacgate-ai-pr` fork/main already carries 10 commits beyond upstream/main
  (sanitizer E2E fixes `87336a9`, handoff docs, journey tests) — those are pushed.

## Credential gate (PASSED — verified byte-level this session)

- `git ls-tree -r fork/main` on both `C:\pacgate-ai-pr` and the wrapper:
  **0 hits** for `OPERATOR|MCP` under `pacgate-ai-assets/.../assets/assets/` — the 4
  credential files are NOT in the fork tree.
- Ignore rule confirmed in `C:\pacgate-ai-pr\.gitignore` line 132:
  `pacgate-ai/**/pacgate-ai-remote-handbook/OPERATOR.md`.
- deer-flow: `config.yaml`, `extensions_config.json`, `.env` all gitignored (verified
  with `check-ignore`). The 2 untracked deer-flow files (test + pr-body) are safe.
- ⚠️ The incident doc (`docs/superpowers/specs/2026-09-16-credential-exposure-incident.md`)
  notes the credentials themselves still need rotation — pushing does not change that.

## Push strategy (the critical decision for the next agent)

**Problem**: wrapper main and fork/main have **unrelated histories** (local main was
rooted at `c4ba8b0 "baseline local monorepo"`; fork/main descends from upstream).
A plain `git push fork main` will be **rejected (non-fast-forward)**.

**Options (in recommended order)**:
1. **Push to a new branch, not main**: `git push fork main:refs/heads/local-main-2026-10`
   — preserves everything, lets the developer PR/merge on GitHub where conflicts are
   visible. Safest; recommended.
2. **Cherry-pick the 6 fix commits** (items 1–5 above) onto a fresh branch off
   `fork/main`, push that. Cleanest history; more work.
3. **Force-push main** — ❌ DO NOT. Destroys the fork's 10-commit lead
   (sanitizer fixes) and rewrites shared history.

**deer-flow is easy**: `pacgate-layer` == `fork/pacgate-layer` (0/0). Just:
```
git -C deer-flow add -A
git -C deer-flow commit -m "fix(skills): prefix-aware allowed-tools matching + eval-fixture exclusion + SKILL.md tool grants"
git -C deer-flow push fork pacgate-layer
```
(37 SKILL.md + 2 code files + 2 new files; all verified safe.)

## v0.1.25 release plan (the actual target — next version after live 0.1.24)

- **Current live stack**: 0.1.24 — `compose.bundle.yaml` pins
  `pacgate-api:0.1.24`, `deer-flow-pacgate:0.1.24`, `deer-flow-frontend-pacgate:0.1.24`,
  `pacgate-mcp:0.1.24`, `ocr-service:0.1.24` (openviking is digest-pinned).
- **v0.1.25 = 0.1.24 + today's fixes**:
  - summarization trigger 48000→12000 (config),
  - tool-policy prefix matching (code patch),
  - skill-storage eval-fixture exclusion (code patch),
  - SKILL.md allowed-tools expansion (37 files).
- **Release mechanics** (template: `C:\pacgate-ai-pr\deploy\HANDOFF-UPSTREAM-SHORT.md`
  + `HANDOFF-UPSTREAM-RELEASE-0.1.21.md`):
  1. Land the fixes on fork/main (see Push strategy above).
  2. Bump version pins: `runtime\bump-release-version.ps1` (targets
     `ghcr.io/jzkk720/*` pins in compose files; regexes were fixed for jzkk720 in
     commit `9cbadc3`).
  3. Push via fork → open PR to `JZKK720/pacgate-ai-pr` → merge.
  4. **A push to main builds NOTHING** — the GHCR build trigger is
     `workflow_dispatch` with `tag=v0.1.25` (or a `v0.1.25` tag push, per the
     0.1.21 template). Fire the dispatch and watch the workflow run.
  5. Per-machine acceptance: pull the new images on this box
     (`docker compose -f compose.bundle.yaml pull` — note docker.io may be
     unreachable; ghcr.io is fine), `up -d`, then run the smoke
     (`runtime/debug-1008/smoke-e2e.py` pattern) + verify summarization engages
     (input bounded ~32.7k) and MCP tools survive skill loading (137+ tools).

### Release-history context (why v0.1.15 was mentioned)
- `v0.1.15` was an early platform release (commit `9cbadc3`, 2026-09-19: OCR
  plumbing + MCP 15 tools). Local tags jump v0.1.14 → v0.1.18; the 0.1.15–0.1.17
  releases were cut from `C:\pacgate-ai-pr` history. Not the current target.

## GPU decision (recorded, no action)

- **Stay on nemotron-30b (option a)** for general purposes. The ~40% GPU ceiling is a
  hardware limit (25GB model / 16GB VRAM → 46%/54% CPU/GPU split, copy engine 27–39%).
- **If this machine hangs again**: switch THIS MACHINE ONLY to gemma4-12b
  (7.2GB, 100% GPU, 580 t/s prefill). That change is **local-only — do not commit/push it**.
- The summarization fix (item 1) IS committable and pushed — it is machine-independent.

## Environment gotchas (verified this session)

- **VPN is flaky right now**: wrapper fetch succeeded once, then `C:\pacgate-ai-pr` and
  deer-flow fetches failed (`Failed to connect to github.com:443 after 21062 ms`).
  Retry until fetch succeeds before pushing. No git proxy configured (VPN is app-level).
- PowerShell heredoc corruption: multi-line `docker exec sh -c 'cat > file << "EOF"...'`
  from PS 5.1 truncates/corrupts. **Write the file in the workspace, then pipe**:
  `Get-Content -Raw file.py -Encoding UTF8 | docker exec -i deer-flow sh -c "cat > /tmp/f.py && ..."`
- Parser-corruption reset: `C:\Windows\System32\cmd.exe /c "echo reset-ok"`.
- `git` needs `$env:Path += ";C:\Program Files\Git\cmd"`.
- deer-flow API test auth: create user in-process
  (`init_engine_from_config` + `get_local_provider().create_user`), login form-encoded
  with NO Origin header, POSTs need `X-CSRF-Token` = csrf cookie.

## Verification performed (evidence)

- Summarization fix: live run on real thread 2b93a758 — hook `should=True`, summary
  call executed, state rewritten, input bounded 32,770. Logs 03:38:02–03:46:09.
- GPU: `ollama ps` (46%/54% split), 10× GPU-engine sampling (compute 15–51%, copy 27–39%).
- Credential gate: byte-level `ls-tree` checks, 0 hits on both repos.
- deer-flow safety: `check-ignore` passed for all secret files; 2 untracked files safe.
- Post-fix smoke: config live in container (trigger=12000), middleware file clean
  (instrumentation removed), gateway up.

## Plausible next steps (ordered)

> ✅ Steps 1–2 EXECUTED 2026-10-09 (see the EXECUTED block at the top).

1. ~~Commit deer-flow changes~~ → DONE: `19021f7f` pushed to fork/pacgate-layer.
2. ~~Commit wrapper changes~~ → DONE: `2fbb144` + `e2ac7ff` + `da8db34` pushed to
   fork as new branch `local-main-2026-10` (option 1 — unrelated histories preserved).
3. Cut release **v0.1.25**: get the deploy-side fixes onto `fork/main`
   (cherry-pick `2fbb144`+`e2ac7ff` from `local-main-2026-10`, dropping the
   model-roster hunks from the config commit — local-only per 2026-09-21 directive)
   → bump pins (`runtime\bump-release-version.ps1`) → PR → workflow_dispatch
   tag=v0.1.25 → pull images on this box → smoke + summarization/MCP verification.
4. Optional: retire the duplicate `C:\pacgate-ai-pr` clone (84 commits behind
   fork/main, owns no container since the 2026-09-23 cutover) — or sync it.

## Relevant files (pointer-first)

- `runtime/debug-1009/FINDINGS.md` — today's root-cause evidence (machine-local, wrapper).
- `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml` — THE fix (wrapper-tracked).
- `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` — patch mounts (wrapper-tracked).
- `deer-flow/backend/packages/harness/deerflow/skills/tool_policy.py` — prefix fix.
- `deer-flow/backend/packages/harness/deerflow/skills/storage/skill_storage.py` — fixture exclusion.
- `C:\pacgate-ai-pr\deploy\HANDOFF-UPSTREAM-SHORT.md` — release mechanics template.
- `docs/superpowers/specs/2026-09-16-credential-exposure-incident.md` — credential incident context.
