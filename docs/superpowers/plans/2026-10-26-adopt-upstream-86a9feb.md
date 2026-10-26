# Adopt upstream `86a9feb` — memory prompt stability + input bound

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, this session has the live stack) to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land upstream `86a9feb` into the `pacgate-ai/` subtree, preserving all local deltas, then roll it out on `compose.bundle.yaml` (the file this machine's containers were actually created from) — not `install.ps1 -Update`.

**Architecture:** `86a9feb` is one bind-mounted Python patch (`deer-flow-memory-prompt.py`) that (a) reorders `MEMORY_UPDATE_PROMPT` so the append-only conversation block precedes the volatile `{current_memory}` block, making the llama.cpp KV prefix reusable, and (b) caps the conversation block at 16 000 chars / 40 messages. Adoption is an index swap of the `pacgate-ai/` subtree (the two histories are unrelated — never merge), then re-application of the local deltas the swap reverts.

**Tech Stack:** Docker Compose (project `pacgate-ai-bundle`), PowerShell 5.1, deer-flow patches (bind-mounted full-file replacements), llama.cpp prompt caching.

## Global Constraints

- **Python is not on PATH.** Use `C:\Program Files\Python313\python.exe` if a script needs it.
- **`git` is not on PATH.** Prepend `$env:Path += ";C:\Program Files\Git\cmd"`.
- **PS 5.1 native stderr under `$ErrorActionPreference='Stop'` is a TERMINATING error.** Scope the preference to `'Continue'` around any native call whose stderr you read.
- **Never `Get-Content`/`Set-Content` on UTF-8 CJK files.** Use `[System.IO.File]::ReadAllBytes`/`WriteAllBytes`.
- **Quote `"VERSION^{tree}"`** — unquoted, PowerShell parses `^` and fails.
- **Two compose files must stay patch-mount parity** — `test-workflow-compose-wiring.ps1` A5 and `test-memory-prompt-stability.ps1` both assert it.
- **Do NOT run `install.ps1 -Update` for this change.** Not because the prod definition is broken — it is not; a prod-env container was tested and behaves identically — but because `install.ps1` renders `deer-flow-extensions-config.json` and **27 of 30 connectors would be lost** (verified in memory: rendered = `openviking, pacgate, officecli`). Use the bundle recreate in Task 6. See `runtime/VERIFICATION-2026-10-26-upstream-86a9feb.md` §5 (including its correction notice) and §6.
- **Back up `deer-flow-extensions-config.json` before any `install.ps1` run** — `OPENVIKING_ROOT_API_KEY` is set (32 chars), so the render **will** fire against a 3-server template while the live file has 30 connectors.
- **`docker.io` is unreachable** (`code=000`); `ghcr.io` is fine. Image pulls cannot be relied on.
- **Red line:** every AI output is a draft for lawyer review. A silent downgrade of the memory lane to `FileMemoryStorage` puts matter memory outside the sanitization gate — that is the compliance failure both upstream and we are guarding.

---

### Task 1: Stage the commit locally (git cannot fetch)

`git fetch upstream` fails from this box (TLS reset). `86a9feb` is absent from the
object store. Fetch the commit over HTTPS with curl and stage it as a real commit
so the swap can use a tree SHA.

**Files:**
- Modify: `.git` objects (no working-tree file)
- Temp: `$env:TEMP\86a9feb\`

**Interfaces:**
- Produces: a local ref `refs/upstream-curl/86a9feb` whose tree SHA the swap in Task 2 consumes.

- [ ] **Step 1: Download the 8 changed files**

```powershell
$base = "https://raw.githubusercontent.com/JZKK720/pacgate-ai-pr/86a9feb"
$out  = Join-Path $env:TEMP "86a9feb"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$files = @(
  'deploy/client-bundle/compose.bundle.yaml',
  'deploy/client-bundle/compose.prod.yaml',
  'deploy/client-bundle/patches/deer-flow-memory-prompt.py',
  'plans/031-aipc-latency-root-cause-and-fix.md',
  'plans/README.md',
  'scripts/run-all-checks.ps1',
  'scripts/test-memory-lane.ps1',
  'scripts/test-memory-prompt-stability.ps1'
)
foreach ($f in $files) {
    $dest = Join-Path $out $f.Replace('/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    curl.exe -sS --max-time 60 "$base/$f" -o $dest
    "{0,9} bytes  {1}" -f (Get-Item $dest).Length, $f
}
```

Expected: 8 lines, each a nonzero byte count. `deer-flow-memory-prompt.py` ≈ 23646 bytes.

- [ ] **Step 2: Verify every download is the real file, not an HTML error page**

```powershell
Get-ChildItem -Recurse -File $out | ForEach-Object {
    $head = (Get-Content $_.FullName -TotalCount 1)
    if ($head -match '<!DOCTYPE|<html') { "HTML_ERROR  $($_.Name)" } else { "OK  $($_.Name)" }
}
```

Expected: 8 × `OK`. Any `HTML_ERROR` means the raw URL 404'd — stop and re-resolve the path via the API.

- [ ] **Step 3: Confirm the patch is byte-identical to what the API reports**

```powershell
$api = curl.exe -sS --max-time 30 "https://api.github.com/repos/JZKK720/pacgate-ai-pr/contents/deploy/client-bundle/patches/deer-flow-memory-prompt.py?ref=86a9feb" | ConvertFrom-Json
"api_sha=$($api.sha)"
$local = "certutil -hashfile `"$out\deploy\client-bundle\patches\deer-flow-memory-prompt.py`" SHA1"
$hash = (Invoke-Expression $local)[1].Replace(' ','').ToLower()
"local_sha1=$hash"
```

Expected: the API `sha` is a git **blob** SHA (SHA-1 of `blob <len>\0<content>`), so it will not equal the raw file SHA-1. Compare length instead: `$api.size` must equal the file's byte count. Print both and read them.

- [ ] **Step 4: Record the tree SHA to target**

```powershell
$a = curl.exe -sS --max-time 30 "https://api.github.com/repos/JZKK720/pacgate-ai-pr/commits/86a9feb" | ConvertFrom-Json
"commit_tree=$($a.commit.tree.sha)"
"expect    526da22b591157a5ef7cebea933cbc8d280a4862"
```

Expected: `commit_tree` equals `526da22b591157a5ef7cebea933cbc8d280a4862`.

- [ ] **Step 5: Attempt the real fetch once more; if it works, skip to Task 2**

```powershell
git fetch upstream 2>&1 | Select-Object -Last 3
git cat-file -t 86a9feb 2>$null
```

Expected: either `commit` (fetch succeeded — proceed to Task 2 normally), or `fatal: Not a valid object name`. If the latter, build the tree manually as follows (Task 1b).

---

### Task 1b: Materialise the commit from downloaded files (only if fetch failed)

**Files:**
- Create: `refs/upstream-curl/86a9feb` (a synthetic commit)

**Interfaces:**
- Consumes: the 8 files from Task 1 step 1.
- Produces: the same `refs/upstream-curl/86a9feb` tree SHA Task 2 consumes.

- [ ] **Step 1: Overlay the 8 files onto a checkout of the current upstream base**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
$repo = "C:\Users\pacga\github-pr\pacgate-law"
$tree = Join-Path $env:TEMP "up-tree"
Remove-Item -Recurse -Force $tree -ErrorAction SilentlyContinue
git -C $repo worktree add --detach $tree 337fb9d
Copy-Item -Recurse -Force "$env:TEMP\86a9feb\*" $tree
git -C $tree add -A
"built_tree=$((git -C $tree write-tree).Trim())"
```

Expected: `built_tree=526da22b591157a5ef7cebea933cbc8d280a4862` — matching Task 1 step 4. **If it does not match, STOP**: the download is incomplete or a file was missed, and swapping to a wrong tree would silently revert content.

- [ ] **Step 2: Create the synthetic commit and tag it**

```powershell
$c = (git -C $tree commit-tree (git -C $tree write-tree) -p 337fb9d -m "upstream 86a9feb (materialised via HTTPS; git transport blocked on this host)").Trim()
git -C $repo update-ref refs/upstream-curl/86a9feb $c
"ref=$c"
git -C $repo rev-parse "refs/upstream-curl/86a9feb^{tree}"
```

Expected: the second command prints `526da22b591157a5ef7cebea933cbc8d280a4862`.

- [ ] **Step 3: Remove the temp worktree**

```powershell
git -C "C:\Users\pacga\github-pr\pacgate-law" worktree remove --force (Join-Path $env:TEMP "up-tree")
git -C "C:\Users\pacga\github-pr\pacgate-law" worktree prune
```

Expected: no output, and `git worktree list` shows only the main tree.

---

### Task 2: Snapshot the local deltas before the swap

The swap reverts every local delta. Capture them by blob SHA **and** copy the
content, so Task 4 re-applies from evidence rather than memory.

**Files:**
- Create: `runtime/sync-1026/local-preserve/` (working copies)
- Create: `runtime/sync-1026/local-delta-list.txt`

**Interfaces:**
- Produces: `runtime/sync-1026/local-preserve/<path>` for each delta, consumed by Task 4.

- [ ] **Step 1: Enumerate every file that differs from the upstream base**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
$repo = "C:\Users\pacga\github-pr\pacgate-law"
$dst  = Join-Path $repo "runtime\sync-1026\local-preserve"
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# Quoted path form is essential: without core.quotepath=false, CJK paths come back
# octal-escaped and Test-Path fails silently on them.
$tracked = git -C $repo -c core.quotepath=false ls-tree -r --name-only HEAD -- pacgate-ai
$deltas = @()
foreach ($p in $tracked) {
    $sub = $p.Substring('pacgate-ai/'.Length)
    git -C $repo cat-file -e "337fb9d:$sub" 2>$null
    $upExists = ($LASTEXITCODE -eq 0)
    if (-not $upExists) { $deltas += "$p`tLOCAL_ONLY"; continue }
    $l = (git -C $repo rev-parse "HEAD:$p").Trim()
    $u = (git -C $repo rev-parse "337fb9d:$sub").Trim()
    if ($l -ne $u) { $deltas += "$p`tDIFFERS" }
}
$deltas | Set-Content -Path (Join-Path $repo "runtime\sync-1026\local-delta-list.txt") -Encoding UTF8
"delta_count=$($deltas.Count)"
$deltas
```

Expected: the list includes `compose.bundle.yaml`, `compose.prod.yaml`,
`scripts/run-all-checks.ps1`, `scripts/test-memory-lane.ps1`, and the AIPC1 files
named in `AGENTS.md` (agent patch, prompt patch, memory-updater, uploads-middleware), plus local-only docs.

- [ ] **Step 2: Copy each delta out as raw bytes**

```powershell
$repo = "C:\Users\pacga\github-pr\pacgate-law"
$dst  = Join-Path $repo "runtime\sync-1026\local-preserve"
Get-Content (Join-Path $repo "runtime\sync-1026\local-delta-list.txt") | ForEach-Object {
    $p = ($_ -split "`t")[0]
    $fat = Join-Path $repo $p
    if (-not (Test-Path -LiteralPath $fat)) { "MISSING $p"; return }
    $target = Join-Path $dst ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    # Byte-copy: Get-Content/Set-Content would re-encode UTF-8 CJK as GBK.
    [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($fat))
    "copied $p"
}
```

Expected: one `copied …` line per delta, zero `MISSING`.

- [ ] **Step 3: Verify the copies are byte-identical**

```powershell
$repo = "C:\Users\pacga\github-pr\pacgate-law"
$dst  = Join-Path $repo "runtime\sync-1026\local-preserve"
$bad = 0
Get-Content (Join-Path $repo "runtime\sync-1026\local-delta-list.txt") | ForEach-Object {
    $p = ($_ -split "`t")[0]
    $src = Join-Path $repo $p
    $cpy = Join-Path $dst ($p -replace '/', '\')
    $a = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash
    $b = (Get-FileHash -Algorithm SHA256 -LiteralPath $cpy).Hash
    if ($a -ne $b) { "MISMATCH $p"; $script:bad++ }
}
"byte_mismatches=$bad"
```

Expected: `byte_mismatches=0`. Any mismatch means the copy is unusable — do not swap.

- [ ] **Step 4: Commit the snapshot**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add runtime/sync-1026
git commit -m "chore(sync): snapshot local deltas before adopting upstream 86a9feb"
```

Expected: one commit, reporting the delta count from step 1.

---

### Task 3: Swap the `pacgate-ai/` subtree

**Files:**
- Modify: 1 899 tracked paths under `pacgate-ai/`

**Interfaces:**
- Consumes: the tree SHA from Task 1 (or 1b).
- Produces: `pacgate-ai/` byte-identical to `86a9feb`'s tree.

- [ ] **Step 1: Swap by index**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
$rev = if (git rev-parse --verify refs/upstream-curl/86a9feb 2>$null) { "refs/upstream-curl/86a9feb" } else { "86a9feb" }
"using=$rev"
git rm -r --cached pacgate-ai --quiet
# The ^ must stay INSIDE the quotes; unquoted, PowerShell parses it and dies on 'e'.
git read-tree --prefix=pacgate-ai/ "$rev^{tree}"
git checkout -- pacgate-ai
"worktree_done"
```

Expected: `worktree_done`, no fatal errors.

- [ ] **Step 2: Prove byte-identity by tree SHA (not per-file — CJK paths break per-file loops)**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
$root = (git write-tree).Trim()
"subtree_sha=$((git rev-parse "$($root):pacgate-ai").Trim())"
"upstream_sha=526da22b591157a5ef7cebea933cbc8d280a4862"
```

Expected: both values identical. **If not, STOP** — do not proceed to Task 4 on a wrong tree.

- [ ] **Step 3: Confirm the new files are present and the memory patch is real**

```powershell
$b = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-memory-prompt.py"
"patch_bytes=$((Get-Item $b).Length)"
Select-String -Path $b -Pattern "MEMORY_CONVERSATION_MAX_CHARS = 16000|MEMORY_CONVERSATION_MAX_MESSAGES = 40" | ForEach-Object { $_.Line.Trim() }
Test-Path "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\test-memory-prompt-stability.ps1"
```

Expected: ≈23646 bytes, both constants printed, and `True`.

---

### Task 4: Re-apply the local deltas the swap reverted

**Files:**
- Modify: the deltas listed in `runtime/sync-1026/local-delta-list.txt`
- Modify: `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` (3 mounts)
- Modify: `pacgate-ai/deploy/client-bundle/compose.prod.yaml` (3 mounts)
- Modify: `pacgate-ai/scripts/run-all-checks.ps1` (1 gate)

**Interfaces:**
- Consumes: `runtime/sync-1026/local-preserve/` from Task 2.
- Produces: a tree whose only difference from `86a9feb` is the local delta set.

- [ ] **Step 1: Restore every preserved file as raw bytes**

```powershell
$repo = "C:\Users\pacga\github-pr\pacgate-law"
$dst  = Join-Path $repo "runtime\sync-1026\local-preserve"
Get-ChildItem -Recurse -File $dst | ForEach-Object {
    $rel = $_.FullName.Substring($dst.Length + 1) -replace '\\', '/'
    $target = Join-Path $repo ($rel -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($_.FullName))
    "restored $rel"
}
```

Expected: one `restored …` per preserved file.

- [ ] **Step 2: DO NOT restore `scripts/test-memory-lane.ps1` — let upstream's stand**

Our `d1ed509` version fixed the same two bugs by different means. Upstream's is
strictly better (no second shell; stderr preserved). Verify upstream's version is
in place and that it is the argv form:

```powershell
$p = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\test-memory-lane.ps1"
Select-String -Path $p -Pattern "docker exec deer-flow grep -c 'REFUSING|ErrorActionPreference = 'Continue'" | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

Expected: both lines present. Then delete the preserved copy so no one
re-introduces ours:

```powershell
Remove-Item "C:\Users\pacga\github-pr\pacgate-law\runtime\sync-1026\local-preserve\pacgate-ai\scripts\test-memory-lane.ps1" -Force
```

- [ ] **Step 3: Re-add the local-only mounts and gate registration**

The upstream compose files already carry the `deer-flow-memory-prompt.py` mount.
Our delta adds three mounts the swap removed. Confirm they are back:

```powershell
$base = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle"
foreach ($f in @('compose.bundle.yaml','compose.prod.yaml')) {
    $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $base $f)))
    foreach ($needle in @('deer-flow-memory-updater.py','deer-flow-uploads-middleware.py','deer-flow/skills/public','deer-flow-memory-prompt.py','deer-flow-memory-storage.py')) {
        "{0,-24} {1,-34} {2}" -f $f, $needle, ($t -match [regex]::Escape($needle))
    }
}
```

Expected: **all five `True` in both files.** If any `False`, re-insert that mount
line next to the `deer-flow-memory-storage.py` mount and re-run.

- [ ] **Step 4: Confirm the prompt-contract gate registration survived**

```powershell
$p = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\scripts\run-all-checks.ps1"
Select-String -Path $p -Pattern "test-prompt-contract\.ps1|test-memory-prompt-stability\.ps1" | ForEach-Object { $_.Line.Trim() }
```

Expected: **both** lines present — ours (`test-prompt-contract.ps1`) and
upstream's new one. If only the new one is there, re-add ours above it.

- [ ] **Step 5: Commit the re-applied deltas**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add -A pacgate-ai
git commit -m "feat(sync): adopt upstream 86a9feb - stable memory prompt prefix and bounded input"
```

Expected: one commit; `git show --stat` lists the delta files plus the 8 upstream ones.

---

### Task 5: Verify gate suite and the new gate's red-check

**Files:**
- Test: `pacgate-ai/scripts/run-all-checks.ps1`

**Interfaces:**
- Consumes: the tree from Task 4.
- Produces: evidence the suite is green and the new gate can actually fail.

- [ ] **Step 1: Run the whole suite**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-all-checks.ps1 2>&1 | Select-Object -Last 12
```

Expected: `ALL 53 GATES PASSED` (52 + the new one). Any FAIL: read it before
touching anything — a red gate after a swap is usually a lost local delta, not a
real regression.

- [ ] **Step 2: Prove the new gate is not blind (mutation test)**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
$p = ".\deploy\client-bundle\patches\deer-flow-memory-prompt.py"
$orig = [System.IO.File]::ReadAllBytes($p)
try {
    $s = [System.Text.Encoding]::UTF8.GetString($orig)
    # Swap the two blocks back so the memory block precedes the conversation.
    $s2 = $s -replace '(?s)<conversation>\{conversation\}</conversation>(.*?)<current_memory>\{current_memory\}</current_memory>', '<current_memory>{current_memory}</current_memory>$1<conversation>{conversation}</conversation>'
    if ($s2 -eq $s) { throw "mutation did not apply - regex drifted" }
    [System.IO.File]::WriteAllBytes($p, [System.Text.Encoding]::UTF8.GetBytes($s2))
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-memory-prompt-stability.ps1 2>&1 | Select-Object -Last 6
    "MUTANT_EXIT=$LASTEXITCODE"
}
finally {
    [System.IO.File]::WriteAllBytes($p, $orig)
}
```

Expected: `MUTANT_EXIT=1` with a FAIL naming the prefix order. Then confirm
restoration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-memory-prompt-stability.ps1 2>&1 | Select-Object -Last 4
"RESTORED_EXIT=$LASTEXITCODE"
git -C C:\Users\pacga\github-pr\pacgate-law status --short -- pacgate-ai/deploy/client-bundle/patches/deer-flow-memory-prompt.py
```

Expected: `RESTORED_EXIT=0` and **empty** git status (byte-identical restore).

- [ ] **Step 3: Commit nothing here (verification only)**

No files should have changed. If `git status` is dirty, the restore in step 2
failed — fix it before continuing.

---

### Task 6: Roll out on the BUNDLE stack (minimal blast radius, not because prod is broken)

> **Why not `install.ps1 -Update`:** not a correctness problem. A prod-env
> container was run and behaves identically to the live one on every path tested
> (§5 of the verification doc). The reasons to prefer bundle are (a) it touches
> only the two services this change needs, and (b) it avoids `install.ps1`'s
> extensions render, which **would drop 27 of 30 MCP connectors** (§6). If you
> later choose `-Update` deliberately, take the step-2 backup first.

**Files:**
- Modify: running containers only

**Interfaces:**
- Consumes: the working tree from Task 4.
- Produces: a live `deer-flow` whose mounted `prompt.py` carries the cap and the new order.

- [ ] **Step 1: Re-confirm what owns the live containers before touching them**

```powershell
docker inspect deer-flow --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
docker inspect deer-flow --format '{{index .Config.Labels "com.docker.compose.project"}}'
```

Expected: `...\deploy\client-bundle\compose.bundle.yaml` and `pacgate-ai-bundle`.
**If this ever reports `compose.prod.yaml`, stop and revisit §5 of the
verification doc** — the rollout command below assumes bundle.

- [ ] **Step 2: Back up the extensions config (armed hazard)**

```powershell
$b = "C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle"
$src = Join-Path $b "deer-flow-extensions-config.json"
$bak = "$src.bak.pre-86a9feb-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
[System.IO.File]::WriteAllBytes($bak, [System.IO.File]::ReadAllBytes($src))
"backup=$bak"
$j = Get-Content $src -Raw | ConvertFrom-Json
"mcp_servers=$(@($j.mcpServers.PSObject.Properties).Count)"
```

Expected: `mcp_servers=30`. This file is **not** touched by the commands in
step 3, but it must exist before anyone is tempted to run `install.ps1`.

- [ ] **Step 3: Recreate the two memory-lane services from the bundle**

A new bind mount requires a recreate; `restart` alone will not pick it up.

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps deer-flow
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps deer-flow-frontend
docker compose -f compose.bundle.yaml ps deer-flow deer-flow-frontend
```

Expected: both `running`, `deer-flow` healthy after ~60 s. `--no-deps` is
deliberate: it cannot touch `pacgate-db` or any named volume.

**If `deer-flow-frontend` comes up with a changed definition**, check step 4
before assuming success — the bundle block keeps both `NEXT_PUBLIC_*` vars, so
recreating from **bundle** is safe; recreating from **prod** is not.

- [ ] **Step 4: Prove the frontend still serves**

Do **not** assert on `NEXT_PUBLIC_*` presence. Those values are inert on this
image (verified: `localhost:8089` appears in 0 client and 0 server chunks; the
`/api/*` rewrites are baked into `.next/routes-manifest.json` at build time), so
their absence is not a defect and their presence is not proof of health.

```powershell
$paths = @('/','/api/memory','/api/agents','/api/langgraph')
foreach ($p in $paths) {
    $r = docker exec deer-flow-frontend sh -c "node -e `"fetch('http://127.0.0.1:3000$p').then(x=>console.log(x.status,x.headers.get('server')||'-')).catch(e=>console.log('ERR'))`"" 2>&1
    "{0,-16} {1}" -f $p, "$r".Trim()
}
```

Expected, matching the pre-change baseline exactly:

```
/                200 -
/api/memory      401 uvicorn
/api/agents      401 uvicorn
/api/langgraph   401 uvicorn
```

`401 uvicorn` is **correct** — it proves `/api/*` is reaching the gateway (which
requires auth) via the baked rewrite. `ERR` or a 5xx on any line is a real
regression: investigate before continuing.

- [ ] **Step 5: Prove the patch is mounted and the new prompt is live**

```powershell
docker inspect deer-flow --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' | Select-String "memory"
docker exec deer-flow sh -c 'F=/app/backend/packages/harness/deerflow/agents/memory/prompt.py; echo "cap=$(grep -c "MEMORY_CONVERSATION_MAX_CHARS = 16000" $F)"; echo "msgs=$(grep -c "MEMORY_CONVERSATION_MAX_MESSAGES = 40" $F)"; grep -n "{conversation}\|{current_memory}" $F | head -4'
```

Expected: `cap=1`, `msgs=1`, and `{conversation}` on a **lower line number** than
`{current_memory}`. This is the exact check upstream reported as
`cap: 16000 | conversation first: True`.

- [ ] **Step 6: Prove the lane is still the sanitized one (the red line)**

```powershell
docker exec deer-flow sh -c 'echo PACGATE_MATTER_ID=$PACGATE_MATTER_ID'
docker exec deer-flow grep -c 'REFUSING to fall back' /app/backend/packages/harness/deerflow/agents/memory/storage.py
```

Expected: a non-empty `PACGATE_MATTER_ID` and a nonzero count. A blank matter ID
means the adapter raises and memory falls back to unsanitized disk storage.

- [ ] **Step 7: Run the live-stack gates**

```powershell
cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-all-checks.ps1 2>&1 | Select-Object -Last 22
```

Expected: `ALL 53 GATES PASSED`, live-stack gates all `PASS`, and update coverage
still `13 of 13`. `test-model-picker-e2e.ps1` may `SKIP` (exit 2, no credential) —
that is pre-existing and not a regression.

---

### Task 7: Measure the effect (the whole point of the commit)

**Files:**
- Create: `runtime/BENCHMARK-2026-10-26-memory-prompt-86a9feb.md`

**Interfaces:**
- Consumes: the live stack from Task 6.
- Produces: before/after evidence that the prefix is reusable.

- [ ] **Step 1: Confirm the mechanism holds in the live process**

```powershell
docker exec deer-flow /app/backend/.venv/bin/python -c @"
import sys; sys.path.insert(0,'/app/backend/packages/harness')
from deerflow.agents.memory import prompt as P
t = P.MEMORY_UPDATE_PROMPT
i_conv = t.find('{conversation}'); i_mem = t.find('{current_memory}')
print('order_conversation_first', i_conv > 0 and i_conv < i_mem)
print('cap_chars', P.MEMORY_CONVERSATION_MAX_CHARS)
print('cap_msgs', P.MEMORY_CONVERSATION_MAX_MESSAGES)
class M:
    def __init__(s,ty,c): s.type=ty; s.content=c
msgs=[M('human','u'*900),M('ai','a'*900)]*80
out=P.format_conversation_for_update(msgs)
print('bounded', len(out) <= P.MEMORY_CONVERSATION_MAX_CHARS + 8, 'len', len(out))
"@
```

Expected: `order_conversation_first True`, `cap_chars 16000`, `cap_msgs 40`,
`bounded True`.

- [ ] **Step 2: Compare the rendered prefix across two memory states**

This is the actual claim: the prefix must be identical when only
`current_memory` changes.

```powershell
docker exec deer-flow /app/backend/.venv/bin/python -c @"
import sys, json; sys.path.insert(0,'/app/backend/packages/harness')
from deerflow.agents.memory import prompt as P
def render(mem):
    return P.MEMORY_UPDATE_PROMPT.format(current_memory=json.dumps(mem,indent=2), conversation='User: hi\n\nAssistant: ok', correction_hint='')
a = render({'facts':[{'id':'1'}]})
b = render({'facts':[{'id':'1'},{'id':'2'}]})
def lcp(x,y):
    n=0
    for i in range(min(len(x),len(y))):
        if x[i]!=y[i]: break
        n+=1
    return n
print('prefix_len_shared', lcp(a,b))
print('a_len', len(a), 'b_len', len(b))
print('prefix_is_most_of_prompt', lcp(a,b) > 0.8*min(len(a),len(b)))
"@
```

Expected: `prefix_is_most_of_prompt True` — the conversation block plus the
static instructions are shared, and only the trailing memory block differs. That
is what lets llama.cpp reuse the KV prefix.

- [ ] **Step 3: Record the finding**

Write `runtime/BENCHMARK-2026-10-26-memory-prompt-86a9feb.md` with: the two
outputs above, the image tag (`0.2.6`), the fact that **no image was rebuilt**,
and the note that wall-clock prefill numbers were not re-measured here (upstream's
68.7 s → 1.3 s was on the HX370 box; this box's Ollama log rotates fast enough
that a stale window cannot be attributed).

- [ ] **Step 4: Commit**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git add runtime/BENCHMARK-2026-10-26-memory-prompt-86a9feb.md
git commit -m "docs(bench): record the 86a9feb memory-prompt prefix evidence on this stack"
```

---

### Task 8: Push to the fork

**Files:** none

**Interfaces:**
- Consumes: the commits from Tasks 2, 4, 7.
- Produces: a pushed branch the developer can pull without VPN.

- [ ] **Step 1: Push the sync branch (never force-push `main`)**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git push fork HEAD:aipc1/v0.2.6-86a9feb-sync
```

Expected: branch created on `pacgate-ai/pacgate-ai-pr`. If the push fails on
transport (the same TLS problem the fetch hit), say so explicitly and leave the
commits local — **do not** retry in a loop.

- [ ] **Step 2: Record the state**

```powershell
$env:Path += ";C:\Program Files\Git\cmd"
cd C:\Users\pacga\github-pr\pacgate-law
git log --oneline -4
git status -sb | Select-Object -First 2
```

Expected: the three commits visible; working tree clean apart from pre-existing
untracked `runtime/` notes.

---

## Self-Review

**Spec coverage** — every upstream claim in the prompt maps to a task:

| Claim | Covered by |
|---|---|
| "Committed 86a9feb / pushed 337fb9d..86a9feb" | Task 1 (staging, since git transport is blocked here) |
| "`-Update` runs `up -d` then `restart deer-flow`" | Verified in `runtime/VERIFICATION…` §1; **deliberately not followed** — Task 6 uses bundle |
| "13 of 13 update coverage" | Task 6 step 7 re-asserts it |
| "52 of 52 gates pass" | Task 5 step 1 expects 53 (52 + the new gate) |
| "Deliberately did not tag or rebuild" | Task 6 — no pull, no tag; local `0.2.6` images reused |
| "Live container confirmed patched" | Task 6 step 5 |
| "Rollout: `install.ps1 -Update`" | **Substituted with the bundle recreate** in Task 6 — on blast-radius and extensions-render grounds, *not* because the prod definition is broken (§5 correction notice) |

**Correction carried into this plan:** an earlier draft of the verification doc
claimed `-Update` would change the frontend's backend wiring. That was wrong —
tested and retracted in §5. The plan's Task 6 step 4 no longer asserts on
`NEXT_PUBLIC_*` presence, because those values are inert on this image.

**Placeholder scan** — no `TBD`, no "add error handling", every code step has
runnable code and an expected result.

**Type consistency** — `refs/upstream-curl/86a9feb` is created in Task 1b step 2,
consumed in Task 3 step 1. `runtime/sync-1026/local-preserve/` is produced in
Task 2 step 2 and consumed in Task 4 steps 1–2. `MEMORY_CONVERSATION_MAX_CHARS` /
`_MAX_MESSAGES` are asserted identically in Tasks 3, 5, 6 and 7.

**Known gap, stated rather than hidden:** wall-clock prefill improvement is not
re-measured on this box (Task 7 step 3 records why). The mechanism — shared
prefix — *is* measured, which is the property the commit claims to fix.
