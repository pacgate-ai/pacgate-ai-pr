# Relocation Plan: `C:\pacgate-ai-pr` → `pacgate-law`

> **For the executing agent:** this plan is written to be followed step by step.
> Steps are checkboxes. **Do not skip the preflight.** Every destructive step has a
> rollback. If a verification fails, STOP and roll back rather than improvising.
>
> **Sub-skills:** follow `safety-guard` for the destructive steps.

**Goal:** Make `C:\Users\pacga\github-pr\pacgate-law` the single local repository
hosting all services, codebases and runtimes, so `C:\pacgate-ai-pr` can be retired.

> ### ⚠️ CORRECTION (2026-09-16, after Phase 1) — the original premise was WRONG
>
> This plan originally asserted: *"the running stack **bind-mounts absolute paths
> under `C:\pacgate-ai-pr`**. Moving that directory *will* break the stack."*
> **That is false.** Verified two ways:
>
> 1. Reading `compose.bundle.yaml` — every mount is **relative**:
>    `./data:/data`, `./patches/deer-flow-artifacts.py:/app/...`,
>    `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro`.
> 2. The live container labels show
>    `com.docker.compose.project.working_dir = C:\pacgate-ai-pr\deploy\client-bundle`.
>
> Compose resolves relative mounts against the **compose file's own directory**,
> so they follow the move automatically. There is **no absolute path to rewrite**
> in any compose file, `.env`, or runtime config.
>
> **Consequences:**
> - Task 2 shrank from "rewrite 23 hardcoded paths" to **2 stale comments** in
>   `build-images.ps1` / `build-frontend.ps1` (their code already used
>   `$PSScriptRoot`) plus 6 handbooks made layout-agnostic. ✅ done, commit `66051ec`.
> - The cutover is **much safer than feared**: the stack must still be restarted
>   (Docker resolves mounts at container start), but the risk of a silently broken
>   mount is low, and the volume/project-name trap is the only real hazard.
> - The maintenance window is still required, but it is a *restart*, not a
>   *reconfiguration*.

---

## Chosen placement: content lands under `pacgate-ai/`

Per the request, the platform consolidates under `pacgate-law\pacgate-ai\`.

**Verified during planning:** the naive copy would produce
`pacgate-ai\pacgate-ai\Cargo.toml` (a double nest), but **promoting the Rust
workspace's contents up one level is a clean move — zero name collisions** between
the Rust workspace (10 entries) and the platform root (38 entries).

Resulting tree:

```
pacgate-law\
├── pacgate-ai\                    <- user's chosen home for the platform
│   ├── Cargo.toml  crates\  wasm-crates\  migrations\  workflows\  Dockerfile
│   ├── deploy\                    (compose, client-bundle, qm-pacgate, handbooks)
│   ├── pacgate-adapters\  scope-assets\  patches\  plans\
│   ├── nginx\  auth-gate\  scripts\  docs\
│   └── pacgate-ai-assets\         (the one surviving asset copy)
├── deer-flow\                     (submodule, unchanged)
├── runtime\                       (inventory + tooling)
├── docs\                          (specs, plans)
└── AGENTS.md  README.md
```

**History implication (resolved):** nesting shifts every tracked path, which would
normally require a `filter-repo` rewrite. But the recommended import is a **squash**
anyway — because the source history contains the four publicly-exposed credential
files, carrying it would re-import them. Since no history is carried, the nesting
costs nothing. There is exactly **one** path substitution to make operationally:

```
C:\pacgate-ai-pr\deploy\client-bundle\...   ->   ...\pacgate-law\pacgate-ai\deploy\client-bundle\...
```

> **Alternative (root placement)** preserves the path layout for a hypothetical
> history-preserving import. It is documented at the end for completeness, but is
> **not** the chosen path and is not required.

---

## Global Constraints

- **Never delete `C:\pacgate-ai-pr` before verification passes.** Archive it.
- **Copy, do not move, during the migration.** The source is the rollback.
- **`git checkout-index` only** for the git-tracked content — never `cp -r` the whole
  tree (it would drag in 6.4 GB of build output and client data), and never
  `git archive` + Windows `tar` (it silently drops every CJK-named file).
- **The four credential files must not enter the new repo** (see §Preflight P6).
- **Do not rename `deploy/client-bundle/`** — its Compose project name derives from
  the directory name, so a rename silently creates a new empty database volume.
- PowerShell 5.1 only; use `.ps1` files with a **UTF-8 BOM** if they contain non-ASCII.
- **Never put a CJK literal in a BOM-less `.ps1`** — PowerShell reads the file with
  the system ANSI codepage (GBK), corrupting the literal before the script runs.
  Build such strings from code points instead.
- All commands run on Windows with the repo at `C:\Users\pacga\github-pr\pacgate-law`.

### Rehearsal status — ✅ PASSED (36 PASS / 0 FAIL)

The entire Task 1 mechanism was rehearsed non-destructively in `C:\temp\rehearsal`
by `runtime/relocate/rehearse.ps1` (source untouched, rehearsal area cleaned up).
Record: `runtime/relocate/REHEARSAL-RESULT.txt`. Key evidence:

| Check | Result |
|---|---|
| Extraction method | `checkout-index`, 515 / 515 |
| Index-vs-disk diff (Ordinal) | 0 missing, 0 extra |
| Specific CJK filenames intact | 2 / 2 probed paths present, not mojibake |
| Mojibake filenames | 0 |
| Credential carriers found | 4 → all removed in the mandatory step |
| Flatten `pacgate-ai\pacgate-ai\` | clean, `Cargo.toml` at root, 0 collisions |
| Hardcoded path references found | 23 (Task 2 scope confirmed) |

Three earlier rehearsal failures were diagnosed to root cause: two were **real**
(`tar.exe` CJK loss → switched to `checkout-index`; credential file inside tracked
content → mandatory removal step), one was **a defect in the probe itself** (CJK
literal mangled by GBK read → rebuilt from code points). All three are now fixed
and the failure modes are documented in the trap table.

---

## Preflight

- [ ] **P1 — Confirm the stack's current state**
  ```powershell
  docker ps --format "{{.Names}}`t{{.Status}}"
  ```
  Expect 25 running. Record the output to `runtime/relocate/preflight-containers.txt`.

- [ ] **P2 — Free space**
  ```powershell
  Get-PSDrive C | Select-Object @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}}
  ```
  **Requires ≥ 8 GB free** (source is 6.6 GB; we copy before deleting). Last measured: 395 GB free. ✅

- [ ] **P3 — Record the rollback anchor** (the single most important step)
  ```powershell
  git -C C:\pacgate-ai-pr rev-parse HEAD
  git -C C:\pacgate-ai-pr branch --show-current
  git -C C:\pacgate-ai-pr status --porcelain
  ```
  Write the output to `runtime/relocate/ROLLBACK-ANCHOR.txt`. Recorded state:
  HEAD `151a383`, branch `feat/agent-capability-enablement`, **13 untracked files,
  zero modified tracked files**.

  > ⚠️ **Gate: there must be ZERO lines starting with ` M` or `M `.** Task 1.1 uses
  > `git checkout-index`, which exports the **committed** state only — any modified
  > tracked file would be silently left behind, and the exported copy would differ
  > from what the running stack actually uses. If modified tracked files appear,
  > **commit or stash them first**, then re-run this step. (Untracked scratch files
  > such as `probe_*.py` / `tmp-*.ps1` are irrelevant — they are not exported and
  > are not runtime dependencies.)

- [ ] **P4 — Back up both `.git` directories**
  ```powershell
  # 67 MB + ~0 MB — cheap insurance
  Copy-Item C:\pacgate-ai-pr\.git C:\backup-pacgate-ai-pr-git -Recurse -Force
  Copy-Item C:\Users\pacga\github-pr\pacgate-law\.git C:\backup-pacgate-law-git -Recurse -Force
  ```
  Verify both exist and are non-empty.

- [ ] **P5 — Resolve the `pacgate-ai/` collision**
  The target `pacgate-law\pacgate-ai` is currently a **submodule gitlink**
  (`160000 f712ec2`), and its `.gitmodules` URL is `JZKK720/pacgate-ai` (the assets
  repo, *not* the Rust workspace). Decide and record:
  - the **Rust workspace** takes `pacgate-ai/` (it is the product)
  - the **old submodule content** moves to `pacgate-ai-assets/`
  - remove the gitlink: `git -C <repo> rm --cached pacgate-ai`, and update or delete
    `.gitmodules`

  ⚠️ The submodule's `assets/` (60 files, 43.4 MB) duplicates the source's vendored
  `pacgate-ai\pacgate-ai-assets\pacgate-ai` (59 files, 43.4 MB). **Keep one.**
  Per the delivery plan, keep the **submodule** copy (its `.gitignore` correctly
  ignores the credential files); delete the vendored duplicate.

- [ ] **P6 — Ensure the four credential files cannot enter the new repo**
  Run the byte-level checker (string comparison gives false negatives on CJK paths):
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\AUTHORITATIVE-credential-check.ps1
  ```
  Confirm the 4 files are listed. They must not be copied into the new repo.

- [ ] **Preflight done? Capture the runtime inventory**
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\capture-runtime.ps1
  ```
  Copy `runtime-inventory.json` to `runtime/relocate/inventory-BEFORE.json`.

- [ ] **P8 — Verify the .gitignore rules for the nested layout** (already added, but confirm):
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\relocate\verify-gitignore-rules.ps1
  ```
  Expect **6 PASS, 0 FAIL**. See `runtime/relocate/gitignore-verification.txt`.

  ⚠️ **Important gotcha discovered during planning:** running `git check-ignore` on a
  path *inside the still-present submodule* fails with
  `fatal: Pathspec ... is in submodule`. That looks like "the rule is missing" but
  is really just the submodule boundary — git never evaluates the rules. Do not
  "fix" the patterns in response to that error; remove the gitlink first (Task 1.0).

---

## Task 1 — Stage the content at the new location (source untouched)

> ### ✅ STATUS: COMPLETE (2026-09-16)
> Commits `c4ba8b0` (baseline) → `9d8fc3b` (import) → `8bf3fee` (tooling).
> 438 files under `pacgate-ai/`, 13 CJK names intact, 0 credential carriers,
> 0 bulk paths. Source untouched at `151a383`; 25 containers still up.
>
> **Two deviations from the steps below, both forced by reality:**
> 1. **Step 4's `Move-Item` failed** with *"cannot delete pacgate-ai\.git —
>    insufficient access"*. `Move-Item` is **not atomic**: it moved the loose
>    files and `.git`, then failed on the `.git` directory removal, leaving the
>    subdirectories behind. Nothing was lost (262 files recovered = exact
>    baseline). Fixed with `robocopy /MOVE` — see `runtime/relocate/RECOVERY.txt`.
>    **Lesson: never use `Move-Item` on a directory containing a `.git`.**
> 2. **`pacgate-ai-assets/` is ignored, not committed.** It is itself a git repo,
>    so `git add` would record a *gitlink* (a phantom submodule). Fully committing
>    it would mean deleting its `.git` and severing its link to
>    `JZKK720/pacgate-ai`. That is destructive and was not requested, so it is
>    deferred — see the `.gitignore` comment and `ASSETS-STRUCTURE.txt`.
>
> **Also discovered:** `deer-flow/` is an embedded repo; `git add -A` would have
> recorded it as a gitlink too. Now ignored (it ships via its own
> `pacgate-layer` branch). See `STAGE-PREVIEW.txt`.

**Deliverable:** the same content present in both places; nothing stopped yet.

- [ ] **1.0 Create the destination and clear the submodule gitlink** (Preflight P5):
  ```powershell
  cd C:\Users\pacga\github-pr\pacgate-law
  git rm --cached pacgate-ai          # remove the gitlink; files stay on disk
  ```
  Then move the old submodule content aside so it cannot collide — it becomes the
  asset copy we keep:
  ```powershell
  Move-Item pacgate-ai pacgate-ai-assets
  ```
  Remove the now-wrong `.gitmodules` entry (it pointed at the assets repo, not the
  Rust workspace). Keep `.gitmodules` only if `deer-flow` remains a submodule.

- [ ] **1.1 Export only the git-tracked platform content** (23.8 MB, 515 files).

  ⚠⚠️ **Do NOT use `git archive` + `tar`.** A decisive test proved that Windows
  `tar.exe` **silently drops all 59 non-ASCII-named files** (478/515 extracted)
  and re-materialises 22 of them as **mojibake duplicates**, reporting only
  `Invalid empty pathname` warnings — exit code 0. Use `checkout-index` instead —
  it is built into git and extracted **515/515**, verified 0 missing / 0 extra:

  ```powershell
  $stage = 'C:\temp\pacgate-stage'
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  git -C C:\pacgate-ai-pr checkout-index -a -f --prefix=($stage.TrimEnd('\') + '\')
  (Get-ChildItem $stage -Recurse -File -Force).Count    # MUST be 515
  ```

  Method comparison (measured, see `runtime/relocate/BLOCKER-DIAGNOSIS.txt`):

  | Method | Extracted | Verdict |
  |---|---|---|
  | `git checkout-index` | **515 / 515** | ✅ **use this** |
  | Python `tarfile` | 515 / 515 | ✅ works, needs Python |
  | `tar.exe` (bsdtar) | 478 / 515 | ❌ drops CJK names |
  | `robocopy` file-by-file | 456 / 515 | ❌ drops CJK names |

- [ ] **1.2 Verify the extraction is complete** (this is the guard against the
  silent-drop failure):
  ```powershell
  $stage = 'C:\temp\pacgate-stage'
  $got = (Get-ChildItem $stage -Recurse -File -Force).Count
  $want = (git -C C:\pacgate-ai-pr ls-files | Measure-Object).Count
  "got=$got want=$want"     # MUST match, both 515
  ```
- [ ] **1.3 Flatten the Rust workspace** — avoid `pacgate-ai\pacgate-ai\`:
  ```powershell
  # verified during planning: ZERO name collisions between these two levels
  $stage = 'C:\temp\pacgate-stage'
  $inner = Join-Path $stage 'pacgate-ai'
  Get-ChildItem -LiteralPath $inner -Force | ForEach-Object {
      Move-Item -LiteralPath $_.FullName -Destination (Join-Path $stage $_.Name) -Force
  }
  Remove-Item -LiteralPath $inner -Force        # now empty
  # verify: Cargo.toml must sit at the STAGE root, not nested
  Test-Path (Join-Path $stage 'Cargo.toml')     # expect True
  ```

- [ ] **1.4 ⚠️ REMOVE the credential file from the stage** — mandatory.
  The rehearsal proved the tracked content **does** carry a credential file
  (`pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md`).
  It must be deleted from the stage before anything is staged in git:
  ```powershell
  $stage = 'C:\temp\pacgate-stage'
  $bad  = Join-Path $stage 'pacgate-ai-assets'
  if (Test-Path -LiteralPath $bad) {
      Remove-Item -LiteralPath $bad -Recurse -Force
      "removed vendored assets tree (59 files, includes OPERATOR.md)"
  }
  # belt-and-braces: sweep for any surviving credential file by NAME
  Get-ChildItem $stage -Recurse -File -Force |
      Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -like '*remote-handbook*' } |
      ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force; "removed $($_.FullName)" }
  # verify none remain
  (Get-ChildItem $stage -Recurse -File -Force | Where-Object { $_.Name -eq 'OPERATOR.md' }).Count  # MUST be 0
  ```

  > The vendored tree is also the **duplicate** of the submodule's assets — the
  > delivery plan already decided to keep the submodule copy. Removing it fixes
  > both problems at once.
- [ ] **1.5 Move the staged content into place**
  ```powershell
  New-Item -ItemType Directory -Path 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai' -Force | Out-Null
  robocopy C:\temp\pacgate-stage 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai' /E /COPY:DAT /R:1 /W:1
  ```
- [ ] **1.6 Copy the untracked runtime state the stack needs** — *the part a naive
  migration forgets*. These are **not** in git:
  ```powershell
  $s = 'C:\pacgate-ai-pr'
  $d = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai'
  robocopy "$s\deploy\client-bundle\data"       "$d\deploy\client-bundle\data"       /E /COPY:DAT /R:1 /W:1
  robocopy "$s\deploy\client-bundle\openviking" "$d\deploy\client-bundle\openviking" /E /COPY:DAT /R:1 /W:1
  robocopy "$s\deploy\qm-pacgate"               "$d\deploy\qm-pacgate"               /E /COPY:DAT /R:1 /W:1
  ```
- [ ] **1.7 Verify the copy before touching anything else**
  ```powershell
  Get-Item 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\data\deer-flow\data\deerflow.db',
           'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\data\deer-flow\checkpoints.db' |
    Select-Object Name, @{N='MB';E={[math]::Round($_.Length/1MB,2)}}
  ```
  Expect `deerflow.db` ≈ 0.81 MB and `checkpoints.db` ≈ 1,635 MB.
  **If either is missing, STOP — do not proceed.**

- [ ] **1.8 Confirm no build output or client data entered git's view**
  ```powershell
  cd C:\Users\pacga\github-pr\pacgate-law
  git status --porcelain | Select-String 'target/|client-bundle/data/'
  ```
  **Expect no output from git for `target/`** (it must be gitignored).
  `client-bundle/data/` will appear as untracked — confirm it is gitignored:
  ```powershell
  git check-ignore -v pacgate-ai/deploy/client-bundle/data/deer-flow/checkpoints.db
  ```
  If this prints nothing, **add the rule before committing.**

---

## Task 2 — Rewrite the absolute path references

> ### ✅ STATUS: COMPLETE (2026-09-16) — commit `66051ec`
> Far smaller than planned. The scan found **22 references in 8 files**, of which
> only **2 were functional** — and both were stale *comments* in
> `build-images.ps1` / `build-frontend.ps1` whose code already used
> `$PSScriptRoot`. The other 6 were handbooks/plans, rewritten to the
> layout-agnostic `<monorepo>\pacgate-ai` (20 replacements) so they are correct
> on this machine, machine #2 and the developer's clone alike.
>
> **No compose file, `.env`, or runtime config contained the old path** — because
> the mounts are relative (see the correction at the top of this plan).
>
> **Trap hit while scanning:** the first pass searched for `'C:\\pacgate-ai-pr'`
> in a *single-quoted* PowerShell string, where `\\` is a **literal two
> backslashes** — so it reported 0 hits and looked like a clean result. The real
> pattern is a single backslash. Always confirm a "0 hits" result with a broader
> pattern before trusting it.
>
> **Trap avoided while rewriting:** files were read/written as raw bytes + UTF-8,
> never `Get-Content`/`Set-Content`, to avoid GBK double-encoding. Verified 0
> mojibake and 0 damaged GitHub URLs (only the drive-letter form was replaced).

**Deliverable:** nothing in the platform refers to `C:\pacgate-ai-pr` any more.

- [ ] **2.1 Inventory what refers to the old path** (23 known files):
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\scan-hardcoded-paths.ps1
  ```
  Worst offender is `.vscode\tasks.json` with **602** references.

- [ ] **2.2 Rewrite them** — prefer relative/`${workspaceFolder}` over a new absolute path:
  ```powershell
  # .vscode/tasks.json: 602 refs -> workspace-relative
  # deploy/*.ps1: use $PSScriptRoot-relative paths
  # docs/*.md: update the documented paths
  ```
  ⚠️ Do **not** blindly swap the string in markdown handbooks — read each hit; some
  are historical records that should stay as written.

- [ ] **2.3 Verify zero remaining functional references**
  ```powershell
  Select-String -Path C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\*.ps1,`
                       C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\*.ps1 `
               -Pattern 'C:\\pacgate-ai-pr'
  ```
  Expect none.

---

## Task 3 — Cut over the running stack

> ### ⏸ STATUS: READY, NOT RUN — needs a maintenance window
> Script: `runtime/relocate/task3-cutover.ps1` (dry-run by default; `-Execute` to apply).
> Dry-run validated. **This is the only remaining step that touches the running stack.**
>
> **The gap Phase 1 could not cover:** git carries only *tracked* content, but the
> stack needs **1,915.7 MB of gitignored runtime state** that currently exists only
> at the old path:
>
> | Item | Size | Why it is not in git |
> |---|---|---|
> | `client-bundle/data/` | 1,915.7 MB (244 files) | client chat history + `checkpoints.db` (1.6 GB) |
> | `client-bundle/openviking/` | 9 MB | per-machine runtime state |
> | `client-bundle/.env` | rendered | contains API keys |
> | `client-bundle/deer-flow-extensions-config.json` | rendered | contains keys |
> | `qm-pacgate/node_modules/` | 1.2 MB (130 files) | installed deps |
> | `qm-pacgate/.env` | rendered | contains keys |
>
> The copy happens **after** the stop, so the 1.6 GB `checkpoints.db` is not
> captured mid-write. See `runtime/relocate/RUNTIME-STATE-GAP.txt`.
>
> **Preflight (all verified):** compose names agree (`pacgate-ai-bundle`), the
> authoritative volume exists, 394 GB free, old location intact as rollback.

**Deliverable:** the stack running from the new location.

> ⚠️ **This is the downtime window.** Everything before this point was non-destructive.

- [ ] **3.1 Confirm writers are quiet**
  ```powershell
  docker compose -f pacgate-ai\deploy\client-bundle\compose.bundle.yaml ps
  ```
- [ ] **3.2 Stop the stack (from the OLD location, while the files still exist)**
  ```powershell
  cd C:\pacgate-ai-pr\deploy\client-bundle
  docker compose -f compose.bundle.yaml down
  cd C:\pacgate-ai-pr\deploy\qm-pacgate
  docker compose -f compose.qm.yaml down
  ```
  > **Do NOT pass `-v`.** `-v` removes volumes and would delete the databases.
- [ ] **3.3 Re-verify the copied data is intact and complete** (the source is still
  present, so this is free):
  ```powershell
  # compare file counts between old and new
  (Get-ChildItem 'C:\pacgate-ai-pr\deploy\client-bundle\data' -Recurse -File -Force).Count
  (Get-ChildItem 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\data' -Recurse -File -Force).Count
  ```
  The numbers must match. **If not, STOP and re-copy.**

- [ ] **3.4 Understand the Compose project-name trap BEFORE starting** — otherwise you
  can get a **new empty database**.

  **Measured state of the running stack** (via `docker inspect pacgate-db`):
  ```
  com.docker.compose.project              = pacgate-ai-bundle
  com.docker.compose.project.config_files = C:\pacgate-ai-pr\deploy\client-bundle\compose.bundle.yaml
  com.docker.compose.project.working_dir  = C:\pacgate-ai-pr\deploy\client-bundle
  ```
  So the **live stack came from `compose.bundle.yaml`**, which declares
  `name: pacgate-ai-bundle` explicitly.

  | File | `name:` key | Derived project | Safe? |
  |---|---|---|---|
  | `compose.bundle.yaml` | ✅ `pacgate-ai-bundle` | `pacgate-ai-bundle` | ✅ **use this** — matches the live volume |
  | `compose.prod.yaml` | ❌ absent | `client-bundle` (dir-derived) | ⚠️ would create a **2nd empty volume** |

  **Consequence for the cutover:** starting with the **same file that started the
  stack** (`compose.bundle.yaml`) preserves the project name and reattaches to the
  correct volume **automatically**. The trap only bites if the stack is started (or
  reinstalled via `install.ps1`) with `compose.prod.yaml`.

  **Action (defensive, do it in 3.5):** add the missing key to `compose.prod.yaml`
  so the two files can never disagree:
  ```yaml
  # deploy/client-bundle/compose.prod.yaml — add near the top
  name: pacgate-ai-bundle
  ```
  Then confirm both agree:
  ```powershell
  docker compose -f pacgate-ai\deploy\client-bundle\compose.prod.yaml config | Select-String '^name:'
  docker compose -f pacgate-ai\deploy\client-bundle\compose.bundle.yaml config | Select-String '^name:'
  ```
  Both must print `name: pacgate-ai-bundle`.

  > 📌 This repairs a **pre-existing latent defect** in `compose.prod.yaml` — it is
  > unrelated to the move, but the move is the right moment to fix it. If it is left
  > alone and someone later runs `install.ps1`, they get an empty DB and it looks
  > exactly like the migration destroyed their data.

- [ ] **3.5 Start from the NEW location**
  ```powershell
  cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
  docker compose -f compose.bundle.yaml up -d
  cd ..\qm-pacgate
  docker compose -f compose.qm.yaml up -d
  ```
  > ⚠️ Because the bind-mount paths changed, Docker must **recreate** the containers
  > for the new sources to take effect. `up -d` does this automatically since the
  > compose file changed; if a container keeps an old mount, use
  > `docker compose up -d --force-recreate`.
- [ ] **3.6 Verify the stack attached to the RIGHT volumes** (the critical check):
  ```powershell
  docker inspect pacgate-db --format '{{range .Mounts}}{{.Name}}{{"\n"}}{{end}}'
  ```
  Expected: `pacgate-ai-bundle_pacgate-db-data` — the **95.5 MB** authoritative volume.
  If it shows `client-bundle_pacgate-db-data`, the project name is still wrong; fix
  before continuing.

---

## Task 4 — Verify the migration

- [ ] **4.1 Containers back up (expect 25)**
  ```powershell
  docker ps --format "{{.Names}}`t{{.Status}}"
  ```
- [ ] **4.2 No dangling mounts** — every mount source must exist:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\test-delete-impact.ps1
  ```
  Expect **0** mounts under `C:\pacgate-ai-pr`.
- [ ] **4.3 The application actually works, not just "is Up"**
  Deleting a mount source leaves containers reporting `Up` while silently broken
  (verified experimentally). So check *behaviour*:
  - log in to the deer-flow UI
  - open a previously existing conversation (proves `checkpoints.db` is the right one)
  - query pacgate-api for a known record (proves the DB volume is right)
- [ ] **4.4 Compare runtime inventories**
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File runtime\capture-runtime.ps1
  ```
  Diff against `runtime/relocate/inventory-BEFORE.json`.
- [ ] **4.5 Credential gate**
  ```powershell
  git -C C:\Users\pacga\github-pr\pacgate-law ls-files | Select-String 'OPERATOR|MCP'
  ```
  Expect none.

---

## Task 5 — Retire the old location (archive, do not delete)

- [ ] **5.1 Observe the new location for a full working day.** If anything is off, roll
  back (§Rollback) — the source is still intact, so rollback is cheap.
- [ ] **5.2 Archive rather than delete**
  ```powershell
  New-Item -ItemType Directory -Path C:\archive -Force | Out-Null
  robocopy C:\pacgate-ai-pr C:\archive\pacgate-ai-pr-final /E /COPY:DAT /R:1 /W:1
  ```
  This preserves the 158 commits and any file not covered by the migration.
- [ ] **5.3 Only after the archive verifies:**
  ```powershell
  Remove-Item C:\pacgate-ai-pr -Recurse -Force
  ```
  ⚠️ Irreversible. Confirm `C:\archive\pacgate-ai-pr-final` is complete first.
- [ ] **5.4 Commit the migration in the new repo**
  ```powershell
  cd C:\Users\pacga\github-pr\pacgate-law
  git add -A
  git commit -m "feat: consolidate pacgate-ai-pr into the mono-stack repository

Migrated from C:\pacgate-ai-pr (HEAD 151a383) per
docs/superpowers/plans/2026-09-16-relocation-pacgate-ai-pr.md.
Platform now lives under pacgate-ai/ (Rust workspace promoted up one level
to avoid a double nest): deploy/, crates/, wasm-crates/, pacgate-adapters/,
scope-assets/, patches/, plans/, auth-gate/, nginx/, docs/, plus the untracked
runtime state the stack bind-mounts (client-bundle/data, openviking, qm).
Squashed import: source history is intentionally not carried, so the
publicly-exposed credential commits do not enter this repository.
Excludes build output (pacgate-ai/target)."
  ```

---

## Rollback

Rollback is cheap **until Task 5.3**. The source is never modified during Tasks 1–4.

- [ ] **R1 — Stop the new stack**
  ```powershell
  cd C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
  docker compose -f compose.bundle.yaml down     # NO -v
  ```
- [ ] **R2 — Start from the original location**
  ```powershell
  cd C:\pacgate-ai-pr\deploy\client-bundle
  docker compose -f compose.bundle.yaml up -d
  ```
- [ ] **R3 — Confirm the original volume is attached**
  ```powershell
  docker inspect pacgate-db --format '{{range .Mounts}}{{.Name}}{{"\n"}}{{end}}'
  ```
  Expected `pacgate-ai-bundle_pacgate-db-data`.
- [ ] **R4 — Delete the partial copy** in the repo (do not commit it).

**After Task 5.3 there is no rollback** — which is exactly why it is last.

---

## Appendix — if you later decide to preserve history

Not required for this migration (the import is a squash, because the source history
contains the four publicly-exposed credential files).

If history is ever needed, note that the **nested placement** (`pacgate-ai/…`) means
paths must be rewritten. `git filter-repo` is **not installed**; install it first:

```powershell
& 'C:\Program Files\Python313\python.exe' -m pip install git-filter-repo
```

Then, on a **copy** of the source (never the original, and never the archived one):

```powershell
git clone --no-local C:\archive\pacgate-ai-pr-final C:\temp\pacgate-rewrite
cd C:\temp\pacgate-rewrite
git filter-repo --to-subdirectory-filter pacgate-ai
```

Two cautions:

1. This rewrites **every commit hash** — any existing clone (including the
   developer's) becomes incompatible.
2. It would **re-introduce the credential files** unless they are stripped in the
   same pass:
   ```powershell
   git filter-repo --path-glob '**/pacgate-ai-remote-handbook/OPERATOR.md' `
                   --path-glob '**/MCP*/**' --invert-paths
   ```
   Even then, the credentials must already have been **rotated** — history rewriting
   cannot un-publish what is already public.

---

## Known traps (each verified during planning)

| Trap | Consequence | Guard |
|---|---|---|
| `compose.prod.yaml` has no `name:` | New **empty** DB volume → looks like data loss | Task 3.4; verify in 3.6 |
| Deleting a bind-mount source | Containers stay `Up` while silently broken | Task 4.2 + 4.3 behavioural check |
| `docker compose down -v` | **Deletes the databases** | Explicitly forbidden in 3.2 |
| `cp -r` the whole tree | 6.4 GB of build output/client data into git | Task 1.1 (`checkout-index` only) |
| CJK filename comparison in PowerShell | False "not tracked" → credentials slip through | Preflight P6 byte-level script |
| Renaming `deploy/client-bundle/` | Third empty volume generation | Global Constraint |
| Target is a submodule gitlink | `git add` writes a gitlink, not files | Preflight P5 / Task 1.0 |
| Naive copy nests `pacgate-ai\pacgate-ai\` | Awkward path, ambiguous naming | Task 1.3 (flatten; verified 0 collisions) |
| Bind mounts resolve only at container start | New paths do not take effect on a running container | Task 3.5 (`--force-recreate` if needed) |
| `check-ignore` inside a submodule boundary | Misleading `fatal: ... is in submodule`; looks like a missing rule | Preflight P8; remove gitlink first (Task 1.0) |
| Nested layout breaks anchored ignore rules | 1.9 GB of client data becomes stageable | Preflight P8; rules added to repo `.gitignore` |
| **`tar.exe` silently drops CJK filenames** | **59 files vanish, 22 more get mojibake names — with no hard error** | Task 1.1 uses `checkout-index`; Task 1.2 verifies |
| Tracked content carries a credential file | Would re-import a leaked secret | Task 1.4 mandatory removal + verification gate |
| CJK literals inside a `.ps1` | PowerShell's GBK read corrupts the literal *before* the script runs; probes report false "missing" | Build CJK strings from code points |
