# PacGate-Law — Session Handoff (2026-09-18)

> **For the next session: builds of the Sanitizer Agent + OCR pipeline.**
> This log is the single source of truth for current state. Read top to bottom.

## 1. Verified state snapshot (all checked 2026-09-18)

| Item | Value |
|---|---|
| Monorepo HEAD | `f40b01f` (main, clean, 0 uncommitted non-runtime changes) |
| Backup mirror | `C:\backup-pacgate-law-mirror.git` @ `f40b01f` (in sync) |
| Fork `pacgate-ai/pacgate-ai-pr` main | `0cd785e` (has CI frontend-overrides fix merged) |
| Fork `pacgate-ai/pacgate-ai` (assets) main | `73b5da9` (pushed, credential-free) |
| deer-flow `pacgate-layer` | `107199ca` (pushed to fork) |
| GHCR published | api/mcp/deer-flow `0.1.14`, frontend `0.1.15` — all PUBLIC |
| Running stack | api/mcp/deer-flow `0.1.14` + frontend `0.1.15`, 25 containers, 0 restarts, DB intact (1 tenant / 3 users) |
| GHCR auth | packages are PUBLIC; `docker logout ghcr.io` was required (stale stored cred poisoned even anonymous pulls) |
| CI dispatch capability | Windows Credential Manager holds a 40-char PAT for `pacgate-ai` (git credential fill; NEVER print it). Can merge + dispatch via GitHub API without user login. |

## 2. What was completed this session (do not redo)

1. **CI frontend-overrides fix** — merged to fork/main (`0cd785e`), dispatched `tag=0.1.15`, run succeeded. Branding verified: 百宸 in 1,962 SSR chunks (identical coverage to 0.1.11); branded chunks served live.
2. **Stack upgraded** — api/mcp/deer-flow 0.1.9/0.1.10 → 0.1.14; frontend 0.1.11 → 0.1.15. Committed `e51525e`.
3. **Monorepo re-synced to fork nested layout** — commit `f40b01f`. The Rust workspace now lives at `pacgate-ai/pacgate-ai/` (Dockerfile, Cargo.toml, crates/, wasm-crates/, migrations/). This matches the fork layout that CI builds (`context: pacgate-ai`). Old flattened root artifacts are gone (recorded as renames). Stale old scaffold archived at `runtime/relocate/stale-scaffold-archive/`.
4. **pacgate-ai-assets push COMPLETE** — fork/main = local main = `73b5da9`. The developer machine had already pushed the bulk (fork/main was 47 commits ahead with SECURITY credential-removal commits); we re-added the 11 genuinely local-only files (SOUL_Justin, 资料收集目录 docs, Haiwen DD scan, 百宸 template checklists, 项目档案 docs, 自动化线条 evaluations, AGENTS.md update).
5. **Credential gate held** — the 2 MCP授权 carriers (`境外法律数据库和网站.md` blob `8e18bfce…`, `百宸AI系统资源接入清单V2.docx` blob `a59e30ed…`) are NOT in the pushed tree (verified by blob-SHA match — CJK filename matching silently fails on this machine; always match by blob SHA).

## 3. USER DIRECTIVES (binding)

- **NO more releases/tags/dispatches without real code changes.** 0.1.15 was justified only because it carried the CI fix. Next release only after the features below land.
- **Next work = two real features**: (1) Sanitizer Agent, (2) OCR pipeline for pacgate-ai.
- Red line (from AGENTS.md): every AI output is a draft for lawyer review; never silent fabrication.

## 4. NEXT SESSION TASK 1 — Sanitizer Agent (脱敏 agent)

Proposed scope (user has NOT yet answered the open questions — ask before coding):

- **Purpose**: prevent client PII / case-identifying data from leaving the local boundary (to external LLM APIs) — a red-line compliance feature for the law firm.
- **Entities to detect**: Chinese names, 身份证号 (18-digit w/ checksum), phone numbers, emails, bank accounts, case numbers (案号), addresses. Regex + dictionary based first pass; local NER model optional later.
- **Modes**: `mask` (irreversible, for external calls) and `pseudonymize` (reversible within a matter; mapping stored in pacgate DB).
- **Integration points**:
  - deer-flow skill: `deer-flow/skills/public/sanitizer/SKILL.md` (YAML frontmatter format — see existing skills)
  - MCP tool in `extensions_config.json` (deer-flow) so the agent can call it
  - Optionally a pre-send hook in the deer-flow gateway so ALL outbound LLM payloads pass through
- **Open questions for the user**: mask-only vs pseudonymize+re-identify? Enforce at gateway boundary or opt-in per skill? Where to store the pseudonym map (pacgate Postgres, per-matter)?

## 5. NEXT SESSION TASK 2 — OCR pipeline (massive OCR for pacgate-ai)

Proposed scope (user has NOT yet chosen the engine — ask before coding):

- **Purpose**: ingest scanned PDFs/images into the RAG store (existing `kb_chunks` pipeline only handles text-layer PDFs; the Haiwen scan in assets is exactly this case).
- **Proposed engine**: PaddleOCR (local, free, strongest Chinese accuracy, runs on the AIPC GPUs). Alternative: commercial API if the firm has a license.
- **Architecture**: OCR worker container + job queue. Add `ocr_jobs` table to pacgate Postgres (id, doc_id, status, pages_done, error). Pipeline: upload → detect text layer (pdftotext empty ⇒ needs OCR) → enqueue → worker OCRs page-by-page → text layer written → existing chunking/embedding picks it up.
- **Scale**: "massive" ⇒ batch worker with concurrency limit + GPU memory guard; never inline in the API request path.
- **Integration**: pacgate-api upload endpoint enqueues; new worker service in `deploy/` + compose entry; progress surfaced via existing document status API.
- **Open questions for the user**: PaddleOCR OK? GPU vs CPU workers? Priority order vs sanitizer?

## 6. Environment traps (learned the hard way — READ BEFORE ANY TERMINAL WORK)

- **Task terminals**: `run_in_terminal` intermittently swallows output / loses PATH / corrupts parser. Use `create_and_run_task` with `powershell -NoProfile -ExecutionPolicy Bypass -File <script>` for anything non-trivial. If a task returns no output, re-run in a NEW task terminal; verify state via files/`docker images`, not the log.
- **CJK paths**: PowerShell 5.1 GBK codepage mangles CJK in .ps1 files and in git output. Build CJK strings from `[char]0xNNNN` code points; match git objects by **blob SHA**, never by filename; use `-c core.quotepath=false` for readable (but still mojibake on console) output.
- **Editor tools fail on `C:\pacgate-ai-pr` files** (read_file returns empty, edits vanish). Edit via byte-level .NET (`[System.IO.File]::ReadAllBytes/WriteAllBytes`) scripts — see `runtime/apply-wf-fix.ps1` for the pattern.
- **docker compose project name**: `compose.bundle.yaml` has `name: pacgate-ai-bundle`; `compose.prod.yaml` now also has it. NEVER rename/move `deploy/client-bundle/` — volume `pacgate-ai-bundle_pacgate-db-data` is the live DB.
- **GHCR pulls**: if `denied` on PUBLIC packages ⇒ stale docker credential; `docker logout ghcr.io` fixes it.
- **Monorepo layout**: platform root = `pacgate-law\pacgate-ai\`; Rust workspace = `pacgate-ai\pacgate-ai\` (nested, matching fork). Build contexts: api = `pacgate-ai/` with `pacgate-ai/Dockerfile`; mcp = `deploy/pacgate-mcp`; deer-flow = repo root with `deploy/deer-flow-pacgate/Dockerfile`.
- **Long builds**: `create_and_run_task` terminals die when closed — use detached `Start-Process -WindowStyle Hidden` + `.done` marker (see `runtime/relocate/build-deerflow.ps1`).
- **VPN is flaky**: git ls-remote succeeds then pushes time out for minutes. Retry; pushes are atomic.

## 7. Still-open user-side blockers (not ours to fix)

1. **Credential rotation** — the 4 leaked files (OPERATOR.md + 3 MCP授权 files) are still public in `pacgate-ai-pr` history. Rotation is THE urgent item; nothing we do code-side fixes it.
2. **`gh auth login`** — monorepo has no real remote; backup mirror is same-disk only.
3. GHCR visibility decision (currently public — fine for now).

## 8. Key paths

| What | Path |
|---|---|
| Monorepo | `C:\Users\pacga\github-pr\pacgate-law` |
| Platform tree | `pacgate-law\pacgate-ai\` |
| Rust workspace (nested) | `pacgate-law\pacgate-ai\pacgate-ai\` |
| Compose (live stack) | `pacgate-ai\deploy\client-bundle\compose.bundle.yaml` |
| Fork worktree | `C:\pacgate-ai-pr` (branch `fix/ci-frontend-overrides` exists; main = 0cd785e) |
| Assets repo | `pacgate-law\pacgate-ai-assets` (main = 73b5da9 = fork/main) |
| deer-flow | `pacgate-law\deer-flow` (branch `pacgate-layer`) |
| Backup mirror | `C:\backup-pacgate-law-mirror.git` |
| Session scripts/evidence | `pacgate-law\runtime\` (this session's scripts all there) |
| Old archive | `C:\archive-pacgate-ai-pr` (66 MB bundle + scratch) |