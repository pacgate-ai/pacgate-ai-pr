# Verification + evaluation — upstream `86a9feb..44f7f43` (5 commits)

**Date:** 2026-10-27
**Trigger:** "can this AIPC pickup these changes, and verify and evaluate, so we can
implement these commits locally as well to patch all the issues?"
**Method:** `doubt-driven-development` — every claim checked against this machine,
not against the commit message. Read-only; nothing was committed.

---

## 0. Headline

| Question | Answer |
|---|---|
| Can this AIPC pick these up? | **Yes** — `git fetch upstream` **worked this time** (it failed on 2026-10-26). All 5 commits are in the local object store. |
| Are there 4 commits? | **No — there are 5.** `44f7f43` (installer fix) was **not** in the message you were given. |
| Is the loop-guard bug real here? | **Yes, and it already fired on this box** — `Tool frequency hard limit reached — forcing stop` at `2026-10-27 02:15:00`. |
| Does it need an image rebuild? | **No.** Bind-mounted in both compose files; the Dockerfile `COPY` is belt-and-braces for standalone runs. |
| Will it work perfectly as shipped? | **No — two defects must be fixed first** (§4, §5). One makes the new gate permanently red on this machine. |
| Gates green as claimed? | **Not reproducible here.** `version-coherence 14/14` ✅, but the loop gate is **red on PS 5.1** and `docker.io` is unreachable so the egress preflight cannot be "healthy". |

---

## 1. What upstream actually shipped

`git log 86a9feb..upstream/main` — five commits, not four:

| Commit | Subject | Files | Kind |
|---|---|---|---|
| `e30b05e` | stop force-stopping productive runs at 50 bash calls | 11 | **the real fix** (patch + compose + config + Dockerfile + gate) |
| `02ed22b` | own the release date, audit the patches, probe docker egress | 11 | tooling + docs |
| `7ca69eb` | measure the real 2.1.0 rebase cost and record its blocker | 1 | docs only |
| `af905f4` | align the remaining sizing figures | 1 | docs only |
| **`44f7f43`** | **make a skipped repo update visible, and prove the patch loaded** | **1** | **installer — NOT in your message** |

`44f7f43` matters: it fixes exactly the failure mode I hit on 2026-10-26 — a
skipped repo refresh leaves `-Update` reporting success while the bind-mounted
code is still the old code. It also adds a probe for `_tool_name_counter`, a
marker that exists **only** in the windowed patch (verified: present in the new
patch, `0` occurrences in the live file).

---

## 2. The bug is real on THIS machine — not just upstream's box

Upstream cites thread `6cc8dfae` (92 calls / 71 bash / 55 distinct). That thread
does **not** exist in our logs (`mentions=0`). But the defect fired here anyway:

```
2026-10-27 01:46:34  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 01:54:07  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:03:00  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:12:44  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:15:00  ERROR    Tool frequency hard limit reached — forcing stop   <-- the bug
2026-10-27 06:02:52  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 06:08:30  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 06:20:19  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 06:33:55  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 07:02:50  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 08:06:52  WARNING  Repetitive tool calls detected — injecting warning
```

**Root cause confirmed by reading the live file**, not by trusting the message:

```
live line 226:  self._tool_freq: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
```

A plain monotonic integer per `(thread_id, tool_name)`, cleared only by
`reset()` (lines 601–610) — which the gateway never calls. The new patch replaces
it with:

```
self._tool_name_history: defaultdict[str, deque[str]] = defaultdict(deque)
self._tool_name_counter: defaultdict[str, Counter[str]] = defaultdict(Counter)
self._tool_freq_window = max(...)
```

Live file: 612 lines, **zero** `deque`/`Counter` for the per-tool counter.
New patch: 698 lines. Diff = 124 lines. **The premise is correct.**

---

## 3. No image rebuild required — verified

The Dockerfile adds a `COPY` of the patch, which *looks* like it needs a rebuild.
It does not, because both compose files also bind-mount the same file:

```
compose.bundle.yaml:  - ./patches/deer-flow-loop-detection.py:/app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py:ro
compose.prod.yaml:    - ./patches/deer-flow-loop-detection.py:/app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py:ro
```

All five release images stay pinned at `0.2.6`. The `COPY` is for standalone
image runs and for any lane that forgets the mount — the comment says so
explicitly, and both point at the same file so they cannot diverge.

---

## 4. 🚨 DEFECT 1 — the new gate is permanently red on PowerShell 5.1

`scripts/test-loop-detection-window.ps1` line 244:

```powershell
$out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1
```

under `$ErrorActionPreference = 'Stop'` (line 1 of the gate). The container's
Python emits a `LangChainPendingDeprecationWarning` on **stderr** when it imports
`deerflow`, and PS 5.1 promotes a native command's stderr to a **terminating**
error. The gate aborts before reading the verdict it just produced.

**Proven in isolation** (`runtime/sync-1027/verify-ps51-stderr2.ps1`):

```
A. gate pattern (2>&1 merge) under Stop, WITH the langgraph import
   ABORTED: RemoteException
   first line: ...LangChainPendingDeprecationWarning: The default value of `allowed_objects` will change...

B. same, preference scoped to Continue (the fix)
   exit=0  lines=3
     ...LangChainPendingDeprecationWarning...
     from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
     IMPORT_OK
```

**This is the third occurrence of the same bug in this repo.** It was fixed in
`test-memory-lane.ps1` twice — by our `d1ed509` and again by upstream's own
`86a9feb` (which scopes `$ErrorActionPreference` to `'Continue'` around exactly
this kind of call). The new gate reintroduces it.

**Consequence:** registering it in `$gates` (which upstream does, line 111) makes
the suite **permanently red on every AIPC**, because the AIPCs ship PS 5.1. That
is the documented "a gate stops being read" failure mode.

**Fix:** scope the preference around the `docker exec` call, exactly as
`86a9feb` did in `test-memory-lane.ps1`.

---

## 5. 🚨 DEFECT 2 — the config half is missing, so the patch alone still trips

The patch windows the counter, but the **ceiling** lives in config. Upstream adds
a `loop_detection:` block to `deploy/client-bundle/deer-flow-config.yaml`:

```yaml
loop_detection:
  tool_freq_warn: 50
  tool_freq_hard_limit: 75
  tool_freq_overrides:
    bash:
      warn: 100
      hard_limit: 150
```

**Our tree does not have it** — verified three ways:

```
local_config_has_loop_detection = False
local_config_has_bash_override  = False
live_container_config_loop_detection_lines = 0
live_container_config_overrides_lines      = 0
```

And the gate says so itself when run with the patch present but config absent:

```
[FAIL] loop_detection section exists in deer-flow-config.yaml
[FAIL] bash override hard_limit (0) has real headroom over the measured peak of 74
[FAIL] bash override warn (0) fires between 50 and its hard limit (0)
```

**Why this matters beyond the gate:** the middleware auto-sizes its window to
`max(window_size, hard_limit, every override hard_limit)`. With the default
ceiling of 50 the window is 50, and upstream measured the bash-heaviest run
packing **48 bash calls into 50** — two calls of headroom. So windowing alone
converts a hard stop into a slightly-later hard stop. **Both halves are required.**

`deer-flow-config.yaml` is one of our **4 merge-required** files (we have a large
local `subagents:` block in it), so this cannot be a blind overwrite.

---

## 6. Collision map — 16 files

| Class | Count | Files |
|---|---|---|
| **CLEAN** (local == adopted base) | 9 | `README.md`, `README-ZH.md`, `DEER-FLOW-UPSTREAM-DRIFT-ASSESSMENT-2026-09-21.md`, `install.ps1`, `deer-flow-pacgate/Dockerfile`, `deer-flow-pacgate/config.yaml`, `plans/023-*.md`, `audit-deer-flow-patches.ps1`, `bump-release-version.ps1` |
| **NEW** (upstream adds) | 3 | `patches/deer-flow-loop-detection.py`, `preflight-docker-egress.ps1`, `test-loop-detection-window.ps1` |
| **MERGE REQUIRED** (local delta) | 4 | `compose.bundle.yaml`, `compose.prod.yaml`, `deer-flow-config.yaml`, `run-all-checks.ps1` |

The 4 merges are all **additive** — upstream inserts new blocks/mounts/registrations
next to anchors that already exist in our files. Same shape as the `86a9feb`
adoption, which merged cleanly.

---

## 7. Gate-bucket analysis — what can turn the suite red

| Script | Bucket | Risk here |
|---|---|---|
| `test-loop-detection-window.ps1` | **`$gates`** (line 111) | 🔴 **permanently red** on PS 5.1 (§4) |
| `preflight-docker-egress.ps1` | `$measurements` (line 672) | 🟡 reports, does not fail the suite |
| `audit-deer-flow-patches.ps1` | `$measurements` (line 694) | 🟡 exits 2 → SKIP when checkout absent (ours **is** present) |

Upstream's "egress preflight healthy" **cannot hold on this box**:

```
registry-1.docker.io  code=000  (20 s timeout)   <-- unreachable
pypi.org              code=200
ghcr.io               code=401  (reachable, auth required)
```

That is the documented VPN/split-tunnel condition, not a new defect. Because it
is a *measurement*, it will report rather than fail — but the claim in the
message is not reproducible here and should not be treated as verified.

---

## 8. Claims checked

| Upstream claim | Verified here |
|---|---|
| "Four commits, all pushed (ahead_count=0, tree clean)" | ⚠️ **Five** commits. `44f7f43` omitted from the message. |
| "loop-detection 33/33" | ❌ **Not reproducible** — gate aborts on PS 5.1 before finishing (§4) |
| "version-coherence 14/14" | ✅ Consistent with our pins (all `0.2.6`, unchanged) |
| "egress preflight healthy" | ❌ **Not reproducible** — `registry-1.docker.io` unreachable here |
| "the loop-guard fix" | ✅ Real, and it already fired on this box at 02:15:00 |
| "no image rebuild" (implied by bind-mount) | ✅ Confirmed — mounted in both compose files |
| README date `2026-10-11` → `2026-10-25` | ✅ Our tree still says `2026-10-11`; the change is correct and applies cleanly |

---

## 9. Mistakes I made during this verification

Recorded because each produced a wrong intermediate result:

1. **Deleted a tracked file.** My green-check cleanup ran
   `Remove-Item $gatePath, $patchPath, $auditPath` — but `audit-deer-flow-patches.ps1`
   is **tracked** in our tree, so I deleted it. Caught by `git status`, restored
   with `git checkout --`. The cleanup must only remove files that were absent
   before the run.
2. **First stderr probe gave a false negative.** I tested with plain `print()`,
   which writes nothing to stderr, so the pattern "survived" and I nearly
   concluded the PS 5.1 bug was absent. Re-testing with the real `deerflow`
   import reproduced the abort.
3. **`grep -c -e a -e b` counts lines matching ANY pattern**, so my first
   "windowed_markers=6" reading was ambiguous — it could have been Layer 1's own
   deque. Resolved by reading the actual data structures (line 226).
4. **Assumed the Dockerfile change meant a rebuild.** It does not; the compose
   mounts are what ship it.

---

## 10. Recommendation

**Adopt all five commits**, with two local fixes applied as part of the adoption:

1. **Fix the PS 5.1 stderr abort** in `test-loop-detection-window.ps1` before
   registering it — otherwise the suite is permanently red on every AIPC.
2. **Merge the `loop_detection:` config block** into our `deer-flow-config.yaml`
   (preserving our `subagents:` block) — without it the patch alone still trips.

Then roll out with the **bundle** recreate (not `install.ps1 -Update`), for the
same reason as last time: `install.ps1` renders `deer-flow-extensions-config.json`
and would drop **27 of 30** MCP connectors.

Plan: `docs/superpowers/plans/2026-10-27-adopt-upstream-loop-guard.md`.
