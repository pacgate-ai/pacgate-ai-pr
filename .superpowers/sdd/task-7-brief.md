## Task 7: Release v0.1.32 and verify end to end

**Files:**
- Modify: `pacgate-ai/deploy/client-bundle/compose.bundle.yaml` (5 image pins)
- Modify: `pacgate-ai/deploy/client-bundle/compose.prod.yaml` (5 image pins)
- Modify: `pacgate-ai/pacgate-ai/Cargo.toml` (workspace version)

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a running 0.1.32 stack with 30 connectors and 60 skills.

- [ ] **Step 1: Bump the version pins**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File runtime\bump-0132-1016.ps1
```

Create `runtime/bump-0132-1016.ps1` first:

```powershell
$ErrorActionPreference = "Stop"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$files = @(
  "pacgate-ai\deploy\client-bundle\compose.bundle.yaml",
  "pacgate-ai\deploy\client-bundle\compose.prod.yaml"
)
foreach ($f in $files) {
  $p = Join-Path $root $f
  $t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $before = ([regex]::Matches($t, 'jzkk720/[a-z-]+:0\.1\.31')).Count
  $t = $t -replace '(jzkk720/[a-z-]+:)0\.1\.31', '${1}0.1.32'
  [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("$f : $before pins bumped")
}
# Cargo workspace version
$c = Join-Path $root "pacgate-ai\pacgate-ai\Cargo.toml"
$ct = [System.IO.File]::ReadAllText($c, [System.Text.Encoding]::UTF8)
$ct = $ct -replace '(?m)^version = "0\.1\.31"', 'version = "0.1.32"'
[System.IO.File]::WriteAllText($c, $ct, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Cargo.toml bumped"
```

Expected: `5 pins bumped` for each compose file.

- [ ] **Step 2: Verify the pins**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
Select-String -Path "pacgate-ai\deploy\client-bundle\compose.bundle.yaml" -Pattern "image:\s*ghcr" -Encoding UTF8 |
  ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
```

Expected: all 5 pins read `0.1.32`; the openviking digest pin is unchanged.

- [ ] **Step 3: Commit and push to fork**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add pacgate-ai/deploy/client-bundle/compose.bundle.yaml \
        pacgate-ai/deploy/client-bundle/compose.prod.yaml \
        pacgate-ai/pacgate-ai/Cargo.toml
git commit -m "chore(release): bump pins to 0.1.32"
```

Then push the accumulated commits to fork/main via the Contents API (git-over-HTTPS is unreliable here) and open a PR to `JZKK720/pacgate-ai-pr`.

- [ ] **Step 4: Dispatch the build**

After the PR merges on JZKK720, dispatch:

```
POST /repos/JZKK720/pacgate-ai-pr/actions/workflows/build-ghcr.yml/dispatches
{ "ref": "main", "inputs": { "tag": "0.1.32" } }
```

Expected: run succeeds; the `Verify skills baked into deer-flow-pacgate` step reports `Skills in image: 60`.

- [ ] **Step 5: Pull and recreate**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle
docker compose -f compose.bundle.yaml pull
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api pacgate-mcp deer-flow deer-flow-frontend ocr-service
```

Expected: 5 containers recreated, 0 restarts. `pacgate-db`, `nginx`, `openviking` untouched.

- [ ] **Step 6: Verify the skills are in the running container**

Run:
```powershell
docker exec deer-flow sh -c "ls /app/skills/public | wc -l"
```

Expected: `60`

- [ ] **Step 7: Verify the connector count end to end**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$j = Get-Content "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Output ("servers: " + ($j.mcpServers.PSObject.Properties | Measure-Object).Count)
Write-Output ("enabled: " + ($j.mcpServers.PSObject.Properties | Where-Object { $_.Value.enabled -eq $true } | Measure-Object).Count)
Write-Output ("leftover placeholders: " + ([regex]::Matches((Get-Content "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.json" -Raw -Encoding UTF8), '\$\{[A-Z_]+\}')).Count)
```

Expected: `servers: 30`, `enabled: 18`, `leftover placeholders: 0`

- [ ] **Step 8: Verify the MCP tools load**

Run:
```powershell
docker exec deer-flow sh -c "grep -c 'mcp' /app/backend/config.yaml" 2>$null
docker logs deer-flow --tail 100 2>&1 | Select-String -Pattern "MCP|tool" | Select-Object -First 20
```

Expected: no MCP load errors; the tool count is at or above the pre-change baseline (137+).

- [ ] **Step 9: Verify the stack is healthy**

Run:
```powershell
docker ps --format "{{.Names}}`t{{.Image}}`t{{.Status}}" | Sort-Object
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select (select count(*) from tenants) as tenants, (select count(*) from users) as users;"
```

Expected: all containers `Up`, 0 restarts; DB intact (tenants/users unchanged from the pre-release baseline).

- [ ] **Step 10: Commit the release notes**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add runtime/
git commit -m "docs(release): v0.1.32 verification results"
```

---
