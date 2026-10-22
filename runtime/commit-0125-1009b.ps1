# Commit the 0.1.25 delta adoption + E2E report — 2026-10-09
$ErrorActionPreference = "Continue"
$env:Path += ";C:\Program Files\Git\cmd"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$out = @()

# 1. Stage the adopted delta files + E2E report
$files = @(
    "pacgate-ai/scripts/ov-mcp-call.ps1",
    "pacgate-ai/scripts/test-legal-journey.ps1",
    "pacgate-ai/.gitignore",
    "pacgate-ai/safe_markdown_to_pdf.py",
    "pacgate-ai/deploy/RUNBOOK-clean-clone-proof.md",
    "pacgate-ai/deploy/BENCHMARK-REPORT-2026-10-09-v0.1.25.md",
    "pacgate-ai/deploy/client-bundle/compose.bundle.yaml",
    "runtime/E2E-REPORT-0.1.25-20261009.md"
)
foreach ($f in $files) {
    $p = "$w\$f"
    if (Test-Path $p) {
        git -C $w add $f 2>&1 | Out-Null
        $out += "staged: $f"
    } else { $out += "MISSING: $f" }
}

# 2. Credential gate before commit (blob-SHA method, codepage-proof)
$out += ""
$out += "=== CREDENTIAL GATE ==="
$carriers = @("5855e649","8e18bfce","a59e30ed")
$staged = git -C $w diff --cached --name-only
$out += "staged files: $($staged.Count)"
$blobs = git -C $w ls-files -s $staged 2>$null
$hits = $blobs | Select-String -Pattern ($carriers -join "|")
if ($hits) { $out += "GATE FAIL: carrier blobs staged!"; $out += $hits } else { $out += "GATE PASS: 0 carrier blobs in staged tree" }

# 3. Commit
$out += ""
$out += "=== COMMIT ==="
$out += git -C $w status --porcelain --untracked-files=no 2>&1 | Select-Object -First 15
$commitMsg = "sync(upstream): adopt v0.1.25 post-tag delta (efaeb50f) + E2E upgrade report"
$out += git -C $w commit -m $commitMsg 2>&1 | Select-Object -First 5
$out += "HEAD now: $(git -C $w rev-parse --short HEAD)"

$out | Out-File -FilePath "$w\runtime\commit-0125-1009b.txt" -Encoding utf8
Write-Output "DONE"
