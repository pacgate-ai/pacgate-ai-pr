# 上游同步与修复评估 — 2026-11-08

Re-fetched upstream and evaluated the fixes already adopted. Read-only until the
gate repairs at the end, which are the only code changes.

## 1. 上游状态：无新提交

```
upstream/main : 1a1b7ba  docs(reference): publish the local-first legal AI stack reference
adopted       : 04643f5
newest tag    : v0.2.32   (v0.2.31, v0.2.30 behind it)
git log 1a1b7ba..upstream/main  ->  empty
```

**0 new commits, no new tag.** Nothing to merge. Everything below is an evaluation
of the `1a1b7ba` adoption that is already in the subtree, not a new sync.

Sync completeness re-verified: 38 of 42 changed files byte-identical, and the 4
differences are exactly the preserved local deltas (`.gitignore`, both compose
lanes, `run-all-checks.ps1`).

## 2. 递归下限（Floor）确实生效 — 行为验证，不是读代码

The `audit-recursion-regressions` gate reported **REGRESSION, 1 run(s) errored on a
caller-supplied recursion budget**. Investigated rather than accepted or dismissed.

### 2.1 The failing run predates the patch

| Evidence | Value |
|---|---|
| Failing run | `2026-11-07 07:57:17`, `recursion_limit=1000` |
| Floor patch committed to our subtree | `0456d7c`, `2026-11-08 13:20` |
| Container carrying the floor started | `2026-11-08T12:00:44Z` |
| Gate window | `2026-11-07 07:04:31 -> 2026-11-08 12:02:15` |

The window *ends* 90 seconds after the floor-bearing container started. So the
"regression" is a pre-patch run, executed by a container that predated the fix by
about a day. The gate was measuring the very defect it exists to retire.

### 2.2 The floor behaves correctly when driven directly

Ran `build_run_config()` inside the live container:

| Caller asked for | Result | Verdict |
|---|---|---|
| `recursion_limit=1000` (the historical failure) | `2000` | raised to floor ✅ |
| `50` (far below floor) | `2000` | raised to floor ✅ |
| `3000` (in range) | `3000` | honoured ✅ |
| `100000` (above ceiling) | `4000` | clamped to ceiling ✅ |
| `'abc'` (non-integer) | `2000` | ignored, default kept ✅ |
| none (server default) | `4000` | ceiling as designed ✅ |

The floor is **live in `/app/backend/app/gateway/services.py`** (L286, L389-390),
not merely in the host patch file — i.e. the bind mount is not shadowing it.

### 2.3 Both "remaining floors" the patch documents are covered

| Remaining window | Reachable? | Clamped? |
|---|---|---|
| `channels/manager.py:51` `DEFAULT_RUN_CONFIG = {"recursion_limit": 100}` | yes, via the IM channel path | ✅ it is a **top-level** key, so `build_run_config` raises it to 2000 |
| `packages/harness/deerflow/client.py:218` `recursion_limit=overrides.get(..., 100)` | **no** — nothing in `app/`, `channels/` or `adapters/` imports it | n/a (separate blast radius, correctly left alone) |

Grep of the whole backend shows `recursion_limit` only at `services.py` (the clamp),
`manager.py:51` (clamped source) and docstrings. There is no third live floor.

## 3. 两个门禁修复（代码改动）

### 3.1 `audit-recursion-regressions.ps1` — baseline 改为派生

**Defect.** The baseline was a hand-maintained constant (`2026-11-07 07:00:00`)
recording when the floor was *written*, with nothing tying it to when the floor was
*deployed*. Those were 29 hours apart, so a pre-patch run fell inside the window and
was reported as a live regression.

**Fix.** Unless `-Baseline` is passed, the baseline is now the live `deer-flow`
container's `StartedAt` — the only value that actually means "the patched code could
first execute here". A run cannot predate the container that executed it, so this
cannot manufacture a false pass; it only stops a historical run being read as new
evidence. Provenance is printed (`baseline source: ...`) so a fallback to the
constant is visible rather than silent.

**Second defect found while fixing it.** The `-Json` path exited **0** for a window
containing one trivial 3-call run, while the text path called the same data "NOT
exercised" and exited **2**. So machine consumers were told "verified" where a human
was told "not tested". Both paths now share one contract: exit 1 on a caller-budget
defect, exit 2 when nothing was delivered and no run reached `-DeepEnough`, else 0.

**Red check** (detection must not be weakened by the fix):

```
-Baseline '2026-11-07 07:00:00' -Json   ->  recursion_defects: 1   exit 1   (still caught)
auto                                     ->  recursion_defects: 0   exit 2   (not exercised)
```

### 3.2 `test-release-provenance.ps1` — diff 改到同一根层级

**Defect.** The gate diffed `git diff <published-rev>..HEAD`. Because this repo's
root is one level above upstream's, that compares **two unrelated roots**, so it
returned **2200 files** — essentially every path in the repo — and the blanket
`'pacgate-ai/'` context entry swept all of them into "image-affecting". Reported
**901 defects**, true answer **1**.

**Fix.** Diff at the same level: `git diff <published-rev> HEAD:pacgate-ai` → **124
files**. The `$contextPrefixes` list is upstream-relative and was **always correct**;
it is unchanged apart from one addition. Two earlier hypotheses in this session —
that the prefixes needed a repo-root prefix, and that the blanket entry was wrong —
were both **wrong** and are retracted; the measurements that killed them: the correct
diff is 124 files (not 2200), and `deploy/deer-flow-pacgate/`,
`pacgate-adapters/`, `deploy/deer-flow-src/frontend/` all exist **inside** the
`pacgate-ai/` subtree, so the prefixes must be subtree-relative.

**Under-report also fixed.** `deploy/laya-serve` is a build context in
`build-ghcr.yml` but had no entry, so changes to it were classified benign — the
dangerous direction. Added.

**Result: 124 changed files, 1 image-reaching.** The other 123 are `scripts/` (55),
`deploy/` docs and PDFs (44), `docs/` (15), plus dotfiles/README — none in a build
context. That is the correct classification.

## 4. 门禁的发现是真实的

The one image-reaching change is **our own** commit `2372847`:

```diff
-const EXCLUDE_FILENAMES: &[&str] = &["OPERATOR.md", "render.py"];
+const EXCLUDE_FILENAMES: &[&str] = &[
+    "OPERATOR.md",
+    "render.py",
+    "法律数据库MCP.md",
+    "境外法律数据库和网站.md",
+];
```

`seed.rs` is compiled into the `pacgate-api` image (`pacgate-ai/pacgate-ai/Dockerfile`
`COPY . .`), so **the deny-list fix is in git but NOT in the published v0.2.32
image**. The container runs the prebuilt image, so the running seeder still only
denies `OPERATOR.md`.

This is a genuine gap and the gate is right to fail on it. It is **not** fixable
from this machine: rebuilding `pacgate-api` needs either the Rust toolchain plus a
full workspace build, or a published image. Resolutions:

1. **Build and publish `pacgate-api`** (`.github/workflows/build-ghcr.yml`) so the
   image carries the deny-list, then re-tag. Preferred — it also closes the audit's
   "deny-list not deployed" item.
2. Or bump to a tag that includes it, if a later upstream release does.
3. Accept and track: the fix is inert until a rebuild, and the *effective* control
   today is `test-secret-in-mounted-data.ps1` (7/7) plus the pgvector purge, which
   do not depend on the image.

Until one is chosen, this gate fails correctly and should **not** be silenced.

## 5. 修复评估汇总

| Fix | Verdict | Evidence |
|---|---|---|
| Recursion floor live | ✅ works | 6 behavioural cases in the live container |
| Summarization-recovery mount | ✅ live | container file 42,179 B (baked 18,488), 4 markers |
| `audit-e2e-credentials` | ✅ 9/9 | was 8/9 before `PACGATE_SANITIZER_KEY` was set |
| `test-agent-mcp-e2e` | ✅ 9/9 | |
| `test-summarization-recovery` | ✅ 22/22 | |
| `test-secret-in-mounted-data` | ✅ 7/7 | red-checks correctly when a deny entry is removed |
| LF pinning | ✅ 0 of 30 patches CRLF | |
| Extraction backfill | ✅ 249 rows, 0 pending unextracted | |
| `seed.rs` deny-list | ⚠️ in git, **not in the image** | see §4 |

## 6. 仍未解决（需要决策，不是代码改动）

1. **KB coverage** — 258 of 5,605 chunks (4.6%) retrievable. 208 docs pending
   sanitization. Needs a capacity decision: raise `pacgate-api` 4 → 8 GiB, run
   off-hours in ~20-doc batches, or add a background queue.
2. **Credential rotation** — the outstanding audit blocker. No code change fixes it.
3. **`seed.rs` deploy** — §4.
4. **Ingest-path `500 embedding error`** (79 s) — not reproduced in isolation.
5. **`read_document` self-verification gap** — deliberately not loosened.

## 7. 门禁结论

`test-release-provenance` correctly fails on §4. It is a **release-provenance**
gate, and the tag genuinely does not describe an image containing our security fix.
Every other gate passes.

Stack state at time of writing: 22 containers running, 0 unhealthy, gateway on
0.2.32, `deer-flow` healthy with 0 restarts.
