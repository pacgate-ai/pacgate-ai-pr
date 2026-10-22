## Task 5: Push the missing patch

**Files:**
- Add to upstream: `deploy/client-bundle/patches/deer-flow-uploads-middleware.py`

**Interfaces:**
- Consumes: nothing.
- Produces: upstream `patches/` at 18 files.

- [ ] **Step 1: Confirm the patch is genuinely missing upstream**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$local = git ls-files pacgate-ai/deploy/client-bundle/patches | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
$up = git ls-tree -r --name-only upstream/main -- deploy/client-bundle/patches | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object
Write-Output "--- local only ---"
Compare-Object $local $up | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { Write-Output ("  " + $_.InputObject) }
Write-Output ("local: " + $local.Count + "  upstream: " + $up.Count)
```

Expected: `deer-flow-uploads-middleware.py` listed as local-only; `local: 18  upstream: 17`.

- [ ] **Step 2: Confirm it is mounted (so it is a real dependency, not dead code)**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
Select-String -Path "pacgate-ai\deploy\client-bundle\compose.bundle.yaml" -Pattern "uploads-middleware" -Encoding UTF8 |
  ForEach-Object { Write-Output ("L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
```

Expected: one mount line mapping it to `.../middlewares/uploads_middleware.py`.

- [ ] **Step 3: Create the push script**

Create `runtime/push-patch-1016.ps1`:

```powershell
$ErrorActionPreference = "Stop"
$root = "c:\Users\pacga\github-pr\pacgate-law"
$rel  = "pacgate-ai/deploy/client-bundle/patches/deer-flow-uploads-middleware.py"
$upRel = "deploy/client-bundle/patches/deer-flow-uploads-middleware.py"

# PAT from Windows Credential Manager (never printed)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "git"; $psi.Arguments = "credential fill"
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine("protocol=https"); $p.StandardInput.WriteLine("host=github.com")
$p.StandardInput.WriteLine(""); $p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
$pat = $null
foreach ($l in ($out -split "`n")) { if ($l -match '^password=(.+)$') { $pat = $Matches[1].Trim() } }
if (-not $pat) { throw "no PAT" }

# LF-normalize: the worktree is CRLF, upstream is LF. Without this the diff
# becomes whole-file noise.
$text = [System.IO.File]::ReadAllText((Join-Path $root $rel), [System.Text.Encoding]::UTF8)
$text = $text -replace "`r`n", "`n"
$b64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))

$h = @{ Authorization = "Bearer $pat"; Accept = "application/vnd.github+json"; "User-Agent" = "pacgate-push" }
$uri = "https://api.github.com/repos/pacgate-ai/pacgate-ai-pr/contents/$upRel"

# Need the existing blob SHA if the file already exists (update vs create)
$sha = $null
try {
  $cur = Invoke-RestMethod -Uri "$uri`?ref=main" -Headers $h -Method Get
  $sha = $cur.sha
  Write-Output "existing file, sha=$sha"
} catch { Write-Output "new file" }

$body = @{
  message = "fix(patches): add deer-flow-uploads-middleware.py

Mounted in compose.bundle.yaml but absent from upstream patches/ (17 vs 18),
so a fresh deploy would mount a non-existent file and the uploads middleware
override would silently not apply."
  content = $b64
  branch  = "main"
}
if ($sha) { $body.sha = $sha }

$json = $body | ConvertTo-Json -Depth 5
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$resp = Invoke-RestMethod -Uri $uri -Headers $h -Method Put -Body $bytes -ContentType "application/json; charset=utf-8"
Write-Output ("pushed: " + $resp.commit.sha)
```

- [ ] **Step 4: Run the push script**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
powershell -NoProfile -ExecutionPolicy Bypass -File runtime\push-patch-1016.ps1
```

git-over-HTTPS is unreliable on this machine; the Contents API works. The script reads the file, LF-normalizes it, base64-encodes it, and PUTs it to `pacgate-ai/pacgate-ai-pr` on `main`.

Expected: HTTP 200/201 with a commit SHA printed.

- [ ] **Step 5: Verify the push landed**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
git fetch fork --quiet
Write-Output ("fork/main patches: " + (git ls-tree -r --name-only fork/main -- deploy/client-bundle/patches | Measure-Object -Line).Lines)
```

Expected: `18`

- [ ] **Step 6: Commit the script**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add runtime/push-patch-1016.ps1
git commit -m "chore(runtime): script to push the missing uploads-middleware patch"
```

---
