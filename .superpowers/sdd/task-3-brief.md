## Task 3: Add the 6 connector keys to `.env.example`

**Files:**
- Modify: `pacgate-ai/deploy/client-bundle/.env.example` (the "Data source connectors" section, ~L88-102)

**Interfaces:**
- Consumes: the 6 non-OpenViking placeholder names from Task 1.
- Produces: a documented key set matching what Task 2 substitutes.

- [ ] **Step 1: Replace the connector section**

In `pacgate-ai/deploy/client-bundle/.env.example`, find this exact block:

```
# === Data source connectors (optional) ===
# Uncomment and fill in only the connectors you need. Without keys, external
# legal search returns fewer sources; core functionality is unaffected.
# See deploy/AIPC-DEPLOYMENT-HANDBOOK.md "Known limitations".

# China-law search (regenerate token at https://mcp.pkulaw.com)
#PKULAW_API_KEY=

# US legal research
#VAQUILL_API_KEY=

# EU compliance MCP
#ANSVAR_API_KEY=

# Offshore corporate registry
#OPENCORPORATES_API_KEY=
```

Replace it with:

```
# === Data source connectors (optional) ===
# Fill in only the connectors you need. Without a key, that connector is
# SKIPPED and install.ps1 prints a warning naming it - external legal search
# returns fewer sources, but core functionality is unaffected and the install
# still succeeds. See deploy/AIPC-DEPLOYMENT-HANDBOOK.md "Known limitations".
#
# These names must match the ${...} placeholders in
# deer-flow-extensions-config.template.json. A key set here but absent from
# the template is inert; a placeholder in the template with no key here is
# reported as unsubstituted.

# 元典 (yuandian) - 4 connectors: law / case / company / securities
# https://open.chineselaw.com
YUANDIAN_API_KEY=

# 北大法宝 (pkulaw) - 9 connectors: law/case search, keyword, recognition,
# citation validation, doc linking. Regenerate at https://mcp.pkulaw.com
PKULAW_API_KEY=

# 企查查 (qcc) - 11 connectors: company, risk, ipr, operation, history,
# executive, regulation, case, tender, document. Disabled by default in the
# template; set the key AND flip "enabled" to true to use them.
QCC_API_KEY=

# Firecrawl - web scraping / search / crawl (stdio MCP server)
FIRECRAWL_API_KEY=

# Vaquill - US legal research. NOTE: this key is embedded in the URL path,
# not sent as a header, so the template templates the whole URL.
VAQUILL_API_KEY=

# Ansvar - EU compliance MCP. Disabled by default in the template.
ANSVAR_API_KEY=
```

- [ ] **Step 2: Verify the key set matches the template placeholders**

Run:
```powershell
cd c:\Users\pacga\github-pr\pacgate-law
$tpl = [System.IO.File]::ReadAllText((Resolve-Path "pacgate-ai\deploy\client-bundle\deer-flow-extensions-config.template.json"), [System.Text.Encoding]::UTF8)
$tplKeys = [regex]::Matches($tpl, '\$\{([A-Z_]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$envKeys = Get-Content "pacgate-ai\deploy\client-bundle\.env.example" -Encoding UTF8 |
  Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=' } |
  ForEach-Object { ($_ -split '=')[0].Trim() } | Sort-Object -Unique
Write-Output "--- template placeholders with NO .env.example key ---"
$missing = Compare-Object $tplKeys $envKeys | Where-Object { $_.SideIndicator -eq '<=' }
if ($missing) { $missing | ForEach-Object { Write-Output ("  " + $_.InputObject) } } else { Write-Output "  none" }
```

Expected: `none` — every template placeholder has a documented key.

- [ ] **Step 3: Commit**

```bash
cd c:/Users/pacga/github-pr/pacgate-law
git add pacgate-ai/deploy/client-bundle/.env.example
git commit -m "docs(env): document the 6 connector keys the template now requires

The template declares 7 placeholders; only OPENVIKING_ROOT_API_KEY was
documented. Adds YUANDIAN/PKULAW/QCC/FIRECRAWL/VAQUILL/ANSVAR with the
connector counts and the vaquill URL-embedding caveat.

Drops OPENCORPORATES_API_KEY (no connector references it) and does not add
COURTLISTENER_API_KEY / FYOPEN_API_KEY, which are set in the live .env but
referenced by no connector - dead keys."
```

---
