# Runtime inventory

Pinned record of every Docker container and image on this machine, plus the
compose project that owns each one.

## Why this exists

The stack is spread across **six** independent compose projects in six
different directories. Nothing in a single repo describes what is actually
running, so there is no way to answer "what exactly is deployed, and can we
rebuild it?" without inspecting the live daemon.

This directory fixes that by generating a snapshot on demand.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\capture-runtime.ps1
```

Options:

```powershell
# write outputs somewhere else
.\capture-runtime.ps1 -OutDir C:\some\other\dir
```

Outputs (overwritten on each run):

| File | Purpose |
|---|---|
| `runtime-inventory.json` | Full fidelity, machine-readable. Includes digests, ports, networks, restart policies. |
| `RUNTIME-INVENTORY.md` | Human-readable, grouped by compose project, with a risk section. |

The `RUNTIME-INVENTORY.md` file is generated — **do not hand-edit it**. Change
the script instead.

## How to read the two risk categories

The script deliberately separates two problems that are easy to conflate:

**Unmanaged** — the container was started outside compose (bare `docker run`).
No compose file rebuilds it, and no project owns its lifecycle or config.
These are invisible to `docker compose` commands.

**Floating image ref** — the image reference does not name immutable bytes.
A future `docker compose pull` can silently hand you different code than what
is running now. Two sub-cases:

- a moving tag (`:latest`, `:main`) — the tag will be re-pointed by upstream
- no tag at all — implicitly `:latest`, same problem, easier to miss

Pinning by digest (`image@sha256:...`) is the only form that is actually
reproducible.

**The `Digest` column is forensic, not a pin.** It records the exact bytes the
container is running *right now*, and it resolves locally for every image,
including floating ones. That is intentional: even when a reference floats, the
currently-running state stays recoverable. Presence of a digest does **not**
mean the reference is pinned — check the `Ref pinned` column.

An earlier version of this script treated "has a local digest" as "is pinned",
which marked every floating reference as safe. That was backwards and is fixed.

## Current known issues

Generated 2026-09-16, 25 containers:

- **2 unmanaged**: `cloudflare`, `open-webui`
- **9 floating refs**: see the risk section of `RUNTIME-INVENTORY.md`

Neither is fixed here on purpose. Repinning changes deployment behaviour and
needs a human decision; `ironclawai-survey` in particular is built locally and
has no registry digest to pin to.

Also worth confirming: the bundle runs `deer-flow-pacgate:0.1.10` alongside
`deer-flow-frontend-pacgate:0.1.11`. The compose file and the running
containers agree with each other, so this is consistent — but it is a
cross-version pairing and may or may not be intended.

## Container → repo map

Only 14 of the 25 containers trace back to a repo in this workspace.

| Compose project | Containers | Compose file |
|---|---|---|
| `pacgate-ai-bundle` | 7 | `C:\pacgate-ai-pr\deploy\client-bundle\compose.bundle.yaml` |
| `qm-pacgate` | 7 | `C:\pacgate-ai-pr\deploy\qm-pacgate\compose.qm.yaml` |
| `odysseus` | 4 | `C:\Users\pacga\github-pr\odysseus\docker-compose.yml` |
| `hermes-agent` | 3 | `C:\Users\pacga\github-pr\hermes-agent\docker-compose.upstream.yml` |
| `ironclawai-survey` | 1 | `C:\Users\pacga\github-pr\ironclawai-survey\docker-compose.yml` |
| `dockhand` | 1 | `C:\Users\pacga\github-pr\dockhand-dash\docker-compose.yaml` |
| *(unmanaged)* | 2 | none — bare `docker run` |

---

## Evidence files (from the mono-stack planning investigation)

These `.txt` files are raw measurements captured while planning the consolidation
of `C:\pacgate-ai-pr` into this repo. They are kept so the plan's claims can be
checked rather than trusted. See
`../docs/superpowers/specs/2026-09-16-mono-stack-delivery-plan.md`.

| File | What it shows |
|---|---|
| `tracked-vs-excluded-audit.txt` | Per-directory tracked vs gitignored counts |
| `client-bundle-breakdown.txt` | What makes up the bundle's 1,924 MB of excluded content |
| `delivery-mechanics.txt` | Largest files, delivery archives, services per compose project |
| `install-mechanics.txt` | How `install.ps1` works; template vs live config |
| `volume-coupling.txt` | Bind-mount definitions and their relocation risk |
| `project-name-and-volumes.txt` | Project names, named volumes, container→volume bindings |
| `volume-generations.txt` | **The duplicate-volume evidence** (see below) |
| `critical-verification.txt` | Project-name derivation and duplicate-volume detection |
| `hardcoded-path-references.txt` | 23 files hardcoding the old absolute path |
| `final-encoding-verdict.txt` | Byte-level UTF-8 validation of authored docs |

### ⚠️ The volume finding in `volume-generations.txt`

Two volumes exist with the **same declared name** but **different project prefixes**:

```
client-bundle_pacgate-db-data        created 2026-09-01  project=client-bundle      (orphaned)
pacgate-ai-bundle_pacgate-db-data    created 2026-09-02  project=pacgate-ai-bundle  (in use)
```

This is not hypothetical — it already happened here. `compose.prod.yaml` (which
`install.ps1` uses) has no `name:` key, so its project name — and therefore its
volume prefix — derives from the **directory name** `client-bundle`.
`compose.bundle.yaml` sets `name: pacgate-ai-bundle` explicitly. Running one after
the other yields an empty database that looks exactly like data loss.

**Before moving or renaming `deploy/client-bundle/`, read §3 of the plan and
confirm which volume holds real data. Do not delete volumes.**

## Requirements

- Docker CLI on `PATH`
- PowerShell 5.1+ (ships with Windows)
- The script file must keep its **UTF-8 BOM**. It contains non-ASCII characters
  (em-dashes), and PowerShell 5.1 reads BOM-less scripts using the system ANSI
  codepage — on Chinese Windows that means GBK, which turns the em-dashes into
  mojibake in the generated Markdown. If you re-save the script, save it as
  UTF-8 *with* BOM.

---

## Security scripts

Two additional scripts support an open security incident (see
`../docs/superpowers/specs/2026-09-16-credential-exposure-incident.md`).
They are not part of the container inventory; they exist to verify the exposure
and to re-verify after remediation.

| Script | Purpose | Output |
|---|---|---|
| `scan-credential-history.ps1` | Full-history content scan (`git log --all -S`, includes deleted files) across the three PacGate repos | `credential-scan-results.txt` |
| `check-exposure-control.ps1` | Checks whether the credential file is still publicly readable | `exposure-control-results.txt` |
| `check-authored-files-for-leaks.ps1` | Self-check: confirms the incident documents do not themselves reproduce any credential value | `leak-selfcheck-results.txt` |

Run with an absolute path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\scan-credential-history.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\check-exposure-control.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\check-authored-files-for-leaks.ps1"
```

`check-authored-files-for-leaks.ps1` deliberately **excludes public identifiers**
by label — the account/org name appears in every repo URL and directory path, so
counting it as a secret produces noise. Its first version reported 3 false
failures for exactly that reason. It also never prints a value, reporting only
counts and source row numbers.

### Why both scripts include negative controls

Each script deliberately tests a **case that must fail**, because a single
signal produces false confidence:

- **HTTP check**: a corporate proxy or VPN can answer `200` for any request.
  `check-exposure-control.ps1` therefore requests a bogus path and a bogus repo
  that must both return `404`. If the controls return `200`, the results are
  being intercepted and prove nothing.
- **`git log -S` check**: zero hits could mean "repo is clean" *or* "the search
  never ran" (wrong path, broken repo). So each repo is also searched for a
  string known to exist; that control must return more than zero.

When first used, the controls behaved correctly (`404` on bogus paths,
non-zero hits on known strings), confirming that the `200` and the zero-hit
results were both genuine.
