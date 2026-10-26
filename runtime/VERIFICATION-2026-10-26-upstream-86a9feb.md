# Verification + evaluation — upstream `86a9feb` (memory prompt stability + input bound)

**Date:** 2026-10-26
**Verdict:** ✅ **Adopt — but NOT via `install.ps1 -Update` alone** (see §5, the blocking finding)
**Method:** adversarial verification against the live stack on THIS machine, not the commit message.

---

## 1. What upstream claims vs what I could confirm

`git fetch upstream` **cannot reach github.com** from this box (TLS reset — `curl`
succeeds, git fails, no proxy configured). `86a9feb` is **not** in the local object
store. All commit content was therefore retrieved via the **GitHub REST API**
(`api.github.com`, reachable) and `raw.githubusercontent.com`.

| Upstream claim | Verified here | Evidence |
|---|---|---|
| Committed `86a9feb`, pushed `337fb9d..86a9feb` | ✅ **y** | API: author `JZKK720`, 2026-10-26T14:00:07Z, 8 files, +1165/−2 |
| The fix is a bind-mounted patch, **no image rebuild** | ✅ **y** | 1 new `.py` patch + 2 compose mounts + docs/gates. Zero `Dockerfile`, zero Rust, zero image tag moved |
| `v0.2.6` stays accurate, no tag/rebuild | ✅ **y** | All 8 image pins still `0.2.6`; the GHCR workflow triggers on `v0.1.*`/`v0.2.*` tags, none pushed |
| `up -d` recreates when the mount set changes | ✅ **y — but see §5** | `docker compose -f compose.prod.yaml up -d --dry-run` → `deer-flow Recreate`, `deer-flow-frontend Recreate` |
| `-Update` runs `up -d` then `restart deer-flow` | ✅ **y** | `install.ps1:1672` (`up -d`), `:1731` (`restart deer-flow`) |
| Update-coverage 13 of 13, 0 needing a human | ✅ **y** | Live gate run: `[covered by -Update : 13 of 13 ; still needing a human: 0]` |
| Full suite: **52 of 52 gates pass** | ✅ **y (before the fix)** | Live run on this box: `ALL 52 GATES PASSED (14 live-stack gate(s) checked separately)` |
| Live container runs the patched code (`cap: 16000 \| conversation first: True`) | ❌ **NOT on this machine** | Live `deer-flow` has **no** `16000`, and `{current_memory}` (line 26) **precedes** `{conversation}`. The claim describes the HX370 box, not AIPC1 |

**So: upstream's report is accurate about their box. It is not a description of
this one — here the defect is still live, which is exactly why the fix matters.**

---

## 2. The defect is real and reproducible here

Live container `deer-flow` (image `ghcr.io/jzkk720/deer-flow-pacgate:0.2.6`):

```
MEMORY_UPDATE_PROMPT:  Current Memory State:{current_memory}   ← line 26
                       New Conversation to Process:{conversation} ← line 31
MEMORY_CONVERSATION_MAX_CHARS    : ABSENT
MEMORY_CONVERSATION_MAX_MESSAGES : ABSENT
```

`current_memory` changes on every successful update, so the prompt **prefix
changes on every update** and llama.cpp can never reuse the KV prefix — the
memory lane pays a full cold prefill each turn. `format_conversation_for_update`
truncated each message to 1000 chars but capped neither total nor message count,
so the memory prompt grows to chat size, evicting the chat lane's cache entry.

Upstream measured 68.7 s cold × 3 consecutive updates vs 0.5 s warm. I did not
re-measure wall-clock (that needs a live update cycle), but the **mechanism** is
confirmed present: both the ordering and the absence of caps are observable in
the running file.

---

## 3. The risk I expected — and it is genuinely safe

Our local `d1ed509` (2026-10-26) shipped an **820-line** `deer-flow-memory-updater.py`
patch and an `deer-flow-memory-storage.py` mount. Upstream's new patch replaces
`memory/prompt.py` — the *module our updater imports from*. A full-file
replacement of a dependency is the classic way to break a patched consumer.

**Checked, and it holds:**

| Check | Result |
|---|---|
| Symbol parity (live `prompt.py` vs upstream patch) | ✅ identical set + 2 new constants. **No API removed.** |
| Our updater's imports (`MEMORY_UPDATE_PROMPT`, `format_conversation_for_update`) | ✅ both present |
| All 3 format placeholders (`{current_memory}`, `{conversation}`, `{correction_hint}`) | ✅ all retained, reordered conv→mem→hint |
| Runtime probe (new `prompt.py` loaded in the live container) | ✅ `CAP_CHARS 16000`, `CAP_MSGS 40`, `ORDER conv<mem: True`, `FORMAT_OK True`, bounded output 16005 chars |
| Redaction ordering | ✅ our `_redact_direct_identifiers()` runs **after** `format_conversation_for_update`, so upstream's cap trims *then* we redact — identifiers cannot survive via truncation |

Note the interaction is subtle and worth stating: upstream's cap trims the
**tail-preserving** window *inside* the formatter; our redaction then runs over
the already-bounded text. Because the redactor is a whole-string regex sweep,
truncation cannot reintroduce a USCC/phone/email — but truncation *can* now cut
the text the redactor sees, which is strictly less exposure, not more.

---

## 4. Subtree-swap collision map (the real cost of adopting)

The two histories are unrelated, so adoption = index swap, which **reverts every
local delta**. For the 8 files `86a9feb` touches:

```
deploy/client-bundle/compose.bundle.yaml                  DIFFERS  -> re-apply (3 mounts)
deploy/client-bundle/compose.prod.yaml                    DIFFERS  -> re-apply (3 mounts)
deploy/client-bundle/patches/deer-flow-memory-prompt.py   LOCAL: ABSENT  (upstream creates)
plans/031-aipc-latency-root-cause-and-fix.md              LOCAL: ABSENT  (upstream creates)
plans/README.md                                           SAME  (clean)
scripts/run-all-checks.ps1                                DIFFERS  -> re-apply (1 gate)
scripts/test-memory-lane.ps1                              DIFFERS  -> re-apply / supersede
scripts/test-memory-prompt-stability.ps1                  LOCAL: ABSENT  (upstream creates)
```

**`test-memory-lane.ps1` is the collision of substance.** Our `d1ed509` fixed
**the same two bugs** upstream fixes in `86a9feb`, independently:

| Bug | Our fix | Upstream fix |
|---|---|---|
| PS 5.1 eats inner quotes → `grep` returns 0 → false UNPATCHED | double-outer/single-inner `sh -c` + `-F` | drop the second shell; pass pattern as argv |
| stderr merge under `$ErrorActionPreference='Stop'` aborts the gate | `2>/dev/null` + `try/catch` | scope EAP to `Continue` around the call |

Both are correct. **Upstream's argv form is strictly better** (no second shell at
all, so no quoting class of bug), and its EAP scoping keeps stderr *visible* in
the output rather than discarding it. **Adopt upstream's version wholesale** and
retire ours — do not try to keep both.

Local `run-all-checks.ps1` has exactly **one** extra registration to preserve:
`'scripts/test-prompt-contract.ps1'` (the 红线圈 prompt-contract ratchet).

Compose delta to re-apply is exactly **3 mount lines** per file:
`deer-flow/skills/public`, `deer-flow-uploads-middleware.py`, `deer-flow-memory-updater.py`.

---

## 5. ⚠️ CORRECTED — `install.ps1 -Update` vs bundle: real drift, but **not** the breakage I first claimed

> **Correction notice.** My first pass called this a *blocking* finding and
> asserted that `-Update` would "drop both `NEXT_PUBLIC_*` vars and change the
> chat frontend's backend URL wiring". **That conclusion was wrong.** The premise
> (bundle has the vars, prod does not) is true; the *consequence* I inferred from
> it was not. Two independent errors, both caught by testing instead of reasoning:
>
> 1. **Inlining claim inverted.** `NEXT_PUBLIC_*` are conventionally inlined at
>    Next.js build time. Here they are **not**: `grep` over the built image finds
>    `localhost:8089` in **0** client chunks and **0** server chunks — only in a
>    `.js.map`. The values are therefore **inert**, not baked wiring.
> 2. **Recreates ≠ breaks.** I inferred a runtime effect from an config
>    difference without executing it. A throwaway container run from the same
>    image with **prod's exact env** behaves identically (see the table below).

### What is actually true

Live containers are labelled `pacgate-ai-bundle` / `compose.bundle.yaml`.
`install.ps1` operates only on `compose.prod.yaml` (`:1265`, `:1637`, `:1672`,
`:1731`). The two files are parity-pinned on `name:` and on all **22** patch
mounts (identical sets — A5 passes). Their non-comment divergence is **7 lines**:

| | `compose.bundle.yaml` (live) | `compose.prod.yaml` (`-Update`) |
|---|---|---|
| `NEXT_PUBLIC_BACKEND_BASE_URL` | `http://localhost:8089` | **absent** |
| `NEXT_PUBLIC_LANGGRAPH_BASE_URL` | `http://localhost:8089/api` | **absent** |
| `../frontend-patches/files/next.config.js` mount | absent | **present** |
| `./data/office:/mnt/user-data/workspace` | absent | **present** |
| `depends_on` on frontend | `[deer-flow]` | `[pacgate-api, deer-flow]` |

**This divergence is upstream's own, not local drift** — verified by reading
`337fb9d`: upstream `compose.bundle.yaml` also carries both `NEXT_PUBLIC_*` vars
and upstream `compose.prod.yaml` also omits them. Nothing here was introduced by
our commits or by `86a9feb`.

### The empirical test that overturned my claim

A throwaway container from the same `0.2.6` image, on the same network, with
**prod's env exactly** (no `NEXT_PUBLIC_*`):

| Path | live (bundle, vars present) | prod-env (vars absent) |
|---|---|---|
| `/` | `200` | `200` |
| `/workspace` | `200` | `200` |
| `/api/memory` | `401 uvicorn` | `401 uvicorn` |
| `/api/agents` | `401 uvicorn` | `401 uvicorn` |
| `/api/skills` | `401 uvicorn` | `401 uvicorn` |
| `/api/langgraph` | `401 uvicorn` | `401 uvicorn` |
| `/api/threads` | `401 uvicorn` | `401 uvicorn` |

**Identical.** And `server: uvicorn` on every `/api/*` reveals *why*: the
`rewrites()` in `next.config.js` are compiled into
`.next/routes-manifest.json` at **build** time, and the manifest contains the
catch-all

```
/api/:path*  ->  http://deer-flow:8001/api/:path*
```

unconditionally. At `next start` the manifest is used as-is, so the
`if (!process.env.NEXT_PUBLIC_* )` guards never re-evaluate. `/api/*` is proxied
to the gateway regardless of which compose file created the container. The
`NEXT_PUBLIC_*` values are dead config on this image.

(The route handlers at `src/app/api/memory/route.ts` — whose fallback
`127.0.0.1:8001` is genuinely `ECONNREFUSED` inside the container — are **shadowed
by the catch-all rewrite** and never serve. That is a latent upstream bug, but it
is not reachable while the baked rewrite exists, and it is identical under both
compose files.)

### Real, verified residual differences

| Difference | Impact here |
|---|---|
| `next.config.js` mount (prod only) | The patch file (4616 B) differs from the image's copy (4495 B) by a **BOM/encoding on one comment line** only — no behavioural delta. Irrelevant either way. |
| `./data/office` mount (prod only) | The host dir is **empty**, and `/mnt/user-data` does **not exist** in the live bundle container. Prod would create a mount point bundle lacks. Harmless today; would matter if officecli output were expected to persist. |
| `depends_on` frontend | Prod adds `pacgate-api`, so `-Update` cannot start the frontend before the API. A strict ordering *improvement*. |
| `docker.io` unreachable (`code=000`) | `compose pull` WARNs (non-fatal since the `$pullExit` guard) and the recreate proceeds on local `0.2.6` images — which are the correct ones, since `86a9feb` rebuilds nothing. |

### Revised recommendation

**Either command is safe for this change.** `install.ps1 -Update` will recreate
`deer-flow` **and** `deer-flow-frontend` from `compose.prod.yaml`; both come up
`200`/`401`-identical to today, on the same `0.2.6` images.

I still recommend the **bundle** recreate, for a narrower reason than before —
**minimal blast radius on a production law-firm box**, not because prod is
broken:

- It touches only the two services the change needs, and cannot rename the
  project or create a second volume.
- It leaves the frontend definition byte-for-byte as it is today, so the rollout
  has *zero* unrelated deltas to reason about.
- It sidesteps `install.ps1`'s `extensions_config.json` render (§6) — which is
  the hazard that **is** real and armed.

Adopting `install.ps1 -Update` instead is defensible; it should then be a
deliberate choice with §6's backup taken first, not an incidental side effect.

---

## 8. Outcome (executed 2026-10-26)

`86a9feb` is **adopted and live on this stack**.

| Step | Result |
|---|---|
| Fetch (git blocked) | 8/8 files via HTTPS; one transfer arrived **truncated** (6 890 of 25 262 bytes) and was caught by an API-size check |
| Tree identity | All 8 blob SHAs matched GitHub; built tree `526da22b…` == commit tree; parent verified `337fb9d` |
| Local deltas | **63** (not the 4 first assumed) — 59 restored verbatim, 3 merged, 1 superseded |
| Merge collisions | 4 files: `compose.bundle.yaml`, `compose.prod.yaml`, `run-all-checks.ps1` (additive — merged), `test-memory-lane.ps1` (upstream supersedes ours) |
| Swap identity | subtree SHA `526da22b…` — byte-identical to upstream |
| Gates | **ALL 53 PASSED** (52 + `test-memory-prompt-stability.ps1`), zero regressions |
| Gate red-check | reversed block order → exit 1; restore byte-identical (SHA-256 match) → exit 0. Not blind. |
| Rollout | `compose.bundle.yaml up -d --force-recreate --no-deps deer-flow` — the frontend was **never touched** |
| Live state | `cap: 16000 \| conversation first: True` — upstream's claim independently reproduced here |
| Red line | `PACGATE_MATTER_ID` set, storage refusal present, identifier redaction live |
| Push to fork | ❌ **blocked** — `github.com:443` TLS reset from this host; commits are local only |

**Measured effect (the point of the commit):** with a 16 000-char conversation
held constant, the shared prompt prefix across a memory change went from
**218 chars (1.0 %)** under the old ordering to **16 278 chars (71.9 %)** —
+16 060 reusable chars. Wall-clock prefill (upstream's 68.7 s → 1.3 s) was **not**
re-measured here; see `runtime/BENCHMARK-2026-10-26-memory-prompt-86a9feb.md` §1
for why.

### Mistakes made and caught during execution

Recorded because each one was productively caught by a check, not by luck:

1. **Truncated download** — `compose.bundle.yaml` arrived as 6 890 bytes. Only
   the API size comparison found it; the build step would have failed opaquely.
2. **CJK paths reported MISSING** — PS 5.1 decoded git's UTF-8 output as GBK,
   so `Test-Path` failed on **56** files. Fixed with `ls-tree -z` + reading the
   stream as UTF-8 bytes.
3. **Then `delta_count=0`** — because `>` redirection writes UTF-16, destroying
   the NUL-separated stream. Fixed with `Start-Process -RedirectStandardOutput`.
4. **Dropped a prod mount** — I assumed the two compose files had the same local
   delta shape; `compose.prod.yaml` actually carried a `skills/public` mount that
   `compose.bundle.yaml`-only rules did not restore. Caught by diffing the merged
   file against the preserved original (22 → 23 mounts, `only_orig=0`).
5. **Flaky gate on the first post-rollout suite run** — `test-workflow-mutations.ps1`
   mutates and restores tracked files, so a concurrent reader can observe it
   mid-mutation. Passes standalone (exit 0) and on the immediate re-run.

---

## 6. Secondary hazards confirmed on this machine

| Hazard | Status | Evidence |
|---|---|---|
| `extensions_config.json` render wipes 27 connectors | ⚠️ **ARMED** | `OPENVIKING_ROOT_API_KEY` is **set (32 chars)** → render **will run**; live `deer-flow-extensions-config.json` has **30** servers, template has **3**. Backup is written first, but only 3 servers are diffed for warnings |
| `install.ps1` fails at `compose pull` | ✅ **no longer fatal** | `:1272` guards `$pullExit` and WARNs. AGENTS.md's "terminates there" is stale |
| `install.ps1` cannot refresh the repo | ✅ **still true** | Looks for `.git` at `pacgate-ai/`; git root is `pacgate-law/` |
| Volume/project-name hazard | ✅ **safe** | Both files pin `name: pacgate-ai-bundle` |

---

## 7. Gate impact

- New gate `test-memory-prompt-stability.ps1` (204 lines) is **self-contained**
  (reads files; no docker, no credentials, no model) → correctly a static gate.
- **Red-checked on this tree**: without the patch it exits **2** with
  `deploy\client-bundle\patches\deer-flow-memory-prompt.py not found`. It is not
  a blind gate.
- It also asserts **mount parity**: any compose file mounting
  `deer-flow-memory-storage.py` must also mount `deer-flow-memory-prompt.py`.
  That covers the A5-class defect without touching A5.
- Suite goes 52 → **53** gates (one added, none removed; our
  `test-prompt-contract.ps1` stays).
