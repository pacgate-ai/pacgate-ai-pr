# Adopt upstream `86a9feb..44f7f43` — windowed loop guard (5 commits)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land upstream's five commits into the `pacgate-ai/` subtree, fix the two defects that would otherwise leave this AIPC broken or permanently red, and roll out on `compose.bundle.yaml`.

**Architecture:** The fix has two halves that must ship together. (a) `patches/deer-flow-loop-detection.py` replaces Layer 2's monotonic per-tool counter with a windowed `deque` + mirrored `Counter`, so spread-out calls decay instead of summing to a hard stop. (b) A `loop_detection:` config block raises only `bash` (warn 100 / hard 150) while the global ceiling stays at 50. Windowing alone is insufficient: the middleware auto-sizes its window to the largest hard limit, so a ceiling of 50 gives a window of 50, and the measured bash-heaviest run already packs 48 bash calls into 50.

**Tech Stack:** Docker Compose (project `pacgate-ai-bundle`), PowerShell 5.1, deer-flow bind-mounted patches, LangChain middleware.

## Global Constraints

- **`git` is not on PATH.** Prepend `$env:Path += ";C:\Program Files\Git\cmd"`.
- **PS 5.1 native stderr under `$ErrorActionPreference='Stop'` is a TERMINATING error.** Scope the preference to `'Continue'` around any native call whose stderr you read. This is the root of Defect 1 and has now bitten this repo three times.
- **Never `Get-Content`/`Set-Content` on UTF-8 CJK files.** Use `[System.IO.File]::ReadAllBytes`/`WriteAllBytes`.
- **Quote `"REV^{tree}"`** — unquoted, PowerShell parses `^` and fails.
- **Do NOT run `install.ps1 -Update`.** It renders `deer-flow-extensions-config.json` from a 3-server template and would drop **27 of 30** MCP connectors. Use the bundle recreate in Task 7.
- **Both compose files must stay patch-mount parity** — `test-workflow-compose-wiring.ps1` A5 and `test-loop-detection-window.ps1` both assert it.
- **`registry-1.docker.io` is unreachable here** (`code=000`). Do not attempt image pulls; all five images stay at `0.2.6`.
- **Red line:** every AI output is a draft for lawyer review. A loop guard that force-stops a productive document run mid-work is a correctness failure, not a performance one — it truncates the deliverable.

---

### Task 1: Snapshot local deltas and confirm the fetch

`git fetch upstream` succeeded on 2026-10-27 (it failed on 2026-10-26), so the
commits are already in the object store. Snapshot the deltas the swap will revert.

**Files:**
- Create: `runtime/sync-1027/local-preserve/`
- Create: `runtime/sync-1027/local-delta-list.txt`

**Interfaces:**
- Produces: `runtime/sync-1027/local-preserve/<path>` for every delta, consumed by Task 5.

- [ ] **Step 1: Confirm the five commits are present**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git rev-parse --short upstream/main
foreach ($c in @('e30b05e','02ed22b','7ca69eb','af905f4','44f7f43')) {
    '{0}  {1}' -f $c, (git cat-file -t $c 2>&1)
}
```

Expected: `44f7f43`, then five lines each ending `commit`. Any `fatal:` means the
fetch did not land — re-run `git fetch upstream` before continuing.

- [ ] **Step 2: Snapshot every local delta against the adopted base `86a9feb`**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File .\runtime\sync-1026\snapshot-deltas.ps1
```

Expected: `delta_count=63`, `missing=0 byte_mismatches=0`.

> Reuses the 2026-10-26 script, which already solves the two encoding traps:
> `ls-tree -z` plus reading the stream as UTF-8 bytes (PS 5.1 decodes native
> stdout as GBK, which silently mojibake'd 56 CJK paths), and
> `Start-Process -RedirectStandardOutput` (PS `>` writes UTF-16 and destroys a
> NUL-separated stream).

- [ ] **Step 3: Copy the snapshot to the new sync folder**

```powershell
$src = 'C:\Users\pacga\github-pr\pacgate-law\runtime\sync-1026'
$dst = 'C:\Users\pacga\github-pr\pacgate-law\runtime\sync-1027'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "$src\local-preserve" $dst -Recurse -Force
Copy-Item "$src\local-delta-list.txt" $dst -Force
'preserved=' + (Get-ChildItem -Recurse -File "$dst\local-preserve").Count
```

Expected: `preserved=63`.

- [ ] **Step 4: Commit the snapshot**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add runtime/sync-1027 runtime/VERIFICATION-2026-10-27-upstream-loop-guard.md
git commit -m "chore(sync): snapshot local deltas before adopting the loop-guard commits"
```

Expected: one commit.

---

### Task 2: Swap the subtree to `44f7f43`

**Files:**
- Modify: tracked paths under `pacgate-ai/`

**Interfaces:**
- Consumes: `upstream/main` = `44f7f43`.
- Produces: `pacgate-ai/` byte-identical to `44f7f43`'s tree.

- [ ] **Step 1: Record the target tree SHA**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
$target = (git rev-parse 'upstream/main^{tree}').Trim()
"target_tree=$target"
```

Expected: a 40-char SHA. Note it — Step 3 compares against it.

- [ ] **Step 2: Swap by index**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git rm -r --cached pacgate-ai --quiet
git read-tree --prefix=pacgate-ai/ "upstream/main^{tree}"
git checkout -- pacgate-ai
'worktree_done'
```

Expected: `worktree_done`, no fatal errors.

- [ ] **Step 3: Prove byte-identity by tree SHA**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
$root = (git write-tree).Trim()
"subtree=$((git rev-parse "$($root):pacgate-ai").Trim())"
"target =$((git rev-parse 'upstream/main^{tree}').Trim())"
```

Expected: both identical. **If not, STOP** — do not proceed on a wrong tree.

- [ ] **Step 4: Confirm the new files arrived**

```powershell
$b = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai'
foreach ($f in @(
    'deploy\client-bundle\patches\deer-flow-loop-detection.py',
    'scripts\test-loop-detection-window.ps1',
    'scripts\preflight-docker-egress.ps1')) {
    '{0,-6} {1}' -f (Test-Path (Join-Path $b $f)), $f
}
```

Expected: three `True`.

---

### Task 3: Re-apply the local deltas (4 merges)

**Files:**
- Modify: the 63 delta files; 4 of them need a merge rather than a restore.

**Interfaces:**
- Consumes: `runtime/sync-1027/local-preserve/`.
- Produces: a tree whose only difference from `44f7f43` is the local delta set.

- [ ] **Step 1: Restore the 59 non-colliding deltas verbatim**

```powershell
$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$preserve = Join-Path $repo 'runtime\sync-1027\local-preserve'
$upstreamTouched = @(
    'pacgate-ai/deploy/client-bundle/compose.bundle.yaml'
    'pacgate-ai/deploy/client-bundle/compose.prod.yaml'
    'pacgate-ai/deploy/client-bundle/deer-flow-config.yaml'
    'pacgate-ai/scripts/run-all-checks.ps1'
)
$rows = (([System.Text.Encoding]::UTF8.GetString(
    [System.IO.File]::ReadAllBytes((Join-Path $repo 'runtime\sync-1027\local-delta-list.txt')))) -split "`n") |
    Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split "`t")[0] }

$n = 0
foreach ($p in $rows) {
    if ($upstreamTouched -contains $p) { continue }
    $src = Join-Path $preserve ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { "SKIP $p"; continue }
    $dst = Join-Path $repo ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    [System.IO.File]::WriteAllBytes($dst, [System.IO.File]::ReadAllBytes($src))
    $n++
}
"restored_verbatim=$n"
```

Expected: `restored_verbatim=59`.

- [ ] **Step 2: Merge the loop-detection mount into both compose files**

Upstream already added the mount to both files, so this step only **verifies** it
survived and that our own mounts are still present.

```powershell
$base = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle'
foreach ($f in @('compose.bundle.yaml','compose.prod.yaml')) {
    $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $base $f)))
    "--- $f"
    foreach ($n in @('deer-flow-loop-detection.py','deer-flow-memory-prompt.py',
                     'deer-flow-memory-updater.py','deer-flow-uploads-middleware.py',
                     'deer-flow/skills/public')) {
        '  {0,-6} {1}' -f $t.Contains($n), $n
    }
}
```

Expected: **all five `True` in both files.** If `deer-flow-loop-detection.py` is
`False`, re-insert it next to the `deer-flow-agent.py` mount.

- [ ] **Step 3: Merge the `loop_detection:` config block (Defect 2)**

Our `deer-flow-config.yaml` carries a large local `subagents:` block, so this is a
targeted insert, not an overwrite.

```powershell
$cfg = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\deer-flow-config.yaml'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($cfg))
if ($t.Contains('loop_detection:')) {
    'already present'
} else {
    $nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
    $anchor = 'uploads:' + $nl + '  auto_convert_documents: true'
    $idx = $t.IndexOf($anchor)
    if ($idx -lt 0) { throw 'anchor not found: uploads/auto_convert_documents' }
    $block = @(
''
'# Pacgate 2026-10-27: size the per-tool loop guard so it can tell productive work'
'# from a loop. The windowed fix lives in patches/deer-flow-loop-detection.py; the'
'# CEILING lives here. Windowing alone is not enough: the middleware auto-sizes its'
'# window to the largest hard limit, so a ceiling of 50 means a window of 50, and'
'# the bash-heaviest run measured on this box packs 48 bash calls into 50.'
'#'
'# Measured same-tool density in a 150-call window, worst across 33 recorded runs:'
'#     bash        74 of 150     <- the tool that needs the room'
'#     write_file  22 of 150'
'#     read_file   10 of 150'
'# Only bash is raised. The global ceiling stays at 50, so 50 read_file calls in'
'# 150 slots still trips while real usage peaks at 10. Layer 1 (identical-call'
'# hash, warn 3 / hard-stop 5) is untouched and is what catches a true repeat loop.'
'loop_detection:'
'  tool_freq_warn: 50'
'  tool_freq_hard_limit: 75'
'  tool_freq_overrides:'
'    bash:'
'      warn: 100'
'      hard_limit: 150'
    ) -join $nl
    $insertAt = $idx + $anchor.Length
    $t = $t.Substring(0, $insertAt) + $block + $t.Substring($insertAt)
    [System.IO.File]::WriteAllText($cfg, $t, [System.Text.UTF8Encoding]::new($false))
    'inserted loop_detection block'
}
```

Expected: `inserted loop_detection block` (or `already present`).

- [ ] **Step 4: Verify the config block parses and our subagents block survived**

```powershell
$cfg = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\deer-flow-config.yaml'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($cfg))
'loop_detection      = ' + $t.Contains('loop_detection:')
'bash_override       = ' + $t.Contains('tool_freq_overrides')
'subagents_preserved = ' + $t.Contains('subagents:')
'custom_agents       = ' + $t.Contains('custom_agents')
```

Expected: **all four `True`.** A `False` on `subagents_preserved` means the merge
clobbered our local block — restore it from `local-preserve` and redo Step 3.

- [ ] **Step 5: Re-register our prompt-contract gate**

```powershell
$rac = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\run-all-checks.ps1'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($rac))
'prompt_contract_registered = ' + $t.Contains("'scripts/test-prompt-contract.ps1'")
'loop_gate_registered       = ' + $t.Contains("'scripts/test-loop-detection-window.ps1'")
```

Expected: both `True`. If `prompt_contract_registered` is `False`, re-insert it
after the `test-memory-prompt-stability.ps1` registration.

---

### Task 4: Fix Defect 1 — the PS 5.1 stderr abort in the new gate

Without this the gate is **permanently red on every AIPC**, because the AIPCs ship
PowerShell 5.1 and the container's Python writes a deprecation warning to stderr.

**Files:**
- Modify: `pacgate-ai/scripts/test-loop-detection-window.ps1:244`

**Interfaces:**
- Consumes: the gate from Task 2.
- Produces: a gate that reads its own verdict instead of aborting.

- [ ] **Step 1: Confirm the defect is present**

```powershell
$g = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\test-loop-detection-window.ps1'
Select-String -Path $g -Pattern 'docker exec -i deer-flow' | ForEach-Object {
    '{0}: {1}' -f $_.LineNumber, $_.Line.Trim()
}
```

Expected: one line containing `$out = $py | & docker exec -i deer-flow ... 2>&1`.

- [ ] **Step 2: Apply the fix**

```powershell
$g = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\test-loop-detection-window.ps1'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($g))
$old = '    $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1'
if (-not $t.Contains($old)) { throw 'anchor not found - inspect the file before editing' }
$new = @(
'    # Pacgate 2026-10-27: the container python emits a LangChainPendingDeprecation'
'    # Warning on STDERR when it imports deerflow. Under $ErrorActionPreference ='
'    # ''Stop'' (set at the top of this gate) PowerShell 5.1 promotes a native'
'    # command''s stderr to a TERMINATING error, so the gate aborted before it could'
'    # read the verdict it had just produced - permanently red on every AIPC, which'
'    # ships 5.1. Scope the preference down for this one call. This is the same'
'    # defect fixed twice already in test-memory-lane.ps1 (d1ed509, 86a9feb).'
'    $prevEap = $ErrorActionPreference'
'    $ErrorActionPreference = ''Continue'''
'    try {'
'        $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1'
'    }'
'    finally { $ErrorActionPreference = $prevEap }'
) -join "`r`n"
$t = $t.Replace($old, $new)
[System.IO.File]::WriteAllText($g, $t, [System.Text.UTF8Encoding]::new($false))
'patched'
```

Expected: `patched`.

- [ ] **Step 3: Prove the gate now reads its verdict**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-loop-detection-window.ps1 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $prevEap }
$out | Select-Object -Last 20 | ForEach-Object { '  ' + "$_".Trim() }
"exit=$code"
```

Expected: **`exit=0`** with `[PASS]` lines for the window, the config ceiling, and
the live replay. If it still aborts with `NativeCommandError`, the anchor was not
the only such call — grep the file for other `2>&1` native invocations and scope
those too.

- [ ] **Step 4: Red-check the fixed gate**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
$p = '.\deploy\client-bundle\patches\deer-flow-loop-detection.py'
$orig = [System.IO.File]::ReadAllBytes((Resolve-Path $p))
try {
    $s = [System.Text.Encoding]::UTF8.GetString($orig)
    # Revert the windowed counter to the monotonic form the patch replaced.
    $s2 = $s.Replace('self._tool_name_counter: defaultdict[str, Counter[str]] = defaultdict(Counter)',
                     'self._tool_name_counter = None  # MUTANT')
    if ($s2 -eq $s) { throw 'mutation did not apply' }
    [System.IO.File]::WriteAllBytes((Resolve-Path $p), [System.Text.Encoding]::UTF8.GetBytes($s2))
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-loop-detection-window.ps1 *> $null; $c = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prevEap }
    "mutant_exit=$c"
    if ($c -eq 0) { throw 'BLIND GATE: passed with the counter removed' }
}
finally { [System.IO.File]::WriteAllBytes((Resolve-Path $p), $orig) }
$h1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
'restored_ok=' + ($h1 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash)
```

Expected: `mutant_exit=1` (non-zero), then `restored_ok=True`.

- [ ] **Step 5: Commit the adoption and both fixes**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add -A pacgate-ai
git commit -m "feat(sync): adopt upstream loop-guard commits; fix PS 5.1 stderr abort and merge the config ceiling"
```

Expected: one commit; `git show --stat` lists the 16 upstream files plus the deltas.

---

### Task 5: Run the full gate suite

**Files:** none (verification)

**Interfaces:**
- Consumes: the tree from Task 4.
- Produces: evidence the suite is green with the new gate registered.

- [ ] **Step 1: Run all gates**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-all-checks.ps1 2>&1 |
    Select-String -Pattern "ALL \d+ GATES|GATE\(S\) FAILED|^  FAIL" | ForEach-Object { $_.Line }
```

Expected: `ALL 54 GATES PASSED` (53 + `test-loop-detection-window.ps1`).

> If `test-workflow-mutations.ps1` fails once and passes on re-run, that is the
> known flake: it mutates and restores tracked files, so a concurrent reader can
> observe it mid-mutation. Confirm with a second run before investigating.

- [ ] **Step 2: Confirm the egress measurement reports rather than fails**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preflight-docker-egress.ps1 2>&1 |
    Select-Object -Last 12
"exit=$LASTEXITCODE"
```

Expected: it names `registry-1.docker.io` as unreachable (this box's VPN does not
proxy it) and exits non-zero — **but it is registered under `$measurements`, so it
does not fail the suite.** Record the output; do not "fix" it by loosening the gate.

---

### Task 6: Roll out on the BUNDLE stack

**Files:** running containers only

**Interfaces:**
- Consumes: the working tree from Task 4.
- Produces: a live `deer-flow` running the windowed middleware with the raised ceiling.

- [ ] **Step 1: Confirm the bundle owns the containers**

```powershell
docker inspect deer-flow --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
```

Expected: `...\deploy\client-bundle\compose.bundle.yaml`. If it reports
`compose.prod.yaml`, stop and revisit — the rollout below assumes bundle.

- [ ] **Step 2: Back up the extensions config (armed hazard)**

```powershell
$b = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle'
$src = Join-Path $b 'deer-flow-extensions-config.json'
$bak = "$src.bak.pre-loopguard-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
[System.IO.File]::WriteAllBytes($bak, [System.IO.File]::ReadAllBytes($src))
'backup=' + (Split-Path $bak -Leaf)
'mcp_servers=' + (@((Get-Content $src -Raw | ConvertFrom-Json).mcpServers.PSObject.Properties).Count)
```

Expected: `mcp_servers=30`.

- [ ] **Step 3: Recreate deer-flow from the bundle**

A new bind mount requires a recreate; `restart` alone will not pick it up.

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps deer-flow
docker compose -f compose.bundle.yaml ps deer-flow
```

Expected: `running`, healthy within ~60 s. `--no-deps` cannot touch `pacgate-db`
or any named volume.

- [ ] **Step 4: Prove the windowed middleware is live**

```powershell
docker exec deer-flow grep -c "_tool_name_counter" /app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py
docker exec deer-flow grep -n "self._tool_freq: dict" /app/backend/packages/harness/deerflow/agents/middlewares/loop_detection_middleware.py
```

Expected: a **non-zero** count for `_tool_name_counter` (the marker the installer
probe uses), and **no match** for the old monotonic `self._tool_freq: dict` line.
A `0` on the first means the mount did not land.

- [ ] **Step 5: Prove the config ceiling is live**

```powershell
docker exec deer-flow grep -A6 "^loop_detection:" /app/backend/config.yaml
```

Expected: `tool_freq_warn: 50`, `tool_freq_hard_limit: 75`, and the `bash`
override with `warn: 100` / `hard_limit: 150`.

- [ ] **Step 6: Prove the lane is still sanitized (the red line)**

```powershell
docker exec deer-flow sh -c 'echo MATTER_ID=[$PACGATE_MATTER_ID]'
docker exec deer-flow grep -c 'REFUSING to fall back' /app/backend/packages/harness/deerflow/agents/memory/storage.py
```

Expected: a non-empty matter ID and a non-zero count.

- [ ] **Step 7: Re-run the suite against the live stack**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-all-checks.ps1 2>&1 |
    Select-String -Pattern "ALL \d+ GATES|GATE\(S\) FAILED|^  FAIL" | ForEach-Object { $_.Line }
```

Expected: `ALL 54 GATES PASSED`, live-stack gates all `PASS`.

---

### Task 7: Measure the effect

**Files:**
- Create: `runtime/BENCHMARK-2026-10-27-loop-guard.md`

**Interfaces:**
- Consumes: the live stack from Task 6.
- Produces: before/after evidence that a productive run no longer force-stops.

- [ ] **Step 1: Replay the measured productive shape against the live module**

```powershell
$py = @'
import sys
sys.path.insert(0, "/app/backend/packages/harness")
from deerflow.agents.middlewares.loop_detection_middleware import LoopDetectionMiddleware
m = LoopDetectionMiddleware()
print("WINDOW=%d" % m._tool_freq_window)
print("GLOBAL_HARD=%d" % m.tool_freq_hard_limit)
print("BASH_OVERRIDE=%s" % (m._tool_freq_overrides.get("bash"),))
'@
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { $out = $py | & docker exec -i deer-flow /app/backend/.venv/bin/python 2>&1 }
finally { $ErrorActionPreference = $prevEap }
@($out) | Where-Object { "$_" -match 'WINDOW=|GLOBAL_HARD=|BASH_OVERRIDE=' } | ForEach-Object { "$_".Trim() }
```

Expected: `WINDOW` ≥ 150 (auto-sized to the bash override), `GLOBAL_HARD=75`,
`BASH_OVERRIDE=(100, 150)`.

- [ ] **Step 2: Confirm no new force-stop appears after the rollout**

```powershell
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gw = (& docker logs deer-flow 2>&1) -join "`n"
$ErrorActionPreference = $prevEap
'forced_stops_since_restart = ' + ([regex]::Matches($gw, 'forcing stop')).Count
'warnings_since_restart     = ' + ([regex]::Matches($gw, 'Tool frequency warning')).Count
```

Expected: `forced_stops_since_restart = 0`. Warnings may still appear — a warning
is the guard working, not failing.

- [ ] **Step 3: Record the finding**

Write `runtime/BENCHMARK-2026-10-27-loop-guard.md` with: the pre-change evidence
(the `02:15:00` force-stop), the post-change window/ceiling values, the
forced-stop count, and an explicit note that the 92-call productive replay was
**not** re-run end-to-end here (it needs a live document-assembly run), so the
claim rests on the window arithmetic plus the absence of new force-stops.

- [ ] **Step 4: Commit**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add runtime/BENCHMARK-2026-10-27-loop-guard.md
git commit -m "docs(bench): record the loop-guard window and ceiling on this stack"
```

---

### Task 8: Push to the fork

**Files:** none

- [ ] **Step 1: Push the sync branch (never force-push `main`)**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git push fork HEAD:aipc1/v0.2.6-loopguard-sync
```

Expected: branch created on `pacgate-ai/pacgate-ai-pr`. If it fails on transport,
say so explicitly and leave the commits local — **do not retry in a loop**.

- [ ] **Step 2: Record the state**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git log --oneline -4
git status -sb | Select-Object -First 2
```

Expected: the commits visible; tree clean apart from pre-existing untracked notes.

---

## Self-Review

**Spec coverage** — every claim in the request maps to a task:

| Claim / requirement | Covered by |
|---|---|
| "Four commits" | Task 1 Step 1 — **five** verified; `44f7f43` added |
| "the loop-guard fix" | Tasks 2–4 (patch + config + gate fix) |
| "release date ownership, patch audit, egress preflight" | Task 2 (clean files), Task 5 Step 2 (egress is a measurement) |
| "measured 2.1.0 rebase cost + adapter blocker" | Task 2 (docs only, no action) |
| "aligned the sizing figures" | Task 2 (docs only) |
| "loop-detection 33/33" | Task 4 Step 3 — **not reproducible until Defect 1 is fixed** |
| "version-coherence 14/14" | Task 5 Step 1 (suite run) |
| "egress preflight healthy" | Task 5 Step 2 — **not reproducible here**; recorded, not "fixed" |
| "implement locally to patch all the issues" | Tasks 3–4 |
| "validate and audit so AIPC1 works perfectly" | Tasks 4–7 |

**Placeholder scan** — no `TBD`, no "add error handling", every code step has
runnable code and an expected result.

**Type consistency** — `runtime/sync-1027/local-preserve/` produced in Task 1
Step 3, consumed in Task 3 Step 1. `_tool_name_counter` is the marker asserted in
Task 6 Step 4 and is the same marker `44f7f43`'s installer probe uses. The
`loop_detection` keys (`tool_freq_warn`, `tool_freq_hard_limit`,
`tool_freq_overrides.bash.{warn,hard_limit}`) are identical in Task 3 Step 3,
Task 4 Step 3, and Task 6 Step 5.

**Known gaps, stated rather than hidden:**
- The 92-call productive replay is not re-run end-to-end (Task 7 Step 3 records why).
- `registry-1.docker.io` stays unreachable; the egress measurement will keep
  reporting it. That is the environment, not a defect to patch.
