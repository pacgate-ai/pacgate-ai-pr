# DeerFlow Integration Guide — PacGate-Law → deer-flow

> **Purpose**: This is the bridge document. When you open the new deer-flow repo
> folder, read this to know exactly what to port from `pacgate-law` into deer-flow,
> where each asset lives, and how it maps to deer-flow's config surfaces.
>
> **Status**: 2026-07-17 — research complete, deer-flow chosen, configs drafted below.
> **Maintainer**: keep this in sync as assets evolve.

## 1. What's been done in this repo (pacgate-law)

| Date | Work | Output |
|---|---|---|
| 2026-07-17 | Converted 11 client PDF/DOCX → Markdown | `assets/百宸初建方案文件/**/*.md` (see §3) |
| 2026-07-17 | Researched 5 multi-agent workspaces | Chose **deer-flow** (`bytedance/deer-flow`) |
| 2026-07-17 | Identified local agent harnesses | **hermes** = `NousResearch/hermes-agent` (216k★, ACP server `hermes acp`); **ironclaw** = `nearai/ironclaw` (12.5k★, MCP client/Agent OS) |
| 2026-07-17 | Researched add-on CLI tools | **OfficeCLI** (native MCP stdio server); **OpenWiki** (cron'd CLI) |
| 2026-07-17 | Created agent guidance | `AGENTS.md` (workspace root) |

Full research: `/memories/session/multi-agent-workspace-research.md` (session memory).

## 2. The decision: deer-flow

**Repo**: `bytedance/deer-flow` (Python, Apache-2.0, v2.0, bytedance).
**Why**: only candidate that integrates hermes *by default* (ACP, config-only) AND has
cron (`scheduled_tasks`) + MCP consumption (`extensions_config.json`) + skills
(`SKILL.md`) + Chinese docs.

**Why not the others**:
- Ruflo (`ruvnet/ruflo`) — references hermes *patterns* but not the protocol; English-only.
- goose (`aaif-goose/goose`) — no scheduler/workspace.
- paperclip (`paperclipai/paperclip`) — critical security advisories (RCE, IDOR, XSS).
- ai4ui (`web3dev1337/agent-workspace`) — CLI-pane wrapper only; no ACP/MCP/cron.

## 3. PacGate assets to port into deer-flow

All paths below are relative to `pacgate-law/` (this repo). When working in the
deer-flow folder, navigate here to read/copy these.

### 3.1 Architecture & design docs (read for context)
```
pacgate-ai/assets/百宸初建方案文件/
├── 方案_模板类文件/
│   ├── 01_总路线图_系统架构与落地.md      ← master architecture (7-layer, 3-tier cloud, 3-axis routing, B0–B5)
│   └── Step5_本地复杂推理_评测方案模板.md   ← local-model evaluation (gold dataset, danger-error ≤2%, upgrade threshold τ)
├── 架构改造类文件/
│   ├── 百宸NDA审查Skill_三层混合云架构改造.md  ← NDA-review skill spec (8-step flow × 3-axis labels)
│   ├── 尽调报告系统改造方案_corporate-legal_与_dd-agents_组合_.md  ← due-diligence system (方案A/B, 11-chapter framework)
│   ├── corporate-legal_13skill改造优先级评估.md  ← 13-skill priority (P0–P3 batches)
│   └── 百宸NDA审查Skill_双模型架构改造示范.md    ← archived v0.1
├── 清单类文件/
│   ├── 百宸AI系统资源接入清单.md            ← ★ MCP/API resource registry (元典/北大法宝/企查查/CourtListener/...)
│   ├── Awesome-Legaltech-资源清单.md        ← global legal-tech landscape
│   └── dd-agents 中国法智能体改写清单.md     ← 9-domain DD agent rewrite (US→China law)
└── 索引_骨架类文件/
    ├── 00_文档总览索引.md                   ← document master index
    └── skill骨架_VCPE投融资协议套.md         ← VC/PE document-suite skill skeleton
```

### 3.2 Persona (→ deer-flow `SOUL.md`)
```
pacgate-ai/assets/智库资料收集/智库资料收集/Agent角色边界/SOUL_Sylvie_v1.0.md
```
Port this into deer-flow's custom-agent `SOUL.md` (deer-flow supports agent-editable
`SOUL.md` rendered into the lead-agent system prompt).

### 3.3 Lawyer prompt guides (→ deer-flow skills or reference docs)
```
pacgate-ai/assets/智库资料收集/智库资料收集/律师角色提示指南/
├── 合规律师实用Prompts指南.md
├── 基金律师实用Prompts指南.md
├── 律师日常通用Prompts指南.md
├── 诉讼律师实用Prompts指南.md
└── 非诉律师实用Prompts指南.md
```

### 3.4 MCP credentials (⚠ sensitive — do NOT commit)
```
pacgate-ai/assets/智库资料收集/智库资料收集/MCP授权/法律数据库MCP.md
```
Contains plaintext legal-DB passwords (元典/北大法宝/企查查). **NOT gitignored** —
flag before any commit. Use these values to populate deer-flow's env vars / secrets,
never commit them into the deer-flow repo either.

### 3.5 Remote-access handbook (operator-only, gitignored)
```
pacgate-ai/assets/pacgate-ai-remote-handbook/OPERATOR.md  ← gitignored, real GitHub creds
pacgate-ai/assets/pacgate-ai-remote-handbook/render.py    ← md→PDF via headless Chrome
```

## 4. Integration map: PacGate asset → deer-flow config surface

| PacGate asset | deer-flow surface | Config file | How |
|---|---|---|---|
| Legal MCP servers (元典, 北大法宝, 企查查, CourtListener, Vaquill, SEC EDGAR) | MCP system | `extensions_config.json` → `mcpServers` | Add each as a stdio/http server (see §5.1) |
| **hermes** (`hermes acp`) | ACP agents | `config.yaml` → `acp_agents` | Config-only: `hermes: {command: hermes, args: [acp]}` (see §5.2) |
| **ironclaw** (`nearai/ironclaw`) | ACP agents | `config.yaml` → `acp_agents` | Needs thin ACP adapter (mirrors `@zed-industries/codex-acp`); see §5.3 |
| **OfficeCLI** (`officecli mcp`) | MCP system | `extensions_config.json` → `mcpServers` | Config-only (see §5.4) |
| **OpenWiki** (`openwiki --update`) | Scheduled tasks | `config.yaml` → `scheduled_tasks` | Cron job (see §5.5) |
| Sylvie persona | Custom agent | `SOUL.md` + `config.yaml` → `agents` | Port `SOUL_Sylvie_v1.0.md` content into a deer-flow custom agent's `SOUL.md` |
| NDA / VC-PE / due-diligence skill skeletons | Skills | `skills/public/<name>/SKILL.md` | Port each skeleton as a `SKILL.md` with YAML frontmatter |
| 3-tier model routing (Main/Mid/Low) | Model factory | `config.yaml` → `models` | Map to deer-flow's model factory (local vLLM + BYOK cloud) |
| Daily cron (DD pipeline, regulation sync) | Scheduled tasks | `config.yaml` → `scheduled_tasks` | `schedule_type: cron` |

## 5. Draft configs (copy into deer-flow repo)

### 5.1 `extensions_config.json` — legal MCP servers + OfficeCLI

> Pull connector details (URLs, auth) from
> `pacgate-ai/assets/百宸初建方案文件/清单类文件/百宸AI系统资源接入清单.md`
> and credentials from `pacgate-ai/assets/智库资料收集/智库资料收集/MCP授权/法律数据库MCP.md`.

```json
{
  "mcpServers": {
    "yuandian": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@yuandian/mcp-server"],
      "env": { "YUANDIAN_API_KEY": "$YUANDIAN_API_KEY" },
      "description": "元典开放平台 — 法律幻觉核验、法规检索、企业信息"
    },
    "pkulaw": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@pkulaw/mcp-law-search"],
      "env": { "PKULAW_BEARER_TOKEN": "$PKULAW_BEARER_TOKEN" },
      "description": "北大法宝 — 法规语义检索、司法案例"
    },
    "qcc": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@qcc/mcp-server"],
      "env": { "QCC_APP_KEY": "$QCC_APP_KEY", "QCC_SECRET_KEY": "$QCC_SECRET_KEY" },
      "description": "企查查 — 工商、股东、司法涉诉、经营风险（尽调数据）"
    },
    "courtlistener": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@courtlistener/mcp-server"],
      "env": { "COURTLISTENER_API_KEY": "$COURTLISTENER_API_KEY" },
      "description": "CourtListener — US case law (cross-border matters)"
    },
    "officecli": {
      "enabled": true,
      "type": "stdio",
      "command": "officecli",
      "args": ["mcp"],
      "description": "Word/Excel/PPT automation for due-diligence reports"
    }
  },
  "skills": {}
}
```
> ⚠ The exact npm package names above are placeholders — verify each connector's
> actual install command in `百宸AI系统资源接入清单.md` before deploying. Some legal
> MCP servers may be HTTP/SSE type, not stdio.

### 5.2 `config.yaml` — ACP agents (hermes by default, ironclaw via adapter)

```yaml
acp_agents:
  hermes:
    command: hermes
    args: ["acp"]
    description: "NousResearch hermes-agent — self-improving agent (ACP server)"
    # env: {}  # hermes reads its own config (~/.hermes/)
  ironclaw:
    # ironclaw has no native ACP-server mode; point this at a thin ACP adapter
    # you write (mirrors @zed-industries/codex-acp). Until that adapter exists,
    # leave this commented out.
    # command: ironclaw-acp
    # args: []
    # description: "nearai/ironclaw Agent OS (via ACP adapter)"
```

### 5.3 ironclaw ACP adapter (one-time custom work)

ironclaw (`nearai/ironclaw`) is an MCP *client* / Agent OS — it does NOT expose an
ACP server. To call it from deer-flow's `invoke_acp_agent`, write a thin wrapper:

1. Create `ironclaw-acp` — a small script (Python or Node) that:
   - Speaks ACP stdio JSON-RPC (use `agent-client-protocol` SDK, same as hermes)
   - On each ACP `prompt`, shells out to `ironclaw` CLI with the prompt
   - Streams `item/*` events back as ACP messages
2. Reference the pattern: `@zed-industries/codex-acp` wraps the `codex` CLI the same way.
3. Add to `acp_agents.ironclaw` (uncomment §5.2) once the adapter exists.

**Alternative**: run ironclaw standalone and let *it* consume deer-flow's MCP servers
(ironclaw is an MCP client via `ironclaw mcp add <name> --transport stdio`). This avoids
the adapter but means ironclaw is a separate process, not a deer-flow subagent.

### 5.4 OfficeCLI — already in `extensions_config.json` (§5.1)

No extra config. `officecli mcp` is a stdio MCP server; deer-flow spawns it and
exposes its tools (read/edit/merge/render docx/xlsx/pptx) to the lead agent.
Install OfficeCLI on the box first: download the single binary from
`github.com/iOfficeAI/OfficeCLI/releases`, or `officecli install` for one-step setup.

### 5.5 `config.yaml` — scheduled tasks (OpenWiki + daily legal cron)

```yaml
scheduler:
  enabled: true

scheduled_tasks:
  - name: openwiki-regen
    schedule_type: cron
    schedule_spec:
      cron: "0 3 * * *"        # nightly 03:00
      timezone: Asia/Shanghai
    prompt: "Run `openwiki --update` in the pacgate-law repo to regenerate the knowledge-base wiki, then summarize any new/changed docs."
    # The agent uses its bash tool to run openwiki; output lands in openwiki/ for read_file

  - name: regulation-sync
    schedule_type: cron
    schedule_spec:
      cron: "0 6 * * *"        # daily 06:00
      timezone: Asia/Shanghai
    prompt: "Use the pkulaw and yuandian MCP tools to check for newly-published PRC regulations relevant to open due-diligence matters; append a summary to the matter workspace."
```
> Exact `scheduled_tasks` schema fields (e.g. `prompt` vs `message`, `schedule_spec`
> shape) — verify against deer-flow's `backend/app/gateway/routers/scheduled_tasks.py`
> and `deerflow.scheduler.schedules` when you clone the repo.

## 6. Step-by-step: from here to a running deer-flow

1. **Clone deer-flow** into a new folder (e.g. `~/deer-flow` or a new VS Code workspace).
2. **Copy configs**: `cp config.example.yaml config.yaml`; `cp extensions_config.example.json extensions_config.json`.
3. **Edit `extensions_config.json`** — paste §5.1 (legal MCP + OfficeCLI). Fill env vars from `法律数据库MCP.md`.
4. **Edit `config.yaml`** — paste §5.2 (hermes ACP agent). Add §5.5 scheduled tasks.
5. **Install OfficeCLI** on the box (single binary; `officecli install`).
6. **Install OpenWiki**: `npm install -g openwiki` (use npm/pnpm, not bun, on Windows).
7. **Verify hermes**: `hermes acp --help` (should start ACP stdio server).
8. **Port skills**: copy NDA / VC-PE / due-diligence skeletons from §3.1 into
   `deer-flow/skills/public/<name>/SKILL.md` with YAML frontmatter (name, description,
   license, allowed-tools, required-secrets).
9. **Port persona**: create a deer-flow custom agent; set its `SOUL.md` from
   `SOUL_Sylvie_v1.0.md`.
10. **Map models**: in `config.yaml` → `models`, define Main/Mid/Low tiers
    (local vLLM for Mid/Low, BYOK cloud for Main).
11. **Start**: `make dev` (or `docker compose up`).
12. **Test**: invoke the lead agent; confirm MCP tools (pkulaw, qcc, officecli) appear;
    confirm `invoke_acp_agent` with `hermes` works.

## 7. Open items / risks

- **ironclaw ACP adapter** — the only custom code required. Unavoidable in any workspace
  (ironclaw has no ACP-server mode). Estimate: ~1 day mirroring codex-acp.
- **Legal MCP package names** — §5.1 uses placeholder npm names; verify real install
  commands in `百宸AI系统资源接入清单.md`. Some may be HTTP/SSE, not stdio.
- **Credentials** — `法律数据库MCP.md` has plaintext passwords and is NOT gitignored.
  Move secrets to deer-flow's env/secrets store; never commit.
- **Windows box quirks** — Python full path (`C:\Program Files\Python313\python.exe`),
  PowerShell `npx` wrap (`cmd.exe /c`), UTF-8 encoding care, legacy `--headless` Chrome.
  See `AGENTS.md` → Environment.
- **deer-flow scheduled_tasks schema** — verify exact field names against the repo when cloned.