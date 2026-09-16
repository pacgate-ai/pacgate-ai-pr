# Volume investigation findings (read-only)

**Date**: 2026-09-16
**Method**: each volume mounted `:ro` into a throwaway `nginx:1.27-alpine`
container and inspected. Nothing was written, moved, or deleted.

## Result: the orphan is NOT stale — it is the original, and still real

| | `pacgate-ai-bundle_pacgate-db-data` | `client-bundle_pacgate-db-data` |
|---|---|---|
| Size | **95.5 MB** | 46.6 MB |
| `PG_VERSION` | 16 | 16 |
| Created | 2026-09-02 | 2026-09-01 |
| Newest WAL segment | **Sep 15 02:49** | Sep 2 05:04 |
| Newest `base/` dir mtime | **Sep 15 02:44** | Sep 1 07:37 |
| WAL entries | 4 | 2 |
| Attached to | ✅ `pacgate-db` (live) | ❌ nobody |
| PGDATA ownership | uid 999 | uid 70 |

## Interpretation

- **`pacgate-ai-bundle_` is authoritative.** It is attached, larger, and its newest
  writes are **2026-09-15** — i.e. yesterday, matching a live database.
- **`client-bundle_` is an abandoned first generation**, last written **2026-09-01**.
  It is not empty, so it must not be deleted without review, but it is ~2 weeks stale
  and corresponds to the first install before the project name changed.
- Different PGDATA uids (70 vs 999) confirm they were initialised by **different
  container definitions**, consistent with the two different compose files.

## Why this matters

This is direct evidence that the **project-name change already happened once**:

1. 2026-09-01 — stack first brought up via `compose.prod.yaml` (no `name:` → project
   taken from the directory `client-bundle`) → volume `client-bundle_pacgate-db-data`.
2. 2026-09-02 — stack brought up again via `compose.bundle.yaml`
   (`name: pacgate-ai-bundle`) → a **second, empty** volume
   `pacgate-ai-bundle_pacgate-db-data` was created, and the app started writing there.

The old data was never lost, but the application moved to a fresh empty database —
which is exactly why this class of bug "looks like data loss".

## Consequences for the consolidation plan

1. **Do NOT delete either volume.** The orphan holds 46.6 MB of real 2026-09-01 state.
2. **Do NOT rename or move `deploy/client-bundle/`.** That would create a *third*
   generation and repeat this failure.
3. **Fix `compose.prod.yaml`** by adding `name: pacgate-ai-bundle` so both compose
   files resolve to the same project — and therefore the same volume.
4. Before applying that fix, confirm no client data exists *only* in the 2026-09-01
   generation. If it does, copy it across with a read-only source mount before switching.
5. If the September-1 data is confirmed obsolete, retire that volume deliberately
   (`docker volume rm client-bundle_pacgate-db-data`) — as a recorded decision, not
   as cleanup.

## Reproduce

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "c:\Users\pacga\github-pr\pacgate-law\runtime\compare-volume-mtime.ps1"
```

Raw output: `runtime/volume-mtime.txt`, `runtime/volume-contents-investigation.txt`.
