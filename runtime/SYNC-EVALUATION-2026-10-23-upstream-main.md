# Sync + evaluation — upstream `main` (b5fa7dd) into the `pacgate-ai/` subtree

**Date:** 2026-10-23
**From:** `v0.2.3` (d33553e) — the release this machine had adopted
**To:** `upstream/main` b5fa7dd — 3 commits ahead, **no new tag, no image rebuild**
**Local baseline:** `24cc129` (pre-swap HEAD)

## 1. What upstream added

| Commit | Subject | Kind |
|---|---|---|
| `4f5aeba` | gates: catch a mixed-version stack, an incapable MAIN tier, and a lost MCP tool | 4 new/changed gates |
| `4a3c87f` | docs: correct the cause of the mixed stack — partial recreate, not the installer | docs only |
| `b5fa7dd` | docs: AIPC #2's branches are reachable, and two of their gate fixes are real | docs + plan 030 |

Diffstat: 8 files, +956 lines. **Every change is a script or a document.** No
`Dockerfile`, no application source, no compose pin moved — so there is no 0.2.4
and nothing to pull.

## 2. Sync performed

Followed the documented index-swap procedure (the two histories are unrelated, so
no merge):

```powershell
git rm -r --cached pacgate-ai --quiet
git read-tree --prefix=pacgate-ai/ "upstream/main^{tree}"
git checkout -- pacgate-ai
```

**Byte-identity verified by tree SHA**, not per-file:

```
subtree after swap : b83c88b7121b91204db685d3503b30533f7f0efa
upstream/main tree : b83c88b7121b91204db685d3503b30533f7f0efa   ✅
```

### Local deltas re-applied

27 files differed from `v0.2.3` before the swap. **Zero overlap** with upstream's
changed set, so the swap was clean. All were restored:

- 13 local-only files (agent/instruction docs, `compose.ocr-override.yaml`,
  `ensure-context-capped-model.ps1`, `deer-flow-uploads-middleware.py`,
  `reclaim-checkpoints.ps1`, `test-t4-hold.ps1`, 4 CJK-named client docs)
- 11 AIPC1 delta files restored from `24cc129` — **the swap reverts these**, as
  AGENTS.md warns. `compose.bundle.yaml` was the one that silently lost its
  skills + uploads-middleware mounts and turned two gates red.

## 3. Evaluation of each upstream change on THIS machine

| Change | Verdict here | Evidence |
|---|---|---|
| `test-stack-version-coherence.ps1` | ✅ **Adopt — passes 14/14** | All 5 release services run their `0.2.3` pin. The defect it guards (partial recreate) is real but not present now. |
| `test-mcp-tool-surface.ps1` | ⚠️ **Adopt, but it was broken under PS 5.1** | Server advertises 19 tools correctly. The gate reported **1 tool** and 4 failures under Windows PowerShell 5.1 — see §4.1. |
| `check-tracked-file-size.ps1` | ⚠️ **Adopt, but it was blind to CJK paths** | Silently skipped **60 of 832** tracked files — see §4.2. |
| `test-model-roster-consistency.ps1` A6 | ⚠️ **Adopt, but it reads the wrong value** | A6 passes on the compose default while the live stack runs a local 12B — see §4.3. |
| `.gitignore` large-binary rules | ⚠️ **Adopt, but it untracked a required artifact** | The `docker-*` rule ignored this repo's own **42.8 MB** `deploy/qm-pacgate/patch/docker-cli/docker` — which `compose.qm.yaml` bind-mounts over `/usr/local/bin/docker`. Ignoring it would leave a fresh clone unable to start the qm stack. Added a directory-then-file negation exception; new `docker-*` binaries are still blocked. |
| `plans/030-*.md`, `plans/README.md` | ✅ Adopt (docs) | Accurate; §7a's cherry-pick recommendation is correct. |
| `run-all-checks.ps1` registration | ✅ Adopt | Registers the 3 new gates in the right buckets (static vs live-stack). |

## 4. Defects found in the new gates (all reproduced, then fixed)

### 4.1 `test-mcp-tool-surface.ps1` — PS 5.1 collapses a JSON array

`@($json | ConvertFrom-Json)` yields **1** element under Windows PowerShell 5.1
for a 19-element array (7 gives 19). The AIPCs ship 5.1, so the gate failed on
exactly the machines it exists to guard.

`@(ConvertFrom-Json -InputObject $json)` **also** collapses to 1 under 5.1. The
form that works on both is assign-then-wrap:

```powershell
$parsed = ConvertFrom-Json -InputObject $m.Groups['j'].Value
$actual = @($parsed)
```

Verified: 6/6 pass under 5.1 and under 7.

### 4.2 `check-tracked-file-size.ps1` — CJK paths silently skipped

`git ls-files` octal-escapes non-ASCII paths unless `core.quotepath=false`, so
`Test-Path` failed on the escape sequence and the file was skipped with no
warning. **60 of 832 tracked files were never size-checked.**

Fixed with `git -c core.quotepath=false ls-files`, plus a new assertion that
**fails** when any tracked file cannot be resolved — an uninspected file is an
unguarded file.

**This immediately surfaced a real 37.7 MB tracked file** that upstream's own
gate had been passing over:
`pacgate-ai/pacgate-ai-assets/.../20201215_货拉拉项目法律尽职调查报告_Haiwen_扫描件.pdf`

Because that file is **already committed** (in upstream's tree too), failing on it
every run would make the suite permanently red — the "a gate stops being read"
failure mode. The guard now distinguishes:

- **newly staged** oversize file → **FAIL** (still preventable)
- **already committed** oversize file → **reported as known debt** (already permanent)

Mutation-tested: a staged 12 MB probe fails the gate; removing it passes.

Two files are now reported as known debt: the 37.7 MB client PDF above, and the
40.8 MB qm `docker` CLI (see §4.4).

### 4.4 `.gitignore` `docker-*` untracked a REQUIRED deployment artifact

Upstream's new rule is right in intent but too broad for this repo:
`deploy/qm-pacgate/patch/docker-cli/docker` is bind-mounted by
`compose.qm.yaml` over `/usr/local/bin/docker`. Ignoring it silently dropped it
from the index, so a fresh clone could not start the qm stack.

Fixed with a negation that re-includes the **directory first** (git cannot
re-include a file whose parent directory is excluded), then the file. Verified:
the artifact is tracked again, and a hypothetical `docker-new` binary is still
ignored.

### 4.3 `test-model-roster-consistency.ps1` A6 — reads the default, not the override

A6 asserts the **compose default** (`deepseek-v4.1-flash:cloud`) is capable. It
never reads `deploy/client-bundle/.env`, which **wins at runtime**. On this box:

```
compose default : deepseek-v4.1-flash:cloud   → A6 PASS
.env override   : gemma4-legal:12b-chat       → what actually runs
running container: PACGATE_MODEL_MAIN=gemma4-legal:12b-chat
```

So A6 was green on a stack that cannot generate a document. Added **A6b**, which
reads the `.env` override and applies the same capability rule.

**Proven end-to-end:** with the local 12B, `test-document-generation-e2e.ps1`
failed 2/10 with `tools_used: list_documents` — the exact D3 signature (the model
calls `list_documents` and stops, never reaching `generate_docx`). After setting
`PACGATE_MODEL_MAIN=deepseek-v4.1-flash:cloud` and recreating `pacgate-api`:
**19/19 pass**, and A6b passes.

## 5. The two fork fixes plan 030 §7a recommends — both applied

Neither is in `upstream/main`; both were fetched from `fork/fix/gate-correctness`
and re-implemented here with the PS 5.1 corrections from `e30f7a5` folded in.

### `5425573` — a bind-mounted file is not a tag/artifact mismatch

`test-release-provenance.ps1` treated any change under a build context as a
provenance defect. But `compose.prod.yaml` bind-mounts `deploy/pacgate-mcp/server.py`
over `/app/server.py`, so a local edit does not change what clients pull. The
whole patch pipeline is bind-mounts, so the gate was permanently red on any
machine carrying a local patch.

Applied with **absolute-path comparison**, not `[System.IO.Path]::GetRelativePath`
(.NET Core only — throws `MethodNotFound` under 5.1, which is `e30f7a5`'s fix).

**Verified by reproducing the failure first:** a committed edit to `server.py`
now reports `1 file(s) changed but are BIND-MOUNTED over the image by compose`
and passes, instead of failing.

### `547a926` — a pull is a no-op when local is AHEAD, not only when equal

`dry-run-update.ps1` asserted `HEAD == origin/main`. A dev box with a local commit
is ahead, and `git pull --ff-only` there fast-forwards nothing and exits 0.

Applied, plus two adaptations this monorepo needs:

1. **No `origin` remote here** — this repo has `upstream` (read/pull) and `fork`
   (push). The gate now resolves the first existing `origin`/`upstream`/`fork`.
2. **Unrelated histories** — `rev-list HEAD...upstream/main` counts 695 commits
   because the roots differ. The gate now detects this and reports rather than
   asserting a meaningless behind-count, the same treatment
   `test-release-provenance.ps1` already uses.

## 6. Not adopted, deliberately

| Item | Why |
|---|---|
| `fix/runtime-mcp` | Fixes `deer-flow-mcp-client.py`, which does not exist in `upstream/main`. Fork-local. |
| `aipc1/v0.2.2-sync` | A 1853-file sync, not a patch. |
| AIPC #1's no-tools docgen patch | Measured 3/5 here; not deterministic. |
| `docs/audit-and-benchmark-records` | 1003 lines of historical benchmark reports. |
| 百宸 exposure (plan 030 D5) | Commercial/legal call, correctly left open upstream. |

## 7. Suite result

See §8 for the final run. The three gates that were red after the swap were all
**caused by the swap reverting local deltas or by the defects above**, not by
upstream's changes:

| Gate | Cause | Resolution |
|---|---|---|
| `test-workflow-compose-wiring.ps1` | swap reverted `compose.bundle.yaml` mounts | restored from `24cc129` |
| `test-workflow-compose-wiring-mutations.ps1` | same | same |
| `test-document-generation-e2e.ps1` | `.env` MAIN is a local 12B (D3) | set to `:cloud`, recreated `pacgate-api` |

## 8. Final verification

```
run-all-checks.ps1  →  ALL 48 GATES PASSED (14 live-stack gate(s) checked separately)
```

Notable individual results:

| Gate | Result |
|---|---|
| `test-stack-version-coherence.ps1` | 14 passed — every service runs its `0.2.3` pin |
| `test-mcp-tool-surface.ps1` | 6 passed — 19 tools, source and deployed surface agree |
| `check-tracked-file-size.ps1` | 5 passed — 832 files inspected, 0 skipped, 1 known-debt file reported |
| `test-model-roster-consistency.ps1` | 15 passed — A6 and A6b both green |
| `test-document-generation-e2e.ps1` | 19 passed — real `.docx` with Chinese text round-tripped |
| `test-release-provenance.ps1` | PASSED — v0.2.3 identifies the d33553e artifacts |
| `test-workflow-compose-wiring.ps1` | PASS — 20 patch mounts agree across both compose files |

One gate is `CANNOT CHECK` (exit 2, not a failure): `test-model-picker-e2e.ps1`
needs a deer-flow credential that is not configured on this box.

## 9. Restore points

- Pre-swap HEAD: `24cc129` — `git checkout 24cc129 -- pacgate-ai` restores the
  entire subtree as it was.
- `.env` backup: `deploy/client-bundle/.env.bak.sync` (pre-change, local 12B MAIN).
- Baseline record: `runtime/sync-snapshots/BASELINE-20261023.txt`
