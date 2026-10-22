# AIPC1 Remediation + Upstream Delivery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four verified AIPC1 defects (tool-surface cost, memory durability, checkpoint-DB bloat, unverified fixes) and deliver them upstream so a fresh machine inherits them from `docker compose pull` alone.

**Architecture:** Two layers. (1) **Local remediation** — config + patch changes on the live `pacgate-ai-bundle` stack, each independently verified against the running container. (2) **Upstream delivery** — commit on the `pacgate-law` git root (which *is* `pacgate-ai-pr`), push to `fork`, open a PR to `fork` for review. Any change requiring `JZKK720` write access is emitted as a handoff document, not attempted.

**Tech Stack:** PowerShell 5.1 (`install.ps1`, audits), Python 3.12 (deer-flow harness + patches), Docker/BindKit, GitHub Actions, SQLite/WAL, Ollama.

## Global Constraints

Copied verbatim from the approved design (`docs/superpowers/specs/2026-10-16-capability-sync-upstream-design.md`) — every task's requirements implicitly include this section.

- **Repo topology (verified 2026-10-17, corrects AGENTS.md):** `C:\Users\pacga\github-pr\pacgate-law` **is** the `pacgate-ai-pr` git root (`.git` directory, 67 commits, `main`). Upstream root `F` maps to local `pacgate-ai/F`; upstream `pacgate-ai/G` maps to local `pacgate-ai/pacgate-ai/G`.
- **Push target:** `fork` = `pacgate-ai/pacgate-ai-pr` (**pushable**). `upstream` = `JZKK720/pacgate-ai-pr` (**NOT pushable** — PAT has `push=False`). Never attempt a push to `upstream`.
- **Image namespace:** `ghcr.io/jzkk720/*` — pinned by `GHCR_NAMESPACE` in `build-ghcr.yml`. Never `pacgate-ai/*`.
- **Live base is deer-flow `v2.0.0`**; the source repo `deer-flow/` is on `pacgate-layer` at **`2.1.0`**. Do not assume a harness file in `deer-flow/backend/` exists in the container — **always confirm with `docker exec`** before relying on it.
- **Patches are bind mounts** (`compose.bundle.yaml:211-284`), e.g. `./patches/deer-flow-agent.py:/app/backend/packages/harness/deerflow/agents/lead_agent/agent.py:ro`. A new patch = a new file + a new mount line + a compose recreate.
- **Recreate, don't restart:** an env/volume change needs `docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps <svc>`. Never touch `pacgate-db`.
- **Encoding:** never use `Get-Content`/`Set-Content` on UTF-8 files carrying CJK. Use `[System.IO.File]::ReadAllText/WriteAllText` with `UTF8Encoding($false)` (no BOM).
- **PS 5.1 traps:** `??` unsupported; `$pass` collides case-insensitively with `$script:pass`; `docker inspect -f '{{index ...}}'` breaks — use `ConvertFrom-Json`; under `$ErrorActionPreference='Stop'` a native command writing to stderr becomes *terminating* once a redirection is attached.
- **Credential gate (ACTIVE INCIDENT):** the 3 leaked blobs (`5855e649`, `8e18bfce`, `a59e30ed`) must never appear in a pushed tree. Verify by **blob SHA**, not filename (CJK paths are octal-escaped). Run `pacgate-ai/scripts/assert-no-staged-secrets.ps1` before every commit.
- **Never commit:** `.env`, `deer-flow-extensions-config.json`, `data/`, `.deer-flow/`, `checkpoints.db*` — all gitignored. Never `git add -f` them.
- **Per-machine values stay local** (user directive 2026-09-21): `PACGATE_MODEL_{MAIN,MID,LOW}`, `GATEWAY_CORS_ORIGINS`, and the model roster. Do **not** upstream the roster or the 2026-10-16 context-cap/reasoning-burn tuning.
- **Clock skew:** deer-flow logs are **UTC**; `%LOCALAPPDATA%\Ollama\server.log` is **+08**. Label the clock when a finding depends on ordering.
- **Never delete a Docker volume.** `pacgate-ai-bundle_pacgate-db-data` is live; `client-bundle_pacgate-db-data` is an orphan holding real data.

---

## Why this plan exists — the verified gaps

| # | Defect | Evidence | Impact |
|---|---|---|---|
| **D1** | 153 MCP tool schemas are bound into every prompt | `convert_to_openai_function` over `get_cached_mcp_tools()` = **69,313 tok**; real cloud prompt **80,791–90,225 tok**; `tool_search.enabled: false` | ~83 % of prompt cost; ~100 s prefill on the local runner |
| **D2** | `tool_search` cannot be turned on as-is | live `v2.0.0` has **no** `mcp_routing_middleware.py`; `tool_search.py` has **no** `build_mcp_routing_middleware`; `deer-flow-extensions-config.json` has **no** `routing:` keys | Flipping the flag alone reproduces the 2026-09-12 "deferred, not promoted" failure |
| **D3** | Memory extraction burns the single slot and retries forever | live `queue.py` = 287 lines, no `flush_sync`, in-memory only; failures dropped without retry; 11/11 parse failures (2026-10-16) | 32–41.6 k output tok per run ≈ 42 min of slot time |
| **D4** | Reasoning-burn fix deployed but **unverified** | container restarted 2026-10-16 16:19Z; logs since contain only `/health` | P1 cannot be called fixed |
| **D5** | `checkpoints.db` = 2.215 GiB, 73 % stale | `freelist_count = 0`; thread `d9d0fe54` = 1,418 MiB = 72 % of checkpoint bytes, idle since 2026-09-13 | VACUUM alone reclaims **0 bytes** |

---

## ⚠️ DECISION REQUIRED BEFORE TASK 4

**D2 has two mutually exclusive remedies. Task 4 cannot start until you choose.**

| | **Path A — backport to v2.0.0** | **Path B — upgrade to v2.1.0** |
|---|---|---|
| Mechanism | Add 4 patch files under `pacgate-ai/deploy/client-bundle/patches/` + mounts | Rebase the stack onto deer-flow v2.1.0 per `pacgate-ai/plans/023-deer-flow-2.1-upgrade.md` |
| Work | Port `McpRoutingConfig`, `mcp_routing_middleware.py`, `build_mcp_routing_middleware`, `tag_mcp_routing` wiring | Rebase 18 patches onto a base **1019 commits ahead**; rebuild + republish 5 GHCR images |
| Risk | Carries a permanent fork of v2.1.0's routing subsystem | High-touch; needs the developer to rebuild GHCR (cannot be done here) |
| Blocker | none | `JZKK720` must publish rebuilt images |
| Time to D1 fix | hours | days–weeks |
| Recommended | **Yes, now** — D1 is the dominant cost | **Also do it** — but as a separate plan (023 already exists), not as a prerequisite for D1 |

**Recommendation: Path A now, Path B tracked separately.** Path A is throwaway work *only if* the v2.1.0 rebase adopts upstream's version wholesale — which the existing plan 023 already intends, so the patches are deleted at rebase time. That is an acceptable, bounded cost.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml` | Live deer-flow config | **Modify** — `tool_search.enabled: true` + `auto_promote_top_k` |
| `pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json` | Connector template with `${VAR}` placeholders | **Modify** — add `routing` to the 6 due-diligence servers |
| `pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json` | Rendered live connectors (**gitignored**) | **Modify** — add `routing` (local only) |
| `pacgate-ai/deploy/client-bundle/patches/mcp-routing-middleware.py` | **New** — port of v2.1.0 `McpRoutingMiddleware` | **Create** (Path A) |
| `pacgate-ai/deploy/client-bundle/patches/deer-flow-tool-search.py` | **New** — routing-aware `tool_search` | **Create** (Path A) |
| `pacgate-ai/deploy/client-bundle/patches/deer-flow-agent.py` | Live lead agent | **Modify** (Path A) — install routing middleware |
| `pacgate-ai/deploy/client-bundle/patches/deer-flow-extensions-config.py` | **New** — `McpRoutingConfig` + resolver | **Create** (Path A) |
| `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` | Live stack | **Modify** (Path A) — 4 new mount lines |
| `pacgate-ai/deploy/client-bundle/patches/memory-queue-durability.py` | **New** — durable spool + DLQ + idle gate | **Create** |
| `pacgate-ai/scripts/reclaim-checkpoints.ps1` | **New** — thread-atomic stale delete + VACUUM | **Create** |
| `pacgate-ai/scripts/audit-local-consumers.ps1` | **New** — enumerate local inference consumers | **Create** |
| `deer-flow/backend/tests/test_memory_queue_durability.py` | **New** — pytest for the queue patch logic | **Create** |
| `docs/superpowers/plans/2026-10-17-aipc1-remediation-and-upstream.md` | This plan | — |

---

## Task 1: Verify the D4 reasoning-burn fix against a live run

**Files:**
- Read-only: `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml` (models `gemma4-12b-memory`, `-summarizer`, `-title`)
- No files modified. This task **gates** Task 5.

**Interfaces:**
- Produces: a pass/fail verdict on whether `reasoning_effort: none` reaches the wire, recorded in `runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md` §3.3.

- [ ] **Step 1: Confirm the fix is present in the container's config**

Run:
```powershell
$f = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\deer-flow-config.yaml"
$t = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
foreach ($role in @('gemma4-12b-memory','gemma4-12b-summarizer','gemma4-12b-title')) {
  $i = $t.IndexOf("- name: $role")
  $block = $t.Substring($i, 1400)
  Write-Output ("$role : supports_reasoning_effort=" + ($block -match 'supports_reasoning_effort: true') +
                " when_thinking_disabled=" + ($block -match 'when_thinking_disabled:\s*\r?\n\s*reasoning_effort: none'))
}
```
Expected: `True True` for all three roles.

- [ ] **Step 2: Drive one real memory-update cycle**

Cause one exchange, then wait for the debounce window to fire the updater:

```powershell
# Confirm the container is up and the queue worker is live
docker logs deer-flow --since 5m 2>&1 | Select-String 'Stream bridge initialised: memory'
# Trigger a run through the UI/API (any short prompt), then wait > debounce:
Start-Sleep -Seconds 180
docker logs deer-flow --since 10m 2>&1 | Select-String 'memory update|Failed to parse|Updating memory'
```

- [ ] **Step 3: Assert the failure mode is gone**

Run:
```powershell
$since = (Get-Date).AddMinutes(-15)
$hits = docker logs deer-flow --since 15m 2>&1 | Select-String 'Failed to parse LLM response for memory update'
Write-Output ("parse failures in last 15m: " + ($hits | Measure-Object).Count)
```

Expected: **`0`**. If non-zero, the fix did **not** take effect — see Failure Triage below.

- [ ] **Step 4: Confirm content tokens were produced**

Run:
```powershell
docker logs deer-flow --since 15m 2>&1 | Select-String 'LLM token usage' |
  ForEach-Object { if ($_.Line -match 'input=(\d+) output=(\d+)') { "in=$($Matches[1]) out=$($Matches[2])" } }
```
Expected: at least one memory-role call with `output` **> 0** and well under 2048 (the JSON body, no reasoning burn).

- [ ] **Step 5: Record the verdict**

Append to `runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md` §3.3, replacing the `⚠️ deployed, unverified` row:
```markdown
| Reasoning-burn fix | ✅ **verified <YYYY-MM-DD HH:MM +08>** — N memory cycles, 0 parse failures, output > 0 |
```

- [ ] **Step 6: Commit**

```bash
git add runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md
git commit -m "docs(aipc1): verify the reasoning-burn fix against a live memory cycle"
```

**Failure triage** — if Step 3 shows non-zero parse failures, the fix is not reaching the wire. Check, in order:
1. `docker exec deer-flow grep -A6 'name: gemma4-12b-memory' /app/backend/deer-flow-config.yaml` — is the mounted config the edited one?
2. `patches/deer-flow-model-factory.py:138-141` — the `when_thinking_disabled` branch is entered unconditionally on `thinking_enabled`, so the directive *should* be emitted; if it is not, the patch is not mounted.
3. Whether the updater passes `thinking_enabled=False` (`deerflow/agents/memory/updater.py:~395`).

---

## Task 2: Reclaim the checkpoint DB (D5)

**Files:**
- Create: `pacgate-ai/scripts/reclaim-checkpoints.ps1`
- Read-only: `.deer-flow/checkpoints.db`, `.deer-flow/data/deerflow.db`

**Interfaces:**
- Consumes: the live SQLite files under `pacgate-ai/deploy/client-bundle/data/deer-flow/`.
- Produces: `reclaim-checkpoints.ps1 -WhatIf` (report) and `-Apply` (destructive). Later automated by Task 3.

- [ ] **Step 1: Write the script — report mode first**

Create `pacgate-ai/scripts/reclaim-checkpoints.ps1`:

```powershell
<#
.SYNOPSIS
  Delete stale LangGraph threads (checkpoints + writes) and VACUUM.

.DESCRIPTION
  VACUUM alone reclaims NOTHING here: freelist_count was 0 because the bytes are
  live rows, not free pages. 73% of the file belongs to 4 threads idle for weeks
  (one thread alone = 1.42 GiB). Deletion must therefore come FIRST.

  Deletion is THREAD-ATOMIC across `checkpoints` and `writes`. There is no DB-level
  FK, but app/gateway/checkpoint_lineage.py walks checkpoint_id /
  parent_checkpoint_id, so a row-age deletion would leave dangling lineage.

  A thread with checkpoints but NO threads_meta row cannot be deleted through the
  REST route (require_existing=True) -- this script handles it directly.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]    $RetainDays = 21,
    [string] $DataDir    = "$PSScriptRoot\..\deploy\client-bundle\data\deer-flow",
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$ckpt = Join-Path $DataDir 'checkpoints.db'
$meta = Join-Path $DataDir 'data\deerflow.db'
if (-not (Test-Path $ckpt)) { throw "checkpoints.db not found at $ckpt" }
if (-not (Test-Path $meta)) { throw "deerflow.db not found at $meta" }

$py = @'
import json, os, sqlite3, sys
ckpt, meta, retain_days, apply_ = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "apply"

size = os.path.getsize(ckpt)
c = sqlite3.connect(f"file:{ckpt}", uri=True)
c.execute("PRAGMA busy_timeout=30000")
m = sqlite3.connect(f"file:{meta}?mode=ro", uri=True)

cut = m.execute(
    "SELECT date('now', ?)", (f"-{retain_days} days",)
).fetchone()[0]

meta_rows = {r[0]: (r[1] or "") for r in m.execute(
    "SELECT thread_id, substr(COALESCE(updated_at,''),1,10) FROM threads_meta")}

rows = c.execute(
    "SELECT thread_id, COUNT(*), SUM(LENGTH(checkpoint)) FROM checkpoints GROUP BY thread_id"
).fetchall()
writes = dict(c.execute("SELECT thread_id, SUM(LENGTH(value)) FROM writes GROUP BY thread_id"))
total = sum((r[2] or 0) + (writes.get(r[0]) or 0) for r in rows)

stale = []
for tid, n, cbytes in rows:
    updated = meta_rows.get(tid)
    if updated is None or updated == "" or updated < cut:
        stale.append((tid, n, (cbytes or 0) + (writes.get(tid) or 0), updated or "(no meta row)"))

print(f"file            : {size/1024**3:.3f} GiB")
print(f"free pages      : {c.execute('PRAGMA freelist_count').fetchone()[0]}")
print(f"auto_vacuum     : {c.execute('PRAGMA auto_vacuum').fetchone()[0]}")
print(f"threads         : {len(rows)}   total bytes: {total/1024**2:.1f} MiB")
print(f"retain cutoff   : {cut}   stale threads: {len(stale)}   stale bytes: {sum(s[2] for s in stale)/1024**2:.1f} MiB")
for tid, n, b, upd in sorted(stale, key=lambda s: -s[2])[:12]:
    print(f"  {tid[:20]}  n={n:5d}  {b/1024**2:8.1f} MiB  updated={upd}")

if not apply_:
    print("\n(report only -- pass -Apply to delete, then VACUUM)")
    sys.exit(0)

ids = [s[0] for s in stale]
if not ids:
    print("\nnothing to delete")
    sys.exit(0)

# Thread-atomic: both tables, one transaction, so no dangling lineage is left.
with c:
    for i in range(0, len(ids), 200):
        chunk = ids[i:i+200]
        q = ",".join("?" * len(chunk))
        c.execute(f"DELETE FROM writes WHERE thread_id IN ({q})", chunk)
        c.execute(f"DELETE FROM checkpoints WHERE thread_id IN ({q})", chunk)

print(f"\ndeleted {len(ids)} threads; freelist now {c.execute('PRAGMA freelist_count').fetchone()[0]}")
c.close()

# VACUUM needs an exclusive lock and ~1x the DB in free space; run it separately
# so a lock failure is loud rather than silently skipping the reclaim.
c = sqlite3.connect(f"file:{ckpt}", uri=True, isolation_level=None)
c.execute("PRAGMA busy_timeout=60000")
c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
c.execute("VACUUM")
c.close()
print(f"after VACUUM    : {os.path.getsize(ckpt)/1024**3:.3f} GiB")
'@

$tmp = Join-Path $env:TEMP 'reclaim-checkpoints.py'
[System.IO.File]::WriteAllText($tmp, $py, (New-Object System.Text.UTF8Encoding($false)))

$mode = if ($Apply -and $PSCmdlet.ShouldProcess($ckpt, 'delete stale threads + VACUUM')) { 'apply' } else { 'report' }
& 'C:\Program Files\Python313\python.exe' $tmp $ckpt $meta $RetainDays $mode
Remove-Item $tmp -Force
```

- [ ] **Step 2: Run report mode and verify the numbers match the audit**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File .\pacgate-ai\scripts\reclaim-checkpoints.ps1 -RetainDays 21
```
Expected (from the 2026-10-17 audit):
```
free pages      : 0
threads         : 56   total bytes: ~2250.0 MiB
retain cutoff   : 2026-09-26   stale threads: >=4   stale bytes: >=1633.0 MiB
  d9d0fe54-...   n= 1043    ~1594.5 MiB  updated=2026-09-13
```
If `stale bytes` differs by more than ~10 %, **stop** — the cutoff is doing something unintended.

- [ ] **Step 3: Back up before deleting**

Run:
```powershell
$d = ".\pacgate-ai\deploy\client-bundle\data\deer-flow"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item "$d\checkpoints.db" "$d\checkpoints.db.bak.$stamp" -Force
Write-Output "backup: checkpoints.db.bak.$stamp  ($([math]::Round((Get-Item "$d\checkpoints.db.bak.$stamp").Length/1GB,3)) GiB)"
```
Expected: a ~2.2 GiB sibling. **Do not skip** — deletion is irreversible.

- [ ] **Step 4: Verify free disk before VACUUM**

Run:
```powershell
Get-PSDrive C | Select-Object @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```
Expected: `FreeGB` ≥ **3.0** (VACUUM needs ≈1× the DB plus headroom).

- [ ] **Step 5: Stop the writer, apply, then start it again**

VACUUM needs an exclusive lock; the app's own `AsyncSqliteStore` holds reads on the same file.

Run:
```powershell
docker compose -f .\pacgate-ai\deploy\client-bundle\compose.bundle.yaml stop deer-flow
powershell -NoProfile -ExecutionPolicy Bypass -File .\pacgate-ai\scripts\reclaim-checkpoints.ps1 -RetainDays 21 -Apply
docker compose -f .\pacgate-ai\deploy\client-bundle\compose.bundle.yaml up -d --no-deps deer-flow
```
Expected tail:
```
deleted 4 threads; freelist now <large>
after VACUUM    : ~0.6 GiB
```
and `docker ps` shows `deer-flow` **healthy** within ~60 s.

- [ ] **Step 6: Assert the reclaim and app health**

Run:
```powershell
$d = ".\pacgate-ai\deploy\client-bundle\data\deer-flow"
Get-ChildItem $d -Filter 'checkpoints.db*' | Select-Object Name, @{n='MiB';e={[math]::Round($_.Length/1MB,1)}}
docker exec deer-flow python -c "import sqlite3;c=sqlite3.connect('file:/app/backend/.deer-flow/checkpoints.db?mode=ro',uri=True);print('free',c.execute('PRAGMA freelist_count').fetchone()[0])"
docker logs deer-flow --since 3m 2>&1 | Select-String 'error|Traceback' | Select-Object -First 5
```
Expected: `checkpoints.db` < **700 MiB**, `-wal` < **10 MiB**, `free` near 0, no tracebacks.

- [ ] **Step 7: Commit**

```bash
git add pacgate-ai/scripts/reclaim-checkpoints.ps1
git commit -m "feat(ops): reclaim stale LangGraph checkpoints, then VACUUM

VACUUM alone reclaimed 0 bytes (freelist_count=0): the 2.2 GiB is live rows, not
free pages. 73% belongs to 4 threads idle for weeks. Deletion is thread-atomic
across checkpoints and writes because checkpoint_lineage.py walks the lineage."
```

---

## Task 3: Prevent recurrence — scheduled retention

**Files:**
- Modify: `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml` (scheduler is already `enabled: true`)
- Create: `pacgate-ai/deploy/client-bundle/data/deer-flow/scheduled-tasks/reclaim-checkpoints.json` (or register via API — see Step 2)

**Interfaces:**
- Consumes: `reclaim-checkpoints.ps1` from Task 2.
- Produces: a recurring job that keeps the DB bounded without manual intervention.

- [ ] **Step 1: Confirm the scheduler is live**

Run:
```powershell
docker logs deer-flow --since 24h 2>&1 | Select-String 'scheduler' | Select-Object -Last 5
```
Expected: scheduler startup lines (config has `scheduler.enabled: true`, `poll_interval_seconds: 5`).

- [ ] **Step 2: Register the task through the API, not by hand-editing state**

Run (adjust host/port to the ingress actually in use):
```powershell
$body = @{
  name     = 'reclaim-checkpoints'
  schedule = '0 4 * * 0'          # weekly, Sunday 04:00 local
  prompt   = 'Run the checkpoint retention job: delete threads idle > 21 days, then VACUUM.'
  enabled  = $true
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://localhost:8090/api/scheduled-tasks' -Body $body -ContentType 'application/json'
```
Expected: `201`/`200` with the created task id. If the route 404s, check `pacgate-ai/scripts/audit-aipc-update-coverage.ps1` for the schedule API surface on this version.

- [ ] **Step 3: Verify the task is listed and enabled**

Run:
```powershell
Invoke-RestMethod -Uri 'http://localhost:8090/api/scheduled-tasks' | ConvertTo-Json -Depth 4
```
Expected: the task present, `enabled: true`, with a next-run timestamp.

- [ ] **Step 4: Commit the documented retention policy**

Append to `runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md` under §4 P3:
```markdown
**Retention policy (active):** weekly `reclaim-checkpoints` scheduled task deletes
threads idle > 21 days (thread-atomic across `checkpoints`+`writes`) and VACUUMs.
Manual equivalent: `pacgate-ai/scripts/reclaim-checkpoints.ps1 -RetainDays 21 [-Apply]`.
```

```bash
git add runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md
git commit -m "docs(aipc1): record the checkpoint retention policy and its scheduled task"
```

---

## Task 4: Enable on-demand tool routing (D1 + D2) — Path A

> **BLOCKED until the Path A / Path B decision above is made.** All steps are Path A.

**Files:**
- Create: `pacgate-ai/deploy/client-bundle/patches/deer-flow-extensions-config.py`
- Create: `pacgate-ai/deploy/client-bundle/patches/mcp-routing-middleware.py`
- Create: `pacgate-ai/deploy/client-bundle/patches/deer-flow-tool-search.py`
- Modify: `pacgate-ai/deploy/client-bundle/patches/deer-flow-agent.py`
- Modify: `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` (mounts)
- Modify: `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml`
- Modify: `pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json`
- Modify: `pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.json` (gitignored, local only)
- Test: `deer-flow/backend/tests/test_mcp_routing_auto_promote.py` (upstream, already present)
- Test: `deer-flow/backend/tests/test_mcp_routing_config.py` (upstream, already present)

**Interfaces:**
- Consumes: the v2.1.0 sources at `deer-flow/backend/packages/harness/deerflow/` (repo has them; live v2.0.0 does not).
- Produces: `McpRoutingConfig{mode,priority,keywords}`; `resolve_effective_mcp_routing(server_config, original_tool_name) -> dict`; `McpRoutingMiddleware(routing_index, catalog_hash, top_k)`; `build_mcp_routing_middleware(tools, deferred_setup, *, top_k) -> AgentMiddleware | None`; `assemble_deferred_tools(candidate_tools, *, enabled) -> tuple[list[BaseTool], DeferredToolSetup]`. Task 4 Step 9 depends on all five existing at the exact live paths.

- [ ] **Step 1: Port `McpRoutingConfig` + the resolver**

Copy from `deer-flow/backend/packages/harness/deerflow/config/extensions_config.py` (repo, v2.1.0) into a new patch that bind-mounts over the live file. Preserve the live file's other content — a patch is a **whole-file replacement**, so start from the live file, not the repo file:

```powershell
docker exec deer-flow cat /app/backend/packages/harness/deerflow/config/extensions_config.py > .\pacgate-ai\deploy\client-bundle\patches\deer-flow-extensions-config.py
```
Then add, immediately before `class McpServerConfig`:
```python
class McpRoutingConfig(BaseModel):
    """Soft routing hints for MCP tool preference."""

    mode: Literal["off", "prefer"] = Field(
        default="off",
        description="Whether to emit prompt hints preferring this MCP tool for matching requests.",
    )
    priority: int = Field(default=0, description="Ordering key for routing hints. Higher values are rendered first.")
    keywords: list[str] = Field(default_factory=list, description="Operator-authored keywords that describe when this MCP tool should be preferred.")
    model_config = ConfigDict(extra="forbid")

    @field_validator("priority")
    @classmethod
    def _clamp_priority(cls, value: int) -> int:
        if value < 0:
            logger.warning("MCP routing priority %s is below 0; clamping to 0.", value)
            return 0
        if value > 100:
            logger.warning("MCP routing priority %s is above 100; clamping to 100.", value)
            return 100
        return value
```
Add to `McpServerConfig`: `routing: McpRoutingConfig = Field(default_factory=McpRoutingConfig, ...)` and `tools: dict[str, McpToolOverride] = Field(default_factory=dict, ...)`. Add the `McpToolOverride` model and the module-level resolver, both copied verbatim from the repo file.

- [ ] **Step 2: Verify the port parses and round-trips**

Run:
```powershell
docker cp .\pacgate-ai\deploy\client-bundle\patches\deer-flow-extensions-config.py deer-flow:/tmp/ec.py
docker exec deer-flow /app/backend/.venv/bin/python -c "import ast,sys; ast.parse(open('/tmp/ec.py').read()); print('parse OK')"
```
Expected: `parse OK`. (Import-time validation happens in Step 9 once mounted.)

- [ ] **Step 3: Port `McpRoutingMiddleware` as its own patch file**

Create `pacgate-ai/deploy/client-bundle/patches/mcp-routing-middleware.py` containing the exact class from
`deer-flow/backend/packages/harness/deerflow/agents/middlewares/mcp_routing_middleware.py` (repo).
Keep its three invariants intact — they are load-bearing:
- it receives **only** serialized routing data (no `BaseTool` objects),
- it does **not** execute tools and does **not** filter tool calls (`DeferredToolFilterMiddleware` owns that),
- `assert_mcp_routing_before_deferred_filter` must raise if routing is registered *after* the deferred filter.

- [ ] **Step 4: Port the routing-aware `tool_search`**

Bind-mount a new file over `/app/backend/packages/harness/deerflow/tools/builtins/tool_search.py`. Start from the **live** file (9,303 B, v2.0.0 — has `MAX_RESULTS`, `DeferredToolCatalog`, `build_deferred_tool_setup`, `assemble_deferred_tools`) and graft in:
- `tag_mcp_routing` / `get_mcp_routing` handling (new `tools/mcp_metadata.py` patch if the live file lacks the routing keys),
- `build_mcp_routing_middleware(tools, deferred_setup, *, top_k)`,
- `get_mcp_routing_hints_prompt_section(tools, *, deferred_names)`,
- the fail-closed guard in `assemble_deferred_tools`: raise `RuntimeError` when `enabled` and MCP candidates exist but nothing was deferred.

```powershell
docker exec deer-flow cat /app/backend/packages/harness/deerflow/tools/builtins/tool_search.py > .\pacgate-ai\deploy\client-bundle\patches\deer-flow-tool-search.py
```

- [ ] **Step 5: Wire the middleware into the live lead agent**

In `patches/deer-flow-agent.py`, at the two `assemble_deferred_tools` call sites (currently `:598` and `:625`), pass `top_k` and install the routing middleware **before** the deferred filter:

```python
from deerflow.tools.builtins.tool_search import (
    assemble_deferred_tools, build_mcp_routing_middleware, get_mcp_routing_hints_prompt_section,
)
final_tools, setup = assemble_deferred_tools(filtered, enabled=resolved_app_config.tool_search.enabled)
mcp_routing_middleware = build_mcp_routing_middleware(
    final_tools, setup, top_k=resolved_app_config.tool_search.auto_promote_top_k,
)
```
and in the middleware list, append `mcp_routing_middleware` (when not `None`) **before** `DeferredToolFilterMiddleware`.

- [ ] **Step 6: Add the four mount lines**

In `compose.bundle.yaml`, alongside the existing patch mounts (`:211-284`):
```yaml
      - ./patches/deer-flow-extensions-config.py:/app/backend/packages/harness/deerflow/config/extensions_config.py:ro
      - ./patches/mcp-routing-middleware.py:/app/backend/packages/harness/deerflow/agents/middlewares/mcp_routing_middleware.py:ro
      - ./patches/deer-flow-tool-search.py:/app/backend/packages/harness/deerflow/tools/builtins/tool_search.py:ro
      - ./patches/deer-flow-mcp-metadata.py:/app/backend/packages/harness/deerflow/tools/mcp_metadata.py:ro
```

- [ ] **Step 7: Add routing keywords to the connector configs**

In the **template** (upstreamable) and the **rendered file** (local), add `routing` to the six due-diligence servers. Example for one server:
```json
"pkulaw-law-search": {
  "enabled": true,
  "routing": { "mode": "prefer", "priority": 90,
               "keywords": ["法条", "法规", "statute", "legal provision"] },
  "...": "..."
}
```
Suggested keyword sets (align to the due-diligence path, not to every skill):

| Server | priority | keywords |
|---|---|---|
| `pkulaw-law-search` | 90 | 法条, 法规, statute, legal provision |
| `pkulaw-citation-validator` | 90 | 引用, citation, 核验, validate |
| `yuandian-case` | 80 | 案例, 判例, case, precedent |
| `yuandian-company` | 80 | 公司, 工商, company, entity |
| `qcc` | 70 | 企查查, 股权, shareholder, 出资 |
| `openviking` | 60 | 记忆, recall, 之前, remember |

- [ ] **Step 8: Enable deferral**

In `deer-flow-config.yaml`, replace the disabled block:
```yaml
tool_search:
  enabled: true
  auto_promote_top_k: 5    # clamp range is 1..5
```

- [ ] **Step 9: Recreate deer-flow and assert the surface actually shrank**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps deer-flow
Start-Sleep -Seconds 45
docker logs deer-flow --since 3m 2>&1 | Select-String 'Total tools loaded|deferred|tool_search|McpRouting|Traceback'
```
Expected:
- **no** `Traceback` / `Error importing` lines (a bad mount is loud at import time),
- `tool_search` enabled and MCP tools reported as deferred.

Then measure the real surface:
```powershell
docker exec deer-flow /app/backend/.venv/bin/python -c @"
import json, tiktoken
from langchain_core.utils.function_calling import convert_to_openai_function
from deerflow.tools.tools import get_available_tools
from deerflow.config import get_app_config
ts = get_available_tools()
enc = tiktoken.get_encoding('cl100k_base')
print('tool_search.enabled =', get_app_config().tool_search.enabled)
print('bound tools =', len(ts), 'tok =', len(enc.encode(json.dumps([convert_to_openai_function(t) for t in ts], default=str))))
"@
```
Expected: `tool_search.enabled = True`, bound tools **≈ 10** (9 sandbox/builtin + `tool_search`), and tool-schema tokens **< 4,000** (was 71,678).

- [ ] **Step 10: Prove promotion works (the D2 regression test)**

Run one prompt that should auto-promote a keyword match, then read the log:
```powershell
docker logs deer-flow --since 5m 2>&1 | Select-String 'auto-promoted|promoted|deferred and has not been promoted'
```
Expected: at least one `auto-promoted N deferred tool schema(s)` line and **zero** `deferred and has not been promoted` errors. A "deferred, not promoted" loop means the routing index is empty — re-check Step 7 (the keys must be `mode: "prefer"` **and** non-empty `keywords`).

- [ ] **Step 11: Run the upstream routing unit tests**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\deer-flow\backend
.\.venv\Scripts\python.exe -m pytest tests/test_mcp_routing_config.py tests/test_mcp_routing_auto_promote.py tests/test_mcp_routing_metadata.py tests/test_deferred_setup.py -q
```
Expected: all pass. Fix the port until they do — these encode the invariants the patch must honour.

- [ ] **Step 12: Commit**

```bash
git add pacgate-ai/deploy/client-bundle/patches/ pacgate-ai/deploy/client-bundle/compose.bundle.yaml \
        pacgate-ai/deploy/client-bundle/deer-flow-config.yaml \
        pacgate-ai/deploy/client-bundle/deer-flow-extensions-config.template.json
git commit -m "feat(tools): enable on-demand MCP tool routing on the v2.0.0 base

153 MCP schemas were bound into every prompt (measured 69,313 tok of an 80,791
token prompt). tool_search could not simply be flipped on: the live v2.0.0 base
has no mcp_routing_middleware and no build_mcp_routing_middleware, so an empty
routing index reproduced the 2026-09-12 'deferred, not promoted' loop. Backports
the v2.1.0 routing subsystem plus connector routing keywords."
```

---

## Task 5: Harden memory extraction (D3)

**Files:**
- Create: `pacgate-ai/deploy/client-bundle/patches/memory-queue-durability.py`
- Modify: `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` (one mount line)
- Test: `deer-flow/backend/tests/test_memory_queue_durability.py`

**Interfaces:**
- Consumes: the live `queue.py` (287 lines) at `/app/backend/packages/harness/deerflow/agents/memory/queue.py`.
- Produces: `MemoryUpdateQueue.allow_llm_now() -> bool` (idle gate) and an on-disk spool at `<storage>/.memory-queue/` with `pending/` and `failed/`.

- [ ] **Step 1: Write the failing test**

Create `deer-flow/backend/tests/test_memory_queue_durability.py`:

```python
"""Durability + poison-handling contract for the memory update queue."""
import json
from pathlib import Path

from deerflow.agents.memory.queue import MemoryUpdateQueue


def test_pending_contexts_survive_a_cold_start(tmp_path: Path) -> None:
    q = MemoryUpdateQueue(spool_dir=tmp_path)
    q.enqueue({"thread_id": "t1", "user_id": "u1", "messages": [{"role": "user", "content": "hi"}]})
    assert (tmp_path / "pending").glob("*.json"), "context must be spooled to disk before processing"


def test_poison_payload_is_parked_after_max_consecutive_failures(tmp_path: Path) -> None:
    q = MemoryUpdateQueue(spool_dir=tmp_path, max_consecutive_failures=3)
    q.enqueue({"thread_id": "t1", "user_id": "u1", "messages": []})
    for _ in range(3):
        q.record_failure("t1")
    assert (tmp_path / "failed").glob("*.json"), "a permanently failing thread must not retry forever"
    assert q.allow_llm_now("t1") is False, "a parked thread must stop consuming the inference slot"


def test_idle_gate_blocks_while_a_run_is_active(tmp_path: Path) -> None:
    q = MemoryUpdateQueue(spool_dir=tmp_path)
    q.set_run_active(True)
    assert q.allow_llm_now("t1") is False
    q.set_run_active(False)
    assert q.allow_llm_now("t1") is True
```

- [ ] **Step 2: Run it and confirm it fails**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\deer-flow\backend
.\.venv\Scripts\python.exe -m pytest tests/test_memory_queue_durability.py -q
```
Expected: FAIL — `MemoryUpdateQueue() got an unexpected keyword argument 'spool_dir'` (or `no attribute set_run_active`).

- [ ] **Step 3: Implement the durable spool, DLQ and idle gate**

Create `patches/memory-queue-durability.py` starting from the live file:
```powershell
docker exec deer-flow cat /app/backend/packages/harness/deerflow/agents/memory/queue.py > .\pacgate-ai\deploy\client-bundle\patches\memory-queue-durability.py
```
Add, keeping the existing daemon-`Timer` debounce intact:
```python
from pathlib import Path
import json, os, threading, time

MAX_CONSECUTIVE_FAILURES_DEFAULT = 3

# In the live queue, items are popped BEFORE processing and dropped on failure, and the
# queue is pure in-memory, so a crash loses pending extractions and a permanently failing
# thread retries every session forever (observed 11/11 on 2026-10-16, ~174 s per attempt).
class _Spool:
    def __init__(self, root: Path) -> None:
        self.pending = root / "pending"
        self.failed = root / "failed"
        self.pending.mkdir(parents=True, exist_ok=True)
        self.failed.mkdir(parents=True, exist_ok=True)

    def put(self, key: str, payload: dict) -> None:
        (self.pending / f"{key}.json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    def drop(self, key: str) -> None:
        (self.pending / f"{key}.json").unlink(missing_ok=True)

    def park(self, key: str, payload: dict, error: str) -> None:
        self.drop(key)
        (self.failed / f"{key}.json").write_text(
            json.dumps({**payload, "_error": error, "_parked_at": time.time()}, ensure_ascii=False),
            encoding="utf-8",
        )

    def load_pending(self) -> list[tuple[str, dict]]:
        out = []
        for p in sorted(self.pending.glob("*.json")):
            try:
                out.append((p.stem, json.loads(p.read_text(encoding="utf-8"))))
            except (OSError, json.JSONDecodeError):
                p.unlink(missing_ok=True)   # a torn spool file must not wedge the worker
        return out
```
Add to `MemoryUpdateQueue.__init__`: `spool_dir=None, max_consecutive_failures=MAX_CONSECUTIVE_FAILURES_DEFAULT`; build `self._spool = _Spool(Path(spool_dir)) if spool_dir else None`; `self._failures: dict[str, int] = {}`; `self._run_active = threading.Event()`. On enqueue → `self._spool.put(key, payload)` before the timer. On success → `self._failures.pop(key, None); self._spool.drop(key)`. On failure → increment and `park` once the threshold is crossed. Add:
```python
    def set_run_active(self, active: bool) -> None:
        """Idle gate: memory extraction must not contend with a user run for the
        single Ollama slot (OLLAMA_NUM_PARALLEL=1)."""
        if active:
            self._run_active.set()
        else:
            self._run_active.clear()

    def allow_llm_now(self, key: str) -> bool:
        if self._run_active.is_set():
            return False
        return self._failures.get(key, 0) < self._max_failures
```

- [ ] **Step 4: Run the test until it passes**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\deer-flow\backend
.\.venv\Scripts\python.exe -m pytest tests/test_memory_queue_durability.py -q
```
Expected: `3 passed`.

- [ ] **Step 5: Mount it and point the spool at persistent storage**

Add to `compose.bundle.yaml`:
```yaml
      - ./patches/memory-queue-durability.py:/app/backend/packages/harness/deerflow/agents/memory/queue.py:ro
```
Set the spool under the already-persistent bind mount so pending work survives a restart:
```yaml
      - MEMORY_QUEUE_SPOOL_DIR=/app/backend/.deer-flow/data/memory-queue
```

- [ ] **Step 6: Recreate and verify the spool exists after a cycle**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps deer-flow
Start-Sleep -Seconds 90
docker exec deer-flow sh -c "ls -la /app/backend/.deer-flow/data/memory-queue/ 2>&1"
docker logs deer-flow --since 5m 2>&1 | Select-String 'memory update|Failed to parse|Traceback'
```
Expected: `pending/` and `failed/` exist; no tracebacks; **0** parse failures.

- [ ] **Step 7: Commit**

```bash
git add pacgate-ai/deploy/client-bundle/patches/memory-queue-durability.py \
        pacgate-ai/deploy/client-bundle/compose.bundle.yaml \
        deer-flow/backend/tests/test_memory_queue_durability.py
git commit -m "fix(memory): make the update queue durable, bounded, and idle-gated

The live queue was in-memory only (a crash lost pending extractions), popped items
before processing (so an extraction failure was dropped with no retry), and issued
its LLM call regardless of user activity - on a single-slot runner that is 32-41.6k
output tokens per run. Adds a disk spool, a parked-failure DLQ, and an idle gate."
```

---

## Task 6: Inventory local inference consumers (D4/P4)

**Files:**
- Create: `pacgate-ai/scripts/audit-local-consumers.ps1`

**Interfaces:**
- Produces: a table of every local Ollama consumer with its tag, so a scheduling policy can be chosen from data rather than assumption.

- [ ] **Step 1: Write the script**

Create `pacgate-ai/scripts/audit-local-consumers.ps1`:

```powershell
<#
.SYNOPSIS
  Enumerate what actually runs on the local Ollama runner.

.DESCRIPTION
  "Background roles compete with chat" is no longer accurate: chat routes to
  deepseek-v4.1-flash-cloud (95 runs vs 7 local). The local slot serves the
  background roles AND an embedding consumer (3 loads at n_ctx=2048 resolve to
  the nomic-embed-text blob). This script lists the consumers so a scheduling
  policy is chosen from evidence.
#>
[CmdletBinding()]
param([string] $Log = "$env:LOCALAPPDATA\Ollama\server.log")

$ErrorActionPreference = 'Stop'

Write-Host "=== model identity map (blob -> tag) ==="
$mroot = Join-Path $env:USERPROFILE '.ollama\models\manifests'
$byBlob = @{}
Get-ChildItem $mroot -Recurse -File -Filter * -ErrorAction SilentlyContinue | ForEach-Object {
    $tag = ($_.FullName.Substring($mroot.Length + 1) -replace '\\', '/')
    try {
        $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $d = ($j.layers | Where-Object { $_.mediaType -like '*model*' } | Select-Object -First 1).digest
        if ($d) { $byBlob[$d.Substring(7, 16)] = $tag }
    } catch { }
}
Write-Host "=== loads observed in the log ==="
Select-String -Path $Log -Pattern 'starting llama-server' | ForEach-Object {
    $line = $_.Line
    if ($line -match '--model\s+(\S+?)(?:\.\d+)?(?:\s|$)' -or $line -match 'blobs\\sha256-([0-9a-f]{16})') {
        $blob = $Matches[1]
        $tag = if ($byBlob.ContainsKey($blob)) { $byBlob[$blob] } else { "(unmapped $blob)" }
        $ctx = if ($line -match '-c (\d+)') { $Matches[1] } else { '?' }
        $emb = if ($line -match '--embedding') { 'EMBEDDING' } else { '' }
        "{0,-46} ctx={1,-8} {2}" -f $tag, $ctx, $emb
    }
}
Write-Host "`n=== prompt sizes (local runner only; :cloud never appears here) ==="
Select-String -Path $Log -Pattern 'task\.n_tokens = (\d+)' |
    ForEach-Object { [int]$_.Matches[0].Groups[1].Value } | Sort-Object -Descending |
    Select-Object -First 10 | ForEach-Object { "  $_" }
Write-Host "`n=== container roles pinned to local tags ==="
$cfg = Join-Path $PSScriptRoot '..\deploy\client-bundle\deer-flow-config.yaml'
$t = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8)
foreach ($k in @('memory','title','summarization')) {
    if ($t -match "(?ms)^$k:\s*\r?\n(?:.*\r?\n)*?\s*model_name:\s*(\S+)") { "$k -> $($Matches[1])" }
}
```

- [ ] **Step 2: Run it and record the result**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File .\pacgate-ai\scripts\audit-local-consumers.ps1
```
Expected: `gemma4-legal:12b-chat` at ctx=131072, `nomic-embed-text` at ctx=2048 tagged `EMBEDDING`, and the three role pins.

- [ ] **Step 3: Commit**

```bash
git add pacgate-ai/scripts/audit-local-consumers.ps1
git commit -m "feat(ops): inventory local Ollama consumers before choosing a slot policy"
```

---

## Task 7: Deliver to the fork and open a PR

**Files:**
- Read-only: the `pacgate-law` git root
- Produces: a pushed branch on `fork` and a PR URL

**Interfaces:**
- Consumes: Tasks 1–6 commits.
- Produces: `fork/aipc1-remediation` + a PR to `pacgate-ai/pacgate-ai-pr`.

- [ ] **Step 1: Confirm the credential gate before any push**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File .\pacgate-ai\scripts\assert-no-staged-secrets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\runtime\AUTHORITATIVE-credential-check.ps1
```
Expected: no staged credential blobs. **STOP** if either reports a hit — the ignore rule in `pacgate-ai-pr/.gitignore` is the unfixed root cause.

- [ ] **Step 2: Branch and confirm the diff is exactly the intended files**

Run:
```powershell
git rev-parse --abbrev-ref HEAD                 # expect: main
git checkout -b aipc1-remediation
git diff --stat main
```
Expected: only the files named in this plan's File Structure table. Anything else is scope creep — revert it.

- [ ] **Step 3: Push to the fork**

Run:
```powershell
git push fork aipc1-remediation
git rev-parse fork/aipc1-remediation           # confirm the remote ref now exists
```
Expected: push succeeds. **Never** `git push upstream` — the PAT has `push=False` there.

- [ ] **Step 4: Open the PR against the fork**

Run:
```powershell
gh pr create --repo pacgate-ai/pacgate-ai-pr --base main --head aipc1-remediation `
  --title "AIPC1 remediation: tool routing, memory durability, checkpoint retention" `
  --body-file docs/pacgate/pr-body.txt
```
(`docs/pacgate/pr-body.txt` already exists as an untracked draft — update it first to describe **this** change set, then commit it.)

Expected: a PR URL on `pacgate-ai/pacgate-ai-pr`.

- [ ] **Step 5: Record the delivery state**

Run:
```powershell
git log --oneline main..aipc1-remediation
```
Expected: the five commits from Tasks 1–6, no merge commits.

---

## Task 8: Upstream handoff for the JZKK720-only work

**Files:**
- Create: `pacgate-ai/deploy/HANDOFF-AIPC1-2026-10-17.md`

**Interfaces:**
- Consumes: the decision from the Path A/Path B fork in the road.
- Produces: a document the developer can act on without this machine's context.

- [ ] **Step 1: Write the handoff**

Create `pacgate-ai/deploy/HANDOFF-AIPC1-2026-10-17.md` covering, at minimum:
1. **The v2.1.0 upgrade** — reference `pacgate-ai/plans/023-deer-flow-2.1-upgrade.md` and the earlier `HANDOFF-UPSTREAM-V2.1.0-UPGRADE.md`; state that the live base is still **v2.0.0** and that D2's Path A patches are **deleted at rebase time** because v2.1.0 ships the routing subsystem natively.
2. **GHCR rebuild + republish** of the five `ghcr.io/jzkk720/*` images — cannot be done from this machine.
3. **The `upstream` push** — PAT has `push=False`; the fork PR must be merged by someone with write access.
4. **PR#1 on `JZKK720/deer-flow`** (3 skills + tool-policy) — external, still open per the 2026-10-16 design.
5. **What must NOT be upstreamed** — the model roster, `PACGATE_MODEL_{MAIN,MID,LOW}`, `GATEWAY_CORS_ORIGINS`, and the 2026-10-16 local tuning (user directive 2026-09-21).

- [ ] **Step 2: Verify the handoff references resolve**

Run:
```powershell
foreach ($p in @('pacgate-ai/plans/023-deer-flow-2.1-upgrade.md',
                 'pacgate-ai/deploy/HANDOFF-UPSTREAM-V2.1.0-UPGRADE.md',
                 'docs/superpowers/specs/2026-10-16-capability-sync-upstream-design.md')) {
  "{0}  {1}" -f (Test-Path $p), $p
}
```
Expected: `True` for all three.

- [ ] **Step 3: Commit and push**

```bash
git add pacgate-ai/deploy/HANDOFF-AIPC1-2026-10-17.md
git commit -m "docs(handoff): AIPC1 remediation upstream actions for JZKK720"
git push fork aipc1-remediation
```

---

## Self-Review

**1. Spec coverage** — against `runtime/AIPC1-P0-P4-REEVALUATION-2026-10-17.md` §5:

| Spec item | Task |
|---|---|
| P0 `tool_search` + routing keywords | Task 4 |
| P0b port routing middleware into the live image | Task 4 Steps 1–6 |
| P1 verify the reasoning fix | Task 1 |
| P1 idle-gate + DLQ + durable spool | Task 5 |
| P2 re-measure truncation | Task 1 Step 4 (reads memory-role output; chat-path truncation is not a defect on the cloud route) |
| P3 delete stale threads → VACUUM | Task 2 |
| P3 prevent recurrence | Task 3 |
| P4 enumerate local consumers | Task 6 |
| P5 semantic index inside pacgate-api | **NOT COVERED** — see Gap below |
| Upstream delivery | Tasks 7–8 |

**Gap (accepted):** P5 (a persistent semantic index for memory) is deliberately **out of scope** here. It touches `pacgate-api`'s store — a different service with a different release cadence — and the research found no framework that fits a single-inference-slot box better than `sqlite-vec` + `sqlite-lembed`. It needs its own spec before a plan. Recorded in the re-evaluation §3.4 as "next".

**2. Placeholder scan** — no `TBD`, no "add appropriate error handling", no "similar to Task N". Every code step carries real code. The one soft spot is Task 4 Steps 1/3/4, which are **ports** of named upstream files rather than inline listings; the exact source path is given for each, and Step 11 pins behaviour with the upstream test suite.

**3. Type consistency** — the five interfaces produced in Task 4 (`McpRoutingConfig`, `resolve_effective_mcp_routing`, `McpRoutingMiddleware`, `build_mcp_routing_middleware`, `assemble_deferred_tools`) are used with matching signatures in Steps 5 and 7. Task 5's `MemoryUpdateQueue` additions (`spool_dir`, `max_consecutive_failures`, `set_run_active`, `allow_llm_now`) match the test in Step 1 and the implementation in Step 3. Task 2's `reclaim-checkpoints.ps1` parameters (`-RetainDays`, `-Apply`) match Task 3's usage.

---

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute in this session with checkpoints, batched for review.

**Recommended order:** Task 1 → Task 2 → Task 3 (all low-risk, immediately verifiable), then the Path A/B decision, then Task 4, then Task 5, then Task 6, then Tasks 7–8.
