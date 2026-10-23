# AGENTS.md — PacGate-Law (百宸法律 AI 系统)

> Guidance for AI coding agents working in this repo. Keep this minimal — link to
> the rich design docs in `assets/` rather than duplicating them.

## ⚠️ Topology correction (2026-10-23) — read first

**This folder IS the `pacgate-ai-pr` git root.** It is a real GitHub repo with
remotes, commits and a pushed branch. The earlier note calling it a "LOCAL-ONLY
docs wrapper" was wrong and has been corrected.

- **Path on this machine:** `C:\Users\pacga\github-pr\pacgate-law`
- **`origin`:** `github.com/JZKK720/pacgate-ai-pr` (read/pull)
- **`fork`:** `github.com/pacgate-ai/pacgate-ai-pr` (push target)
- **Upstream root maps to the local `pacgate-ai/` subtree.** Upstream's
  `deploy/`, `scripts/`, `plans/` are this repo's `pacgate-ai/deploy/`,
  `pacgate-ai/scripts/`, `pacgate-ai/plans/`.

> ⚠️ **The two histories are UNRELATED** (different root commits). `git diff
> upstream/main..HEAD` compares two unrelated trees and reports every file as
> changed. Never use it. Compare content instead — see "Sync workflow" below.

The actual agent workspace (deer-flow + PacGate layer) lives at
`C:\Users\pacga\github-pr\pacgate-law\deer-flow` (branch `pacgate-layer`).

> **Do NOT** write Rust source for the scaffolded
> `pacgate-ai/pacgate-ai/Cargo.toml` workspace unless explicitly asked.

## What this project is

百宸 (Baichen) law firm's legal-AI system. **First deliverable**: due-diligence report
(尽调报告). **Red line**: every AI output is a draft for lawyer review — never a final
legal opinion, never silent fabrication.

## Local folder layout

```
pacgate-law/                      ← the pacgate-ai-pr git root
├── AGENTS.md                      ← this file
├── DEER-FLOW-INTEGRATION.md       ← bridge doc: what to port into deer-flow
├── runtime/                       ← container/image inventory, handoffs, patches
├── docs/superpowers/specs/        ← design docs
├── deer-flow/                     ← agent workspace clone (branch pacgate-layer)
│   └── docker/Dockerfile.pacgate  ← builds ghcr.io/pacgate-ai/deer-flow-pacgate
└── pacgate-ai/                    ← SUBTREE = upstream pacgate-ai-pr root
    ├── deploy/client-bundle/      ← THE LIVE STACK (compose.bundle.yaml)
    ├── deploy/qm-pacgate/         ← the qm co-working stack
    ├── scripts/                   ← the gate suite
    └── pacgate-ai/                ← the real Rust workspace (crates/)
```

> ⚠️ **`pacgate-ai` is a name collision, not a duplicate.** The nested
> `pacgate-ai/pacgate-ai/` is the real Rust workspace (with `crates/`). The
> outer `pacgate-ai/` is the upstream repo root. `C:\pacgate-ai-pr` still exists
> on this machine but **owns no container** — it is not the live stack.

> ⚠️ **`pacgate-ai/` is a plain subtree, NOT a git submodule.** There is no
> gitlink and no `.gitmodules` entry for it. Do not try to `git submodule update`.

## Runtime stack — spread across SIX compose projects

Only **14 of 25** running containers trace back to the pacgate platform repo. The rest
belong to separate sibling clones under `C:\Users\pacga\github-pr\`. There is no
single repo that describes the whole running stack.

> **⚠️ The live pacgate stack runs from THIS MONOREPO, not `C:\pacgate-ai-pr`.**
> Verified 2026-09-23 from live container labels: project `pacgate-ai-bundle`,
> working dir `pacgate-law\pacgate-ai\deploy\client-bundle`, config
> `compose.bundle.yaml`. The old `deploy/` paths in the table below are **stale** —
> `C:\pacgate-ai-pr` still exists but owns no container.

| Compose project | # | Compose file |
|---|---|---|
| `pacgate-ai-bundle` | 7 | `pacgate-law\pacgate-ai\deploy\client-bundle\compose.bundle.yaml` |
| `qm-pacgate` | 7 | `pacgate-law\pacgate-ai\deploy\qm-pacgate\compose.qm.yaml` |
| `odysseus` | 4 | `C:\Users\pacga\github-pr\odysseus\docker-compose.yml` |
| `hermes-agent` | 3 | `C:\Users\pacga\github-pr\hermes-agent\docker-compose.upstream.yml` |
| `ironclawai-survey` | 1 | `C:\Users\pacga\github-pr\ironclawai-survey\docker-compose.yml` |
| `dockhand` | 1 | `C:\Users\pacga\github-pr\dockhand-dash\docker-compose.yaml` |
| *(unmanaged)* | 2 | `cloudflare`, `open-webui` — bare `docker run`, no compose owner |

### ⚠️ Running `install.ps1` / the update path — verified protocol

**`install.ps1` fails on this machine with exit code 1**, for two independent reasons:

1. `docker compose -f compose.prod.yaml pull` (its L477) returns exit 1 because
   **`docker.io` / `registry-1.docker.io` is UNREACHABLE here** (the VPN does not proxy
   it) — `nginx:1.27-alpine` and `pgvector/pgvector:pg16` cannot resolve. The script sets
   `$ErrorActionPreference="Stop"`, so it terminates there, before `up -d`. `ghcr.io` IS
   reachable. Nothing gets recreated when this happens.
2. It prints `[WARN] <repo>\pacgate-ai is not a git checkout - cannot refresh` — it looks
   for `.git` at `pacgate-ai/`, but the real git root is `pacgate-law/`. Its repo-refresh
   step is a no-op here.

**🚨 Back up `deer-flow-extensions-config.json` before running it.** The render step
regenerates that file from `deer-flow-extensions-config.template.json`, which is a
**3-server stub** (openviking/pacgate/officecli). That silently wipes the **27 legal-database
connectors** (firecrawl, yuandian-*, 11x pkulaw-*, 11x qcc-*, vaquill, ansvar) and reports
only `MCP servers REMOVED: firecrawl - check the template`. Restore byte-exact from the
`.bak.<timestamp>` it leaves behind.

To apply a compose **env or volume** change, `up -d` alone is NOT enough — Compose does not
recreate on an env-only change. Use:

```powershell
docker compose -f <abs>\compose.bundle.yaml up -d --force-recreate --no-deps <service>
```

This is safe for bind-mounted state and named volumes, and avoids touching `pacgate-db`.
Confirm with `docker inspect <svc> | ConvertFrom-Json` and read `.Config.Env` / `.Mounts`.
(`docker inspect -f '{{index .Config.Labels "..."}}'` breaks under PS 5.1.)

**To regenerate the pinned inventory** (records image digests, flags floating
refs and unmanaged containers):

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\runtime\capture-runtime.ps1
```

**Known gaps as of 2026-09-16**: 9 containers use floating image refs
(`:latest` / `:main` / no tag) and 2 are unmanaged. `qm-pacgate` (5 images) and
`openviking` are already digest-pinned — follow that pattern. See
`runtime/RUNTIME-INVENTORY.md` for the full list.

### ⚠️ Named-volume / project-name hazard (already triggered on this machine)

Docker Compose prefixes named volumes with the **Compose project name**. If that
name changes, Compose creates a **new empty volume** and the app connects to an
empty database — which looks exactly like data loss, while the real data still
sits in the old volume.

Two compose files in the **same** directory declare the **same** volume but
produce **different** project names:

| File | `name:` key | Derived project | Volume created |
|---|---|---|---|
| `compose.bundle.yaml` | `pacgate-ai-bundle` | `pacgate-ai-bundle` | `pacgate-ai-bundle_pacgate-db-data` |
| `compose.prod.yaml` (used by `install.ps1`) | **`pacgate-ai-bundle`** (added 2026-09-23) | `pacgate-ai-bundle` | same volume |

**Fixed 2026-09-23.** `compose.prod.yaml` previously had **no `name:`**, so it derived
`client-bundle` from the directory and would have created a second, empty
`client-bundle_pacgate-db-data`. It is now pinned to `pacgate-ai-bundle`, so both files
converge on the live volume. **Do not remove that key.**

**Both volumes exist right now** (created 2026-09-01 and 2026-09-02). The running
`pacgate-db` is attached to `pacgate-ai-bundle_pacgate-db-data`; the
`client-bundle_` one is orphaned.

**Forensics (read-only, 2026-09-16)** — the orphan is **not** empty:

| | `pacgate-ai-bundle_` | `client-bundle_` |
|---|---|---|
| Size | **95.5 MB** | 46.6 MB |
| Newest write | **2026-09-15** | 2026-09-01 |
| Attached | ✅ `pacgate-db` | ❌ nobody |

So `pacgate-ai-bundle_` is authoritative, but the orphan holds 46.6 MB of real
2026-09-01 data. **Do not delete either.** Full detail:
`runtime/VOLUME-INVESTIGATION-FINDINGS.md`.

**Consequences — read before moving anything:**

- **Do NOT rename or move `deploy/client-bundle/`.** `compose.prod.yaml` derives
  its project name from the directory, so a rename produces a third empty volume.
- **Do NOT delete any volume** until you have confirmed which one holds real data.
- Before deploying, verify the project name:
  `docker compose -f deploy/client-bundle/compose.prod.yaml config | findstr name`

Evidence: `runtime/volume-generations.txt`, `runtime/critical-verification.txt`.
Plan: `docs/superpowers/specs/2026-09-16-mono-stack-delivery-plan.md` (§3).

## Key docs to read

- `DEER-FLOW-INTEGRATION.md` — what to port into deer-flow, draft configs
- `C:\pacgate-ai-pr\deploy\AIPC-DEPLOYMENT-HANDBOOK.md` — two-AIPC deployment handbook
- `C:\pacgate-ai-pr\deploy\AIPC2-HANDOFF-PROMPT.md` — machine #2 setup prompt
- `assets/智库资料收集/智库资料收集/Agent角色边界/SOUL_Sylvie_v1.0.md` — agent persona/charter

## Environment (Windows box — critical)

- **Python**: `python` is NOT in PATH. Always use `C:\Program Files\Python313\python.exe`.
- **PowerShell**: execution policy blocks `npx.ps1` — wrap in `cmd.exe /c "npx ..."`.
- **Encoding**: Chinese Windows defaults to GBK. Never use `Get-Content`/`Set-Content`
  on UTF-8 Chinese files (causes double-encoded mojibake). Use `[System.IO.File]::ReadAllBytes`
  / `WriteAllBytes`, or pipe through `docker exec sh -c "cat ..."` for text.
- **Headless Chrome**: use legacy `--headless` (not `--headless=new`, which crashes).
- **markitdown** is installed (`markitdown[all]` v0.1.6) for PDF/DOCX → MD conversion.
- **VPN required for GitHub + Docker**: this client machine needs VPN to reach
  `github.com` and `docker.io`. The developer's own machine does NOT need VPN. Sync
  state must be pushed from this machine so the developer can pull from `JZKK720/*`
  on their own machine. See "Sync workflow" below.

## Sync workflow (adopt an upstream release, then push to the fork)

This client machine (VPN-required) is the **only** place that can reliably push to
GitHub. The developer's own machine pulls from `JZKK720/*` without VPN.

### 1. Adopt an upstream release into the `pacgate-ai/` subtree

The two histories are unrelated, so **do not merge**. Swap the subtree by index:

```powershell
cd C:\Users\pacga\github-pr\pacgate-law
git fetch upstream --tags --prune
git rm -r --cached pacgate-ai --quiet
git read-tree --prefix=pacgate-ai/ "v0.2.3^{tree}"   # QUOTE the rev
git checkout -- pacgate-ai
```

- **Quote `"v0.2.3^{tree}"`.** Unquoted, PowerShell parses `^` and fails with
  "unknown switch `e`".
- `read-tree` only updates the **index**; `git checkout -- pacgate-ai` syncs the
  working tree.
- **Verify byte-identity by tree SHA**, not per-file (per-file loops break on CJK
  paths — see the PS 5.1 note above):

```powershell
$newRoot = (git write-tree).Trim()
git rev-parse "${newRoot}:pacgate-ai"   # must equal: git rev-parse "v0.2.3^{tree}"
```

- **Local-only files survive on disk as untracked.** Re-add them:
  `git -c core.quotepath=false ls-tree -r --name-only HEAD -- pacgate-ai` before
  the swap, diff against the tag, then `git add` each. Without
  `core.quotepath=false`, CJK paths come back octal-escaped and `Test-Path` fails.
- **Re-apply the AIPC1 deltas** (they are reverted by the swap): skills +
  uploads-middleware mounts, the context-capped model roster, the
  `ollama-models.txt` derived-tag block, the `deer-flow-prompt.py` read_file
  directive, `audit-model-tags.ps1` `.env` tier reading, and the 7 gate-script
  fixes. See `runtime/` for the current set.

### 2. Pull the pinned images and recreate

```powershell
cd pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml pull
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps `
  pacgate-api deer-flow deer-flow-frontend pacgate-mcp ocr-service
```

`up -d` alone is **not** enough for an env-only or mount-only change — Compose
does not recreate on those. `--force-recreate --no-deps` is safe for bind-mounted
state and named volumes, and avoids touching `pacgate-db`.

### 3. Push to the fork

```powershell
git push fork HEAD:aipc1/v0.2.3-sync
```

- `origin` = `github.com/JZKK720/pacgate-ai-pr` (read/pull)
- `fork` = `github.com/pacgate-ai/pacgate-ai-pr` (push target)
- **Never force-push `main`.** `fork/main` is a *different lineage* with commits
  this HEAD does not have. Push to an `aipc1/*` branch instead.

### 4. deer-flow integration repo — push the `pacgate-layer` branch

deer-flow is at `c:\Users\pacga\github-pr\pacgate-law\deer-flow`, checked out on
branch `pacgate-layer`. Remotes: `fork` = `github.com/pacgate-ai/deer-flow.git`
(push target), `origin` = `github.com/JZKK720/deer-flow.git`, `upstream` =
`github.com/bytedance/deer-flow.git`.

```
git -C c:\Users\pacga\github-pr\pacgate-law\deer-flow push fork pacgate-layer
```
**Do NOT commit** gitignored config: `config.yaml`, `extensions_config.json`, `.env`,
`.deer-flow/` (contains Sylvie SOUL.md + agent config with secrets). These are
gitignored by deer-flow's `.gitignore` — verify with `git check-ignore` before adding.

### 5. Patches must stay LF

`core.autocrlf=true` is set on this box. A `.patch` committed with LF is checked
out with CRLF, and `git apply` then fails against upstream's LF sources with
"patch does not apply". `.gitattributes` pins `*.patch`/`*.diff` to `-text` so
this cannot recur. Verify a patch before handing it over:

```powershell
git apply --check -p2 runtime/<name>.patch   # against a vX.Y.Z checkout
```

### Credentials safety (applies to any commit)

> ⚠️ **HISTORICAL INCIDENT — rotation still outstanding.**
> Full detail: `docs/superpowers/specs/2026-09-16-credential-exposure-incident.md`.
> **4** credential files were tracked and publicly readable on GitHub. They are
> now **untracked and ignored** (`.gitignore:121` → `pacgate-ai-assets/`), so the
> leak is closed going forward. **The credentials themselves must still be
> rotated — deleting files cannot undo public history.**

The four exposed files (all under one subtree,
`pacgate-ai-pr/pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/`):

| File | Content |
|---|---|
| `pacgate-ai-remote-handbook/OPERATOR.md` | PacGate GitHub account credentials |
| `MCP授权/法律数据库MCP.md` | legal-DB unified login + password |
| `MCP授权/境外法律数据库和网站.md` | overseas legal-DB accounts |
| `MCP授权/百宸AI系统资源接入清单V2.docx` | resource access inventory |

⚠️ **Three of the four have Chinese filenames.** Checking them by string
comparison **silently fails** on this machine: PowerShell 5.1 decodes git's UTF-8
output using the GBK console codepage, so CJK paths become mojibake and never
match — producing a *false* "not tracked" result. Verify with the byte-level
script instead, which is codepage-proof:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runtime\AUTHORITATIVE-credential-check.ps1
```

**The correct check is against the tracked paths in THIS repo.** The commands
previously documented here pointed at `pacgate-ai/assets/...`, which resolved
inside what was then a submodule — and that submodule's `.gitignore` *did* ignore
them, so those commands returned "ignored" and gave false assurance about a repo
that was actually leaking.

Before any push, confirm the four files are untracked **and** that the ignore
rule exists in this repo's `.gitignore`:

```powershell
git check-ignore -v "pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md"
```

If that prints nothing, **STOP** — the root cause is unfixed.

## Conventions

- **Language**: docs are Simplified Chinese; code identifiers are English (`pacgate-*`).
- **MCP**: the system *consumes* external legal MCP servers (北大法宝, 元典, 企查查,
  CourtListener, Vaquill, SEC EDGAR) via `.mcp.json` connector configs. It does not
  yet *host* an MCP server.
- **No Docker** is used in this repo currently. `ironclaw`/`hermes` agent harnesses
  live on the machine but are NOT part of this repo — they are external local agents
  to be integrated via the chosen multi-agent workspace (see below).
- **hermes** = `NousResearch/hermes-agent` (216k★, MIT) — self-improving agent with
  gateway + cron + **ACP server** (`hermes acp`, stdio JSON-RPC). Also an ACP client.
  Has Chinese docs. **ironclaw** = `nearai/ironclaw` (12.5k★) — "Agent OS focused on
  privacy, security and extensibility"; MCP client (HTTP/stdio/unix), extension system.
  hermes ports security code FROM ironclaw (sibling NousResearch/nearai projects).
- **Credentials**: see the "Credentials safety" section above — it is an **active
  incident**, not a hypothetical. `OPERATOR.md` is **tracked and public** in
  `pacgate-ai-pr` despite its own header claiming it is gitignored.

## Multi-agent workspace decision (2026-07-17)

Research compared 5 candidates for adapting (not building) an open-source agent
workspace to run the client's daily cron tasks and integrate the local
`ironclaw`/`hermes` agent harnesses. Full comparison:
`/memories/session/multi-agent-workspace-research.md`.

| Candidate | Repo | Verdict |
|---|---|---|
| **deer-flow** | `bytedance/deer-flow` | ✅ **Primary choice** — ACP `invoke_acp_agent` (pluggable, like codex/claude_code), built-in `scheduled_tasks` (cron), MCP via `extensions_config.json`, `SKILL.md` skills, Chinese docs, Apache-2.0 |
| **Ruflo** | `ruvnet/ruflo` | 🥈 Strong alt — explicitly references "hermes-agent pattern" in code, autopilot+cron, MCP server mode, 64.6k stars; but English-only, less structured skills |
| goose | `aaif-goose/goose` | ❌ Excellent local agent, but no scheduler/multi-agent workspace; ACP providers are code-centric |
| paperclip | `paperclipai/paperclip` | ❌ Multiple critical security advisories (RCE, cross-tenant IDOR, XSS) — unacceptable for a law firm |
| ai4ui | `web3dev1337/agent-workspace` | ❌ 31 stars, no MCP/cron/harness integration, just parallel CLI runner |

**Integration of hermes/ironclaw (verified)**: hermes exposes `hermes acp` (stdio ACP
server) → integrates with deer-flow **by default** (config-only: `acp_agents.hermes:
{command: hermes, args: [acp]}`) and with goose (ACP providers). ironclaw has no native
ACP-server mode (it's an MCP client/Agent OS) → needs a thin ACP adapter in ANY
workspace (unavoidable one-time work). Ruflo references hermes *patterns* but not the
hermes *protocol*. ai4ui only wraps agent CLIs as terminal panes (no ACP/MCP).

**Integration path (deer-flow)**: add `hermes` to `acp_agents` in `config.yaml`
(config-only); write a thin ACP adapter for `ironclaw` (mirrors `@zed-industries/codex-acp`);
port legal MCP connectors into `extensions_config.json`; port PacGate skill skeletons
(NDA, VC/PE, due-diligence) into `skills/public/SKILL.md`; use `scheduled_tasks` for daily
cron; use `SOUL.md` for the Sylvie persona; map 3-tier routing to deer-flow's model factory.

## Add-on CLI tools (deer-flow compatibility, verified 2026-07-17)

| Tool | Repo | Type | deer-flow integration | PacGate value |
|---|---|---|---|---|
| **OfficeCLI** | `iOfficeAI/OfficeCLI` (18.5k★, Apache-2.0, C# binary) | MCP stdio server (`officecli mcp`) | ✅ **Native MCP** — add to `extensions_config.json` as a stdio server; auto-registers with claude/cursor/vscode/lmstudio | HIGH — Word/Excel/PPT automation for due-diligence reports; no MS Office needed on the box; has Chinese README |
| **OpenWiki** | `langchain-ai/openwiki` (11.9k★, Node/TS) | CLI (consumes MCP for Notion; does NOT expose MCP) | ⚠ **As a cron'd CLI / skill** — run `openwiki --update` via a `scheduled_task`; output dir read by the sandbox `read_file` tool | MEDIUM — maintains internal knowledge-base docs; best as a nightly regeneration task |

OfficeCLI config snippet for `extensions_config.json`:
```json
{ "mcpServers": { "officecli": { "enabled": true, "type": "stdio",
  "command": "officecli", "args": ["mcp"], "description": "Word/Excel/PPT for agents" } } }
```

## Agent guidance

- When editing design docs, preserve Chinese phrasing and the "红线" (red line) framing.
- When converting client PDFs/DOCX, use `markitdown` (already installed) and write
  sibling `.md` next to the source; never clobber existing `.md` — use `_converted.md` suffix.
- Do NOT commit `OPERATOR.md` or `法律数据库MCP.md` (credentials).
- Before proposing code for the Rust workspace, note that the 16 crates are
  scaffolded only — confirm with the user whether to start implementation or
  continue planning in `assets/`.