## Task 2: Generic placeholder substitution in `install.ps1`

**Files:**
- Modify: `pacgate-ai/deploy/client-bundle/install.ps1:434` (the `.Replace` call)
- Modify: `pacgate-ai/deploy/client-bundle/install.ps1:471` (the `$knownServers` list)

**Interfaces:**
- Consumes: the 7 placeholder names from Task 1.
- Produces: a rendered `deer-flow-extensions-config.json` with all placeholders substituted, plus a non-fatal warning listing any that were not.

- [ ] **Step 1: Replace the single-key substitution with a generic pass**

In `pacgate-ai/deploy/client-bundle/install.ps1`, find this exact line (L434):

```powershell
            $df = (Get-Content $dfTemplate -Raw -Encoding UTF8).Replace('${OPENVIKING_ROOT_API_KEY}', $dfKey)
```

Replace it with:

```powershell
            # Generic placeholder pass: substitute EVERY ${VAR} the template
            # declares, from .env. Previously only OPENVIKING_ROOT_API_KEY was
            # replaced, so the 27 legal-database connectors could not be
            # templated at all - they lived only in the rendered (gitignored)
            # file, and a fresh machine got 3 servers instead of 30.
            #
            # .Replace() is a LITERAL string replace, so a value containing '$'
            # is safe (unlike -replace, which would treat it as a regex).
            $df = Get-Content $dfTemplate -Raw -Encoding UTF8
            foreach ($k in $envVars.Keys) {
                $df = $df.Replace('${' + $k + '}', [string]$envVars[$k])
            }

            # Report any placeholder left unsubstituted. NOT fatal: a missing
            # connector key must degrade to "fewer sources", never fail the
            # install. OPENVIKING_ROOT_API_KEY is guarded above and cannot
            # reach here unset.
            $leftover = [regex]::Matches($df, '\$\{[A-Z_]+\}') |
                ForEach-Object { $_.Value } | Sort-Object -Unique
            if ($leftover.Count -gt 0) {
                Write-Host "[WARN] Unsubstituted placeholders in $dfRendered - these connectors will be skipped:" -ForegroundColor Yellow
                Write-Host "       $($leftover -join ', ')" -ForegroundColor Yellow
                Write-Host "       Set them in .env to enable the corresponding connectors." -ForegroundColor Yellow
            }
```

- [ ] **Step 2: Expand the change-reporting server list**

Find this exact line (L471):

```powershell
                $knownServers = @('openviking', 'pacgate', 'firecrawl')
```

Replace it with:

```powershell
                # All 30 servers, so a gained/lost connector is always named.
                # The previous 3-entry list could not report a change to any of
                # the 27 legal-database connectors - which is how pacgate-mcp
                # went missing unnoticed.
                $knownServers = @(
                    'openviking', 'pacgate', 'firecrawl', 'officecli',
                    'yuandian-law', 'yuandian-case', 'yuandian-company', 'yuandian-securities',
                    'pkulaw-law-search', 'pkulaw-law-keyword', 'pkulaw-case-semantic-search',
                    'pkulaw-case-keyword', 'pkulaw-law-item-keyword', 'pkulaw-law-recognition',
                    'pkulaw-case-number-recognition', 'pkulaw-citation-validator', 'pkulaw-doc-link',
                    'qcc-company', 'qcc-risk', 'qcc-ipr', 'qcc-operation', 'qcc-history',
                    'qcc-executive', 'qcc-legal-regulation', 'qcc-legal-case', 'qcc-tender',
                    'qcc-document', 'qcc-document-mcp',
                    'vaquill', 'ansvar'
                )
```

- [ ] **Step 3: Verify the script still parses**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$err = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path "pacgate-ai\deploy\client-bundle\install.ps1").Path, [ref]$null, [ref]$err) | Out-Null
if ($err.Count -eq 0) { Write-Output "PARSE OK" } else { $err | ForEach-Object { Write-Output $_.Message } }
```

Expected: `PARSE OK`

- [ ] **Step 4: Test the substitution logic in isolation (positive case)**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$tpl = [System.IO.File]::ReadAllText((Resolve-Path "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.template.json"), [System.Text.Encoding]::UTF8)
$envVars = @{
  OPENVIKING_ROOT_API_KEY = 'test-ov-key'
  FIRECRAWL_API_KEY       = 'test-fc-key'
  YUANDIAN_API_KEY        = 'test-yd-key'
  PKULAW_API_KEY          = 'test-pk-key'
  QCC_API_KEY             = 'test-qcc-key'
  VAQUILL_API_KEY         = 'test-vq-key'
  ANSVAR_API_KEY          = 'test-an-key'
}
$df = $tpl
foreach ($k in $envVars.Keys) { $df = $df.Replace('${' + $k + '}', [string]$envVars[$k]) }
$leftover = [regex]::Matches($df, '\$\{[A-Z_]+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
Write-Output ("leftover: " + $(if ($leftover) { $leftover -join ", " } else { "NONE" }))
$j = $df | ConvertFrom-Json
Write-Output ("servers: " + ($j.mcpServers.PSObject.Properties | Measure-Object).Count)
Write-Output ("vaquill url: " + $j.mcpServers.vaquill.url)
Write-Output ("pkulaw auth: " + $j.mcpServers.'pkulaw-law-search'.headers.Authorization)
```

Expected:
```
leftover: NONE
servers: 30
vaquill url: https://mcp.vaquill.ai/s/test-vq-key
pkulaw auth: Bearer test-pk-key
```

- [ ] **Step 5: Test the failure path (negative control)**

This is the check that matters — a bare "30 servers" proves nothing about what happens when a key is missing.

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$tpl = [System.IO.File]::ReadAllText((Resolve-Path "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.template.json"), [System.Text.Encoding]::UTF8)
# Deliberately omit PKULAW_API_KEY and QCC_API_KEY
$envVars = @{
  OPENVIKING_ROOT_API_KEY = 'test-ov-key'
  FIRECRAWL_API_KEY       = 'test-fc-key'
  YUANDIAN_API_KEY        = 'test-yd-key'
  VAQUILL_API_KEY         = 'test-vq-key'
  ANSVAR_API_KEY          = 'test-an-key'
}
$df = $tpl
foreach ($k in $envVars.Keys) { $df = $df.Replace('${' + $k + '}', [string]$envVars[$k]) }
$leftover = [regex]::Matches($df, '\$\{[A-Z_]+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
Write-Output ("leftover: " + ($leftover -join ", "))
Write-Output ("still valid JSON: " + $(try { $null = $df | ConvertFrom-Json; "YES" } catch { "NO" }))
```

Expected:
```
leftover: ${PKULAW_API_KEY}, ${QCC_API_KEY}
still valid JSON: YES
```

The install must **warn and continue**, not exit. Confirm the code path: the `$leftover` block uses `Write-Host`, never `exit`.

- [ ] **Step 6: Commit**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add pacgate-ai/deploy/client-bundle/install.ps1
git commit -m "fix(install): substitute every \${VAR} placeholder, not just OpenViking's

install.ps1 replaced only \${OPENVIKING_ROOT_API_KEY}, so no other connector
could be templated. Now every \${VAR} the template declares is substituted
from .env, and any placeholder left unsubstituted is reported as a warning.

Deliberately non-fatal: a missing connector key must degrade to 'fewer
sources', never fail the install. OPENVIKING_ROOT_API_KEY stays mandatory
because a missing value breaks deer-flow memory recall (OV-2a).

Also expands the gained/lost reporting list from 3 servers to all 30, so a
connector change is always named - the 3-entry list is how pacgate-mcp went
missing unnoticed."
```

---
