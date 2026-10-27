# Merge our local additions back into the 4 files upstream also changed.
# Upstream's new content stays; only our additions are re-inserted.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$repo = (Get-Location).Path
$base = Join-Path $repo 'pacgate-ai\deploy\client-bundle'

function Read-Text([string]$p) { return [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($p)) }
function Write-Text([string]$p, [string]$t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.UTF8Encoding]::new($false)) }

function Insert-After([string]$text, [string]$anchor, [string[]]$lines, [string]$label) {
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    # Idempotence: the mount path is the last "- " line.
    $mountLine = ($lines | Where-Object { $_ -match '^\s+- ' } | Select-Object -Last 1)
    if ($mountLine) {
        $needle = ($mountLine -split ':')[0].Trim()
        if ($text.Contains($needle)) { "  already-present $needle"; return $text }
    }
    $idx = $text.IndexOf($anchor)
    if ($idx -lt 0) { throw "anchor not found for ${label}: $anchor" }
    $insertAt = $idx + $anchor.Length
    return $text.Substring(0, $insertAt) + $nl + ($lines -join $nl) + $text.Substring($insertAt)
}

# ---------- compose.bundle.yaml ----------
$f = Join-Path $base 'compose.bundle.yaml'
$t = Read-Text $f
$t = Insert-After $t '      - ./deer-flow-config.yaml:/app/backend/config.yaml:ro' @(
'      # Pacgate 2026-10-08: serve the skills tree (60 dirs: 37 PacGate legal + 23',
'      # upstream) from the merged pacgate-layer working copy. The published image',
'      # has NO /app/skills - re-verified against 0.2.6 on 2026-10-25. Without it the',
'      # gateway resolves its skills root to a missing dir and /api/skills returns [].',
'      - ../../../deer-flow/skills/public:/app/skills/public:ro'
) 'bundle/skills'
$t = Insert-After $t '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro' @(
'      # Pacgate (2026-10-10): strengthen the <uploaded_files> block so the model',
'      # actually calls read_file (30B MoE tool-choice variance buried the softer',
'      # instruction under 64k of tool/system context).',
'      - ./patches/deer-flow-uploads-middleware.py:/app/backend/packages/harness/deerflow/agents/middlewares/uploads_middleware.py:ro'
) 'bundle/uploads-mw'
$t = Insert-After $t '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro' @(
'      # Pacgate 2026-10-26: redact direct identifiers (USCC / 身份证 / 手机号 /',
'      # 银行卡 / email) from the memory lane input AND its outgoing payload.',
'      # pacgate-api refuses a payload containing one (HTTP 422), so the save failed',
'      # on essentially every turn of a research run. Person and organisation NAMES',
'      # stay permitted by design. See deer-flow-memory-updater.py.',
'      - ./patches/deer-flow-memory-updater.py:/app/backend/packages/harness/deerflow/agents/memory/updater.py:ro'
) 'bundle/memory-updater'
Write-Text $f $t
'compose.bundle.yaml merged'

# ---------- compose.prod.yaml ----------
$f = Join-Path $base 'compose.prod.yaml'
$t = Read-Text $f
$t = Insert-After $t '      - ./deer-flow-config.yaml:/app/backend/config.yaml:ro' @(
'      # Pacgate 2026-10-08: serve the skills tree from the merged pacgate-layer',
'      # working copy. The published image has NO /app/skills - re-verified against',
'      # 0.2.6 on 2026-10-25. See compose.bundle.yaml.',
'      - ../../../deer-flow/skills/public:/app/skills/public:ro'
) 'prod/skills'
$t = Insert-After $t '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro' @(
'      # Pacgate (2026-10-10): strengthen the <uploaded_files> block (see',
'      # compose.bundle.yaml for the rationale).',
'      - ./patches/deer-flow-uploads-middleware.py:/app/backend/packages/harness/deerflow/agents/middlewares/uploads_middleware.py:ro'
) 'prod/uploads-mw'
$t = Insert-After $t '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro' @(
'      # Pacgate 2026-10-26: redact direct identifiers from the memory lane',
'      # (see compose.bundle.yaml for the rationale).',
'      - ./patches/deer-flow-memory-updater.py:/app/backend/packages/harness/deerflow/agents/memory/updater.py:ro'
) 'prod/memory-updater'
Write-Text $f $t
'compose.prod.yaml merged'

# ---------- deer-flow-config.yaml : our subagents block ----------
# The swap reverted it. Re-insert the whole block from the preserved original,
# anchored on the line that follows it in the new file.
$cfg = Join-Path $base 'deer-flow-config.yaml'
$t = Read-Text $cfg
if ($t.Contains('subagents:')) {
    'deer-flow-config.yaml: subagents already present'
}
else {
    $orig = Read-Text (Join-Path $repo 'runtime\sync-1027\local-preserve\pacgate-ai\deploy\client-bundle\deer-flow-config.yaml')
    $oLines = $orig -split "`r?`n"
    $start = -1
    for ($i = 0; $i -lt $oLines.Count; $i++) {
        if ($oLines[$i] -match '^subagents:\s*$') { $start = $i; break }
    }
    if ($start -lt 0) { throw 'subagents: block not found in the preserved original' }
    # The block runs until the next top-level key (column 0, non-comment).
    $end = $oLines.Count - 1
    for ($i = $start + 1; $i -lt $oLines.Count; $i++) {
        if ($oLines[$i] -match '^[A-Za-z_][A-Za-z0-9_]*:') { $end = $i - 1; break }
    }
    $block = $oLines[$start..$end]
    "  subagents block lines = $($block.Count)"
    # Anchor: insert immediately before the loop_detection block upstream added.
    $anchor = 'loop_detection:'
    $idx = $t.IndexOf($anchor)
    if ($idx -lt 0) { throw 'anchor not found: loop_detection:' }
    $nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
    $t = $t.Substring(0, $idx) + ($block -join $nl) + $nl + $nl + $t.Substring($idx)
    Write-Text $cfg $t
    'deer-flow-config.yaml: subagents block restored'
}

# ---------- run-all-checks.ps1 : our prompt-contract gate ----------
$rac = Join-Path $repo 'pacgate-ai\scripts\run-all-checks.ps1'
$t = Read-Text $rac
if ($t.Contains("'scripts/test-prompt-contract.ps1'")) {
    'run-all-checks.ps1: prompt-contract already registered'
}
else {
    $anchor = "    'scripts/test-loop-detection-window.ps1'"
    $idx = $t.IndexOf($anchor)
    if ($idx -lt 0) { throw 'anchor not found: test-loop-detection-window registration' }
    $nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
    $block = @(
''
'    # PROMPT CONTRACT, registered 2026-10-24. The suite asserted PLUMBING; nothing'
'    # asserted that a PROMPT says what the product promises. That is where the 红线'
'    # lives: SOUL_Sylvie_v1.0.md forbids issuing a "final legal opinion" and forbids'
'    # filling a legal conclusion from model knowledge when the source cannot be'
'    # found. Measured 2026-10-24 across 219 document-producing prompts:'
'    # draft-for-review 1.8%, citation 47.0%, uncertainty 5.9%.'
'    #'
'    # STATIC: reads YAML, no containers, no credentials, no model. It RATCHETS'
'    # against scripts/eval/baseline-prompt-contract.json so existing failures do not'
'    # make the suite permanently red, while a NEW clause-free prompt fails.'
"    'scripts/test-prompt-contract.ps1'"
    ) -join $nl
    $insertAt = $idx + $anchor.Length
    $t = $t.Substring(0, $insertAt) + $block + $t.Substring($insertAt)
    Write-Text $rac $t
    'run-all-checks.ps1: prompt-contract registered'
}
