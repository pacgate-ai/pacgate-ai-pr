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
## Correction: the stack runs the PUBLISHED images, and the deltas are a PR

An earlier revision of this record described a locally built `pacgate-api`. That
was wrong and has been reverted. A local build is invisible to upstream and
unmaintainable, and it defeats the point of pinning to GHCR.

The stack now runs the published image, verified by digest:

    running : sha256:a154813306724ce9445c37e8f5dceafac8aadfc0e1135b81d1371ac42bfcbf4b
    GHCR    : sha256:a154813306724ce9445c37e8f5dceafac8aadfc0e1135b81d1371ac42bfcbf4b

The four deltas that were in the local build are now a PR against `fork/main`:

    branch  pr/0.2.35-upstream-fixes  (3 commits, 4 files, +141/-8)
    https://github.com/pacgate-ai/pacgate-ai-pr/pull/new/pr/0.2.35-upstream-fixes

  1. `fix(docker)` - re-declare PAC_SOURCE_REVISION in the runtime stage
  2. `fix(rag)`    - label sanitized chunks with the job's data_level
  3. `feat(api)`   - report extraction completeness on /sanitize-status

### The noise.rs place-name delta was dropped as redundant

It was a symptom fix for the class `9f0e0c8` fixed at the root. Verified on the
STOCK published image:

    上海市浦东新区   verdict=pass
    北京市朝阳区     verdict=pass
    广州市天河区     verdict=pass   <- never covered by our suffix rule
    杭州市西湖区     verdict=pass   <- never covered by our suffix rule

and it is STRICTER, not looser: a document with a place name AND real
identifiers redacts all five spans (both locations, person, ID, phone).

### Final delta set: 14 files

4 are in the PR (upstream needs them). 10 are local-only gate/config fixes
upstream does not need: 7 gate fixes, 3 patch mounts, install.ps1 tenant-role
repair.