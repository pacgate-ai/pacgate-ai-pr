# AIPC #2 Handoff Prompt — PacGate Full-Stack Setup

> Copy everything below into a fresh agent session on **AIPC #2**. This is a
> self-contained setup prompt. It assumes AIPC #2 is a fresh Windows machine
> (Docker Desktop, Ollama, Node.js 24+ installed) and that you have the
> `pacgate-ai` GitHub credentials available.

---

## Mission

Set up the complete PacGate AI stack on this machine (AIPC #2), identical to
AIPC #1, using the **updated** code that carries all the 2026-09-02 fixes.

## Critical: clone from the fork, not the old repo

The `pacgate-ai` account **cannot write** to `JZKK720/pacgate-ai-pr` (403, needs
2FA grant). The fixes live on the **`pacgate-ai/pacgate-ai-pr`** fork, which the
`pacgate-ai` account owns. **Clone from there:**

```powershell
cd C:\
git clone https://github.com/pacgate-ai/pacgate-ai-pr.git
cd pacgate-ai-pr
```

Verify you have the fixes — the handbook should be v0.1.3 and contain a
"Significant findings" section:
```powershell
Select-String -Path deploy\AIPC-DEPLOYMENT-HANDBOOK.md -Pattern "0.1.3|Significant findings"
```

If you must use `JZKK720/pacgate-ai-pr`, pull the `feat/deer-flow-pacgate-mcp`
branch (or `git am` the patches in `patches/`) to get the same fixes.

## The 6 fixes you MUST have (from the handbook)

1. **pacgate-mcp** — a new FastMCP service so the deer-flow agent can query
   pacgate's legal DBs (`pacgate_kb_search`, `pacgate_connector_search`,
   `pacgate_list_connectors`). Registered in `deer-flow-extensions-config.json`.
2. **openviking key fix** — `deer-flow-extensions-config.json` must use
   `OPENVIKING_ROOT_API_KEY` (not `OPENVIKING_API_KEY`). Wrong key → openviking
   401 → **no MCP tools load at all**.
3. **deer-flow recreate warning** — never `--force-recreate` deer-flow (wipes its
   local DB + admin user). Use `docker compose restart deer-flow`.
4. **QM uses Resend** — `AUTH_EMAIL_TRANSPORT=resend`, needs `RESEND_API_KEY`.
5. **QM web-ui can't self-auth** — always reach it via the portal (`:8181`).
6. **Git push via fork** — push to `pacgate-ai/pacgate-ai-pr`, not `JZKK720`.

## Setup steps (follow the handbook)

### Stage 2 — core stack
```powershell
cd C:\pacgate-ai-pr\deploy\client-bundle
copy .env.example .env
notepad .env
```
Fill in: `PACGATE_DB_PASSWORD`, `PACGATE_JWT_SECRET`, `PACGATE_TENANT_ID=pacgate-law`,
`OPENVIKING_ROOT_API_KEY`, `OPENVIKING_API_KEY` (generate 32-hex each). Then:
```powershell
.\install.ps1
docker compose -f compose.prod.yaml ps
curl http://localhost:8081/health
```
Expected: 5 containers up, `/health` returns `ok`.

### Stage 3 — seed tenant + users
```powershell
docker exec pacgate-db psql -U pacgate -c "INSERT INTO tenants (name, slug) VALUES ('Pacgate Law', 'pacgate-law');"
$body = @{email="admin@pacgate-law.com"; password="<strong-password>"} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8081/api/auth/register" -Method POST -Body $body -ContentType "application/json"
$body = @{email="qm-bridge@pacgate.local"; password="<strong-bridge-password>"} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8081/api/auth/register" -Method POST -Body $body -ContentType "application/json"
```

### Stage 4 — QM (needs a Resend key)
```powershell
cd C:\pacgate-ai-pr\deploy\client-bundle
.\setup-qm.ps1
```
Then set `RESEND_API_KEY` in `deploy/qm-pacgate/.env` (a secret — type it in the
terminal yourself, never via the agent). Also set `AUTH_EMAIL_FROM` to a
Resend-verified sender (or `onboarding@resend.dev` for testing). Then:
```powershell
cd C:\pacgate-ai-pr\deploy\qm-pacgate
node_modules\.bin\qm.cmd up
```
> Use `node_modules\.bin\qm.cmd up` — `npm exec qm -- up` is blocked by the
> PowerShell execution policy.

### Stage 5 — verify deer-flow
```powershell
# Open http://localhost:8081/research/
# Ask: "Summarize recent force majeure case law in China"
# Verify: response includes citations + is saved to matter memory
```

## Verify the pacgate-mcp wiring (the key new feature)

After the stack is up, confirm the deer-flow agent can query pacgate's legal DBs:
```powershell
docker logs deer-flow --since=5m | Select-String "Configured MCP server: pacgate|Successfully loaded"
```
Expected: `Configured MCP server: pacgate` and `Successfully loaded N tool(s)`.
Then in the deer-flow chat, ask: "用你连接的法律数据库搜索 force majeure 判例" —
the agent should call `pacgate_connector_search` and return real case law.

## Environment gotchas (Windows AIPC)

- `python` is NOT in PATH — use `C:\Program Files\Python313\python.exe`.
- PowerShell blocks `.ps1`/`npm.ps1` — wrap in `cmd.exe /c "..."` or use
  `node_modules\.bin\qm.cmd`.
- Chinese Windows defaults to GBK — never `Get-Content`/`Set-Content` on UTF-8
  Chinese files (mojibake). Use `[System.IO.File]::ReadAllBytes`/`WriteAllBytes`.
- Headless Chrome: use legacy `--headless` (not `--headless=new`, which crashes).
- ollama.com downloads are blocked on this box — use on-board models only
  (ornith-1.5:9b default, already in `deer-flow-config.yaml`).

## When done

Report: (1) all 5 core containers healthy, (2) deer-flow agent can query pacgate
legal DBs, (3) QM portal sign-in works (or note the Resend key is still needed).
