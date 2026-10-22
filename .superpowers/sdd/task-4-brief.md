## Task 4: Bake the skills tree into the deer-flow image

**Files:**
- Modify: `pacgate-ai/deploy/deer-flow-pacgate/Dockerfile` (add `COPY` after the adapter install)
- Modify: `pacgate-ai/.github/workflows/build-ghcr.yml` (add clone step before the deer-flow-pacgate build)
- Modify: `pacgate-ai/deploy/client-bundle/compose.bundle.yaml:202-207` (comment out the mount)
- Modify: `pacgate-ai/deploy/client-bundle/compose.prod.yaml` (comment out the mount)
- Modify: `pacgate-ai/.gitignore` (ignore the CI-generated dir)

**Interfaces:**
- Consumes: `JZKK720/deer-flow` at a ref containing 60 skill dirs (see Task 6 ordering note).
- Produces: an image with `/app/skills/public` containing 60 directories.

- [ ] **Step 1: Add the COPY to the Dockerfile**

In `pacgate-ai/deploy/deer-flow-pacgate/Dockerfile`, find:

```dockerfile
# Install the adapter package globally and also expose the copied source tree on
# PYTHONPATH, because DeerFlow itself runs from /app/backend via `uv run --no-sync`.
RUN pip install --no-cache-dir /app/adapters/pacgate_deerflow_adapter
```

Insert immediately after it:

```dockerfile
# Pacgate: bake the skills tree so a fresh deploy gets all 60 skills without a
# sibling deer-flow clone. The compose mount (../../../deer-flow/skills/public)
# is MONO-FOLDER-ONLY - a fresh upstream deploy has no such sibling, so the
# mount resolves to nothing and the agent gets ZERO skills. Verified 2026-10-16:
# `docker run --rm --entrypoint sh <0.1.31 image> -c "ls /app/skills/public | wc -l"`
# returned 0.
#
# The source tree is populated by CI (build-ghcr.yml, "Clone deer-flow skills
# source") and is gitignored - it is a build input, not tracked content.
COPY deploy/deer-flow-pacgate/skills/public /app/skills/public
```

- [ ] **Step 2: Add the CI clone step**

In `pacgate-ai/.github/workflows/build-ghcr.yml`, find:

```yaml
      # ── deer-flow-pacgate (backend + adapter) ────────────────────────────
      - name: Build & push deer-flow-pacgate
```

Insert immediately before it:

```yaml
      # Bake the skills tree into the deer-flow image. The compose mount is a
      # mono-folder-only relative path, so a fresh upstream deploy would get
      # ZERO skills. Cloning here makes the image self-contained.
      #
      # SKILLS_REF must resolve to a ref that CONTAINS the 3 skills added in
      # pacgate-ai/deer-flow@19021f7f (antitrust-compliance, arbitration,
      # bankruptcy-restructuring). JZKK720/deer-flow main has 139 skill files;
      # the fork branch has 142. Point this at main once PR#1 is merged, or at
      # the fork SHA as a fallback so a release is never blocked.
      - name: Clone deer-flow skills source
        env:
          SKILLS_REPO: https://github.com/JZKK720/deer-flow.git
          SKILLS_REF: main
        run: |
          git clone --filter=blob:none --no-checkout "$SKILLS_REPO" deploy/deer-flow-skills-src
          git -C deploy/deer-flow-skills-src sparse-checkout set skills/public
          git -C deploy/deer-flow-skills-src checkout "$SKILLS_REF"
          if [ ! -d deploy/deer-flow-skills-src/skills/public ]; then
            echo "::error::skills/public missing at $SKILLS_REF in $SKILLS_REPO"
            exit 1
          fi
          mkdir -p deploy/deer-flow-pacgate/skills
          cp -rv deploy/deer-flow-skills-src/skills/public deploy/deer-flow-pacgate/skills/public
          n=$(ls deploy/deer-flow-pacgate/skills/public | wc -l)
          echo "Baked skill dirs: $n"
          if [ "$n" -lt 60 ]; then
            echo "::error::Expected 60 skill dirs, got $n. SKILLS_REF=$SKILLS_REF may predate the 3 skills added in 19021f7f."
            exit 1
          fi
```

- [ ] **Step 3: Add a post-build assertion to the manifest verification step**

In the same file, find:

```yaml
          for img in pacgate-api pacgate-mcp ocr-service deer-flow-pacgate deer-flow-frontend-pacgate; do
```

Leave it unchanged. Instead, add a new step immediately after the whole `Verify image manifest (anonymous HEAD)` step:

```yaml
      # Assert the skills actually landed in the image. The manifest check above
      # proves the image EXISTS; it says nothing about its contents. Without
      # this, a COPY that silently matched nothing would ship a skill-less
      # image and every downstream signal would still be green.
      - name: Verify skills baked into deer-flow-pacgate
        run: |
          PREFIX="${{ steps.ns.outputs.prefix }}"
          TAG="${{ steps.tag.outputs.tag }}"
          docker pull "$PREFIX/deer-flow-pacgate:$TAG"
          n=$(docker run --rm --entrypoint sh "$PREFIX/deer-flow-pacgate:$TAG" \
                -c "ls /app/skills/public 2>/dev/null | wc -l")
          echo "Skills in image: $n"
          if [ "$n" -lt 60 ]; then
            echo "::error::deer-flow-pacgate:$TAG has $n skill dirs, expected 60."
            exit 1
          fi
```

- [ ] **Step 4: Demote the compose mount to a commented dev override**

In `pacgate-ai/deploy/client-bundle/compose.bundle.yaml`, find:

```yaml
      # Pacgate 2026-10-08 (re-applied 2026-10-15 after 0.1.31 sync): serve the
      # skills tree (60 dirs: 37 PacGate legal + 23 upstream) from the merged
      # pacgate-layer working copy. MONO-FOLDER-ONLY: fresh upstream deploys
      # have no sibling deer-flow clone. The 0.1.31 image still has no
      # /app/skills baked in - keep this mount until an image carries it.
      - ../../../deer-flow/skills/public:/app/skills/public:ro
```

Replace it with:

```yaml
      # Pacgate 2026-10-16: the skills tree is now BAKED INTO the image
      # (deploy/deer-flow-pacgate/Dockerfile), so a fresh deploy gets all 60
      # skills from `docker compose pull` alone. This mount is DEMOTED to a
      # dev-only override: uncomment it to edit skills live without rebuilding.
      #
      # Do NOT leave it enabled in a release. The mount wins at runtime, so a
      # stale image would look correct on a machine that has the sibling clone
      # and broken on one that does not - a silent divergence.
      #
      # - ../../../deer-flow/skills/public:/app/skills/public:ro
```

- [ ] **Step 5: Apply the same change to `compose.prod.yaml`**

Find the equivalent skills mount in `pacgate-ai/deploy/client-bundle/compose.prod.yaml` and apply the identical comment-out. Verify it exists first:

```powershell
cd c:\Users\pacga\github-pr\pacgate-law
Select-String -Path "pacgate-ai\deploy\client-bundle\compose.prod.yaml" -Pattern "skills/public" -Encoding UTF8 |
  ForEach-Object { Write-Output ("L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
```

Expected: one match, the mount line. Comment it out with the same explanatory block.

- [ ] **Step 6: Ignore the CI-generated skills dir**

Append to `pacgate-ai/.gitignore`:

```
# CI-generated build input for the deer-flow image (see build-ghcr.yml,
# "Clone deer-flow skills source"). Populated at build time, never committed.
deploy/deer-flow-pacgate/skills/
deploy/deer-flow-skills-src/
```

- [ ] **Step 7: Verify both compose files still validate**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml config --quiet; Write-Output ("bundle exit: " + $LASTEXITCODE)
docker compose -f compose.prod.yaml config --quiet; Write-Output ("prod exit: " + $LASTEXITCODE)
docker compose -f compose.prod.yaml config | Select-String "^name:"
```

Expected: both exit `0`, and `name: pacgate-ai-bundle` is present (the volume-safety pin must survive).

- [ ] **Step 8: Verify the mount is gone from the running config**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml config | Select-String "skills"
```

Expected: **no output** (the mount is commented out).

- [ ] **Step 9: Commit**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add pacgate-ai/deploy/deer-flow-pacgate/Dockerfile \
        pacgate-ai/.github/workflows/build-ghcr.yml \
        pacgate-ai/deploy/client-bundle/compose.bundle.yaml \
        pacgate-ai/deploy/client-bundle/compose.prod.yaml \
        pacgate-ai/.gitignore
git commit -m "feat(skills): bake the skills tree into the deer-flow image

The image baked 0 skills and the compose mount was a mono-folder-only
relative path (../../../deer-flow/skills/public), so a fresh upstream
deploy got ZERO skills - verified: 'ls /app/skills/public | wc -l' on the
0.1.31 image returned 0.

CI now clones JZKK720/deer-flow at SKILLS_REF, copies skills/public into the
build context, and the Dockerfile COPYs it to /app/skills/public. A
post-build step asserts >=60 dirs in the published image, because the
manifest check only proves the image exists, not what is in it.

The compose mount is demoted to a commented dev override. Leaving it active
would let the mount win at runtime, so a stale image would look correct on a
machine with the sibling clone and broken on one without."
```

---
