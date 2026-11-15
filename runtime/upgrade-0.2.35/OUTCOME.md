# 0.2.34 -> 0.2.35 upgrade outcome

Measured 2026-11-16 on AIPC1.

## Release

- tag `v0.2.35` peels to `2924798cb44a3dd66bf08d2ecfde8b78f351f872`
- all six images carry that revision (verified against GHCR, not inferred)
- unlike 0.2.33, whose images were built from `d636174` before the egress fix

## Superseded local deltas (dropped)

| Upstream | What it fixes | Our delta it replaces |
|---|---|---|
| `9f0e0c8` | `verify()` no longer lets a `MatchSource::Model` span block on its own | The `PUBLIC_ENTITIES` place-name patch was a SYMPTOM fix for exactly this. The root fix is now upstream. |
| `4670c87`, `0f9ed04` | the two extraction gates assert the 0.2.33 contract themselves | Our rewrites of `test-empty-extraction-gate.ps1` and `test-text-native-sanitize.ps1` |

The `noise.rs` patch is KEPT as belt-and-braces — it costs nothing and keeps
`上海市` out of residue — but it is no longer load-bearing.

## Surviving local deltas

- `ingest.rs` — `reingest_sanitized_chunks_at` (data_level propagation)
- `sanitize.rs` / `extract.rs` — `extraction_incomplete` on `/sanitize-status`
- `Dockerfile` — runtime-stage `PAC_SOURCE_REVISION`
- `install.ps1` — tenant-role repair
- 3 patch mounts in both compose files (A5 parity)
- 6 gate fixes (see the plan's delta table)

## Data

| | before | after |
|---|---|---|
| documents | 276 | 276 |
| matters | 65 | 65 |
| users | 5 | 5 |
| kb_chunks | 5599 | 5602 |
| audit_log | 2001 | 2015 |

No new migrations between 0.2.34 and 0.2.35, so the schema is unchanged.
`kb_chunks` +3 and `audit_log` +14 are the re-chunk and the sanitize jobs.

## Re-sanitize (mandatory — 0.2.35 is inert without it)

The verdict is computed at sanitize time and STORED, so a green stack can still
hold documents blocked by the old rule.

| | before | after |
|---|---|---|
| blocked documents | 7 | 1 |
| blocked chunks | 67 | 19 |
| sanitized documents | 49 | 55 |

6 reopened, 46 chunks promoted. The one that stays blocked is CORRECT: its
ledger names "1 surviving structural match(es) - a rule the redactor found and
left in place" — residue `2026-0001` is a BankAccount pattern match, i.e.
structural evidence, which is supposed to block and needs a human. Its 3
model-only matches (`杭州`, `杭州市A区劳动人事争议仲裁委员会`) are correctly
non-blocking now.

## Round trips proven

- sanitizer e2e: PASS (22 checks)
- format coverage: 48 passed, 0 failed — every accepted format survives
  upload -> extract -> sanitize -> convert
- full legal journey: PASSED, 20 assertions, all lanes verified
  (matter -> upload -> OCR/extract -> sanitize -> review gate -> search ->
   deer-flow sign-in -> qm co-work -> OpenViking write/recall)
- T4 hold: PASS (16 assertions)
- lane connectivity: 11 passed, 0 not reachable (incl. qm -> openviking /mcp)
- agent MCP e2e: 9 passed, 0 failed (a real agent run invoked an MCP tool)
- place-name probe: verdict=pass, 3 redactions, `上海市浦东新区` kept verbatim

## Defect found and fixed during the upgrade

`test-agent-mcp-e2e.ps1` parsed the extensions config with `Get-Content -Raw`.
On chcp 936 that decodes UTF-8 as GBK, and `"检索"` became `"妫€绱?` — the
closing quote swallowed by a multi-byte character's trailing byte. The gate
reported CANNOT CHECK on a valid config, silently skipping the whole agent MCP
proof. Fixed with `[System.IO.File]::ReadAllText`.

## Rollback

- git: `pre-sync-0.2.35`
- db: `runtime/upgrade-0.2.35/db-backup.sql` (62.1 MB, gitignored, NOT committed)
- runtime: retag the 0.2.34 images, then
  `docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api deer-flow deer-flow-frontend pacgate-mcp ocr-service`

The database needs no rollback: no migrations ran.