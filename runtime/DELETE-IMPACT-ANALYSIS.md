# Can `C:\pacgate-ai-pr` be deleted safely?

**Question asked**: *"if we delete and clear this path `C:\pacgate-ai-pr`, everything
will survive and run perfectly with our current local repo and docker containers
structures?"*

**Answer**: **No.** Deleting it would immediately orphan the host data of 5 containers,
leave 14 containers without working `docker compose` control, and permanently destroy
1,635 MB of untracked client conversation history that exists nowhere else.

**Date**: 2026-09-16 · **Method**: empirical inspection of the live Docker daemon
(nothing was modified).

---

## 1. Why not — three independent failure modes

### Failure mode 1: 19 bind mounts stop resolving across 5 containers

Every one of these is a **host path under `C:\pacgate-ai-pr`**, not a Docker volume.
Delete the directory and the mount source vanishes.

> **Tested empirically** (throwaway container + throwaway directory, no real data):
> the container **keeps running** and still reports `Up` in `docker ps`, but the
> mount becomes completely unreadable:
>
> ```
> phase 1 (source exists):  read /data/marker.txt -> "hello"
> phase 2 (source deleted): container still running: true
> phase 3 (re-read):        ls: /data: No such file or directory
> phase 5 (app's own log):  OK / OK / FAIL / FAIL
> ```
>
> **This is worse than a crash.** A crash is loud and visible. Here the container
> looks healthy in `docker ps` while the application has silently lost its data
> directory and its config files. See `runtime/bindmount-deletion-experiment.txt`.

| Container | Dependent mounts from `C:\pacgate-ai-pr\...` |
|---|---|
| `deer-flow` | **13 mounts** — 3 directories (`./data`, `workflows/`, `data/deer-flow`) and **10 individual files** (`deer-flow-config.yaml`, `deer-flow-extensions-config.json`, and 8 files under `patches/`) |
| `qm-pacgate-core-1` | 3 — `sandbox/skills`, `sandbox/tools`, `patch/pi-models.ts` |
| `pacgate-api` | 1 — `deploy/client-bundle/data` → `/data` |
| `openviking` | 1 — `deploy/client-bundle/openviking` → `/app/.openviking` |
| `pacgate-nginx` | 1 — `deploy/client-bundle/nginx/default.conf` |

**19 dependent bind mounts in total across 5 containers.**

Note that `deer-flow` mounts **10 individual patch/config files** *over* files inside
the image (`/app/backend/app/gateway/routers/*.py`, `.../lead_agent/agent.py`,
`.../langchain_mcp_adapters/tools.py`, etc.). Those files exist **only on the host** —
they are not baked into the image. Deleting the directory removes the patch source,
and the container silently loses the behaviour those files provide.

### Failure mode 2: irreplaceable untracked data

The Postgres **named volumes** live inside the Docker VM
(`/var/lib/docker/volumes/...`) and are *not* affected. But two services store their
live state on the **host filesystem** instead:

| Path | Size | What it is |
|---|---|---|
| `client-bundle/data/deer-flow/checkpoints.db` | **1,635 MB** | Live LangGraph conversation checkpoints |
| `client-bundle/data/deer-flow/data/deerflow.db` | 0.81 MB | Admin password hash, threads, users |
| `client-bundle/data/` (whole tree) | 1,915 MB / 244 files | Client conversation workspace |
| `client-bundle/openviking/` | 9 MB / 145 files | OpenViking runtime state |
| `deploy/qm-pacgate/` | 1.3 MB (131 of 162 files ignored) | qm runtime state |

**None of this is in git** — it is deliberately gitignored as client data, and
therefore recoverable from *nowhere*. Deleting the directory deletes the only copy.

### Failure mode 3: `docker compose` loses its footing

Docker records the config path used at `up` time. Both projects point inside the
directory:

```
pacgate-ai-bundle -> C:\pacgate-ai-pr\deploy\client-bundle\compose.bundle.yaml
qm-pacgate       -> C:\pacgate-ai-pr\deploy\qm-pacgate\compose.qm.yaml
```

With the files gone, `docker compose down`, `up`, `config`, and `logs <service>`
all fail until the stack is re-pointed at a new location.

---

## 2. What WOULD survive

Being precise about this matters, because it identifies what is *not* at risk:

- ✅ **Named Postgres volumes** — `pacgate-ai-bundle_pacgate-db-data` (95.5 MB),
  `qm-pacgate-pgdata`, `qm-pacgate-coredata`, and the odysseus/hermes/dockhand
  volumes. These live in the Docker VM, unaffected by a host directory deletion.
- ✅ **The 23.8 MB tracked source** — recoverable from the GitHub remotes
  (`JZKK720/pacgate-ai-pr`, `pacgate-ai/pacgate-ai-pr`).
- ✅ **Container images** — already pulled; they live in the Docker image store.

So the danger is *not* the code and *not* the databases. It is the **1.9 GB of
untracked host-side client data** and the **19 live bind mounts**.

---

## 3. Affected containers (14)

**Immediately orphaned** — these bind-mount host paths and lose their data/config
the moment the directory is gone (5 containers, 19 mounts):

```
deer-flow              qm-pacgate-core-1      pacgate-api
openviking             pacgate-nginx
```

**Lose `docker compose` control** — containers keep running briefly, but `down`,
`up`, `config`, and `logs <service>` fail because the recorded config file is gone
(14 containers total, being the 5 above plus those below):

```
deer-flow-frontend     pacgate-db             pacgate-mcp
qm-pacgate-admin-1     qm-pacgate-auth-1      qm-pacgate-mailpit-1
qm-pacgate-pg-1        qm-pacgate-portal-1    qm-pacgate-web-ui-1
```

---

## 4. The correct order

**Never delete first.** The safe sequence is:

1. **Stop the stack** (`docker compose -f <file> down`) — not delete.
2. **Copy** everything the stack needs from `C:\pacgate-ai-pr` into the mono-repo,
   preserving relative layout so the `./data`, `./patches` bind mounts still resolve:
   - the tracked 23.8 MB (via `git archive`, never `cp -r`)
   - **plus** the untracked-but-required host state: `client-bundle/data/`,
     `client-bundle/openviking/`, `qm-pacgate/` runtime files
3. **Re-point** the stack at the new location and confirm it starts.
4. **Verify** against the checklist in the consolidation plan §8.
5. Only then retire `C:\pacgate-ai-pr` — and even then, **archive it** rather than
   deleting outright, so the 158 commits of history remain queryable.

> ⚠️ **Additional trap**: because `compose.prod.yaml` has no `name:` key, the
> Compose project name derives from the **directory name**. Moving
> `deploy/client-bundle/` changes the project name and therefore creates a **new,
> empty** `pacgate-db-data` volume. Fix that (plan §3 / Phase 1) *before* moving
> anything, or the migration will look like data loss.

---

## 5. Summary

| Question | Answer |
|---|---|
| Will containers keep running? | ⚠️ **They stay `Up` — but silently lose all data access.** Worse than crashing, because `docker ps` still looks healthy. |
| Will client conversation history survive? | ❌ No — 1,635 MB exists only here |
| Will the Postgres databases survive? | ✅ Yes — they live in the Docker VM |
| Will the source code survive? | ✅ Yes — recoverable from GitHub |
| Can we delete first and fix later? | ❌ No — the data is unrecoverable |

**Bottom line: migrate first, verify, then archive — never delete first.**

---

*Evidence*: `runtime/delete-impact-bindmounts.txt`, `runtime/delete-impact-full.txt`,
`runtime/delete-impact-verdict.txt`, `runtime/delete-impact-counts.txt`,
`runtime/bindmount-deletion-experiment.txt`
*Reproduce*: `runtime/test-delete-impact.ps1`,
`runtime/assess-delete-impact-full.ps1`, `runtime/experiment-bindmount-delete.ps1`
*Related*: `docs/superpowers/specs/2026-09-16-mono-stack-delivery-plan.md`
