<#
.SYNOPSIS
    Fail if any secret from client-bundle/.env appears verbatim in a text file
    under the agent-readable data tree.

.DESCRIPTION
    deploy/client-bundle/data/ is bind-mounted into deer-flow at /data, and the
    sandbox is LocalSandboxProvider with allow_host_bash, so the agent can read
    every file there with plain `grep`. On 2026-11-08 an API token and five
    passwords were found in plaintext in that tree (see
    runtime/SECURITY-2026-11-08-redaction/REMEDIATION.md).

    Every other gate inspects code and config. None of them looked at the data
    tree the agent can actually read, which is how the leak survived.

    Reports the FILE and the KEY NAME. Never prints a secret value.

.PARAMETER EnvFile
    The .env to source secrets from.

.PARAMETER DataDir
    The data tree to scan.

.PARAMETER MinLength
    Ignore values shorter than this, so `true`, `changeme`, port numbers and
    other non-secrets do not produce noise.
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$DataDir,
    [int]$MinLength = 16
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $EnvFile) { $EnvFile = Join-Path $repoRoot 'deploy/client-bundle/.env' }
if (-not $DataDir) { $DataDir = Join-Path $repoRoot 'deploy/client-bundle/data' }

$pass = 0
$fail = 0
function Pass($m) { $script:pass++; Write-Host "  [PASS] $m" -ForegroundColor Green }
function Fail($m) { $script:fail++; Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Skip($m) { Write-Host "  [SKIP] $m" -ForegroundColor Yellow }

Write-Host '=== no .env secret appears verbatim in the agent-readable data tree ===' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Skip "env file not found at $EnvFile; cannot check."
    Write-Host 'RESULT: SKIP - no .env to source secrets from.' -ForegroundColor Yellow
    exit 0
}
if (-not (Test-Path -LiteralPath $DataDir)) {
    Skip "data dir not found at $DataDir; cannot check."
    Write-Host 'RESULT: SKIP - no mounted data tree.' -ForegroundColor Yellow
    exit 0
}

# --- collect candidate secrets -------------------------------------------------
# Machine-usable credentials only. Human-login passwords live in the operator
# docs and are a separate, known, documented exposure (REMEDIATION.md).
$secretKeys = @(
    'PACGATE_DB_PASSWORD', 'PACGATE_JWT_SECRET', 'PACGATE_API_PASSWORD',
    'OPENVIKING_ROOT_API_KEY', 'OPENVIKING_API_KEY',
    'YUANDIAN_API_KEY', 'PKULAW_API_KEY', 'QCC_API_KEY', 'FYOPEN_API_KEY',
    'COURTLISTENER_API_KEY', 'VAQUILL_API_KEY', 'ANSVAR_API_KEY', 'FIRECRAWL_API_KEY'
)

$secrets = @{}
foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k = ($line -split '=', 2)[0].Trim()
    $v = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if ($k -notin $secretKeys) { continue }
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    if ($v.Length -lt $MinLength) { continue }
    $secrets[$k] = $v
}

if ($secrets.Count -eq 0) {
    Skip "no candidate secrets >= $MinLength chars in $EnvFile."
    Write-Host 'RESULT: SKIP - nothing to scan for.' -ForegroundColor Yellow
    exit 0
}
Pass "sourced $($secrets.Count) secret(s) from .env (values never printed)"

# --- scan ---------------------------------------------------------------------
$exts = @('.md', '.txt', '.json', '.yaml', '.yml', '.csv', '.log', '.xml', '.html')
$scanned = 0
$hits = @()

foreach ($f in Get-ChildItem -LiteralPath $DataDir -Recurse -File -ErrorAction SilentlyContinue) {
    if ($f.Extension -notin $exts) { continue }
    if ($f.Length -gt 2MB) { continue }
    $scanned++
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f.FullName))
    foreach ($k in $secrets.Keys) {
        if ($text.Contains($secrets[$k])) {
            $hits += [pscustomobject]@{
                Key  = $k
                File = $f.FullName.Substring($DataDir.Length).TrimStart('\', '/')
            }
        }
    }
}
Pass "scanned $scanned text file(s) under $([System.IO.Path]::GetFileName($DataDir))"

if ($hits.Count -eq 0) {
    Pass 'no secret value found in the data tree'
} else {
    foreach ($h in $hits) {
        Fail "$($h.Key) appears verbatim in $($h.File)"
    }
    Write-Host ''
    Write-Host '  An agent can read /data with plain grep. Move the value into .env and' -ForegroundColor Yellow
    Write-Host '  reference it by name. See runtime/SECURITY-2026-11-08-redaction/.' -ForegroundColor Yellow
}

# --- also assert the known credential docs are redacted -----------------------
$redacted = 0
$bad = 0
foreach ($f in Get-ChildItem -LiteralPath $DataDir -Recurse -File -Filter '*境外法律数据库和网站*.md' -ErrorAction SilentlyContinue) {
    $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f.FullName))
    foreach ($m in [regex]::Matches($t, '(?i)(?:密码|口令|password|passwd)\s*[:：]\s*(\S+)')) {
        if ($m.Groups[1].Value -like '<REDACTED*') { $redacted++ } else { $bad++ }
    }
}
if ($bad -eq 0) {
    Pass "credential docs carry $redacted redacted password field(s), 0 plaintext"
} else {
    Fail "$bad plaintext password field(s) remain in the credential docs"
}

# --- and assert the KB ingester refuses those files ---------------------------
# Redaction stops the CURRENT content leaking. This asserts the ingester never
# picks the files up in the first place, which is what failed on 2026-11-08:
# OPERATOR.md was on the deny-list but the two MCP授权 docs beside it were not,
# so they were chunked into kb_chunks. Only the retrieval gate hid them.
$seeder = Join-Path $repoRoot 'pacgate-ai/crates/pacgate-api/src/bin/seed.rs'
if (Test-Path -LiteralPath $seeder) {
    $src = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($seeder))
    $m = [regex]::Match($src, 'const EXCLUDE_FILENAMES[^=]*=\s*&\[(?<body>.*?)\];', 'Singleline')
    if (-not $m.Success) {
        Fail 'could not locate EXCLUDE_FILENAMES in seed.rs'
    } else {
        $body = $m.Groups['body'].Value
        foreach ($needed in @('OPERATOR.md', '法律数据库MCP.md', '境外法律数据库和网站.md')) {
            if ($body.Contains("`"$needed`"")) {
                Pass "seed deny-list excludes $needed"
            } else {
                Fail "seed deny-list is MISSING $needed - it would be chunked into kb_chunks"
            }
        }
    }
} else {
    Skip 'seed.rs not found; cannot check the KB deny-list.'
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host "RESULT: $pass passed, 0 failed - no .env secret is reachable from the data tree." -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULT: $fail failed, $pass passed - a secret is exposed to the agent." -ForegroundColor Red
    exit 1
}
