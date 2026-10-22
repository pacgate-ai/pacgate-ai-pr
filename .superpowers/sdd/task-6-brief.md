## Task 6: Merge PR#1 on JZKK720/deer-flow (EXTERNAL — cannot be done from this machine)

**Files:** none (remote action).

**Interfaces:**
- Produces: `JZKK720/deer-flow` main at 142 skill files, which Task 4's `SKILLS_REF: main` depends on.

- [ ] **Step 1: Confirm PR#1 is still open and mergeable**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File runtime\check-pr1-1016.ps1
```

Expected: PR#1 open, `mergeable_state` clean or unstable (CI pending).

- [ ] **Step 2: Hand off to the developer**

Our PAT has `push=False` on `JZKK720/*`, so this cannot be merged from here. Send the developer:

> PR#1 on `JZKK720/deer-flow` (`pacgate-ai:pacgate-layer-fixes-2026-10 → main`) needs merging. It carries 3 skills absent from main (`antitrust-compliance`, `arbitration`, `bankruptcy-restructuring`) plus the prefix-aware `tool_policy.py` fix. The v0.1.32 build's `SKILLS_REF` points at `main`, so the release needs this merged first.

- [ ] **Step 3: If the merge stalls, pin the fork SHA instead**

Change `SKILLS_REF` in `build-ghcr.yml` from `main` to `19021f7f` and change `SKILLS_REPO` to `https://github.com/pacgate-ai/deer-flow.git`. This unblocks the release; re-point to `main` after the merge.

- [ ] **Step 4: Verify after merge**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\deer-flow
git fetch origin --quiet
Write-Output ("origin/main skills/public files: " + (git ls-tree -r --name-only origin/main -- skills/public | Measure-Object -Line).Lines)
```

Expected: `142`

---
