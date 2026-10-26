# Re-apply local deltas after the subtree swap.
#
# Two classes, handled differently:
#   A. files 86a9feb does NOT touch -> restore the preserved copy verbatim
#   B. files 86a9feb DOES touch     -> MERGE: keep upstream's new version, then
#      re-insert ONLY our local additions on top
#
# Restoring class B verbatim would silently erase upstream's fix - the exact
# failure mode that makes a subtree swap dangerous.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$repo = (Get-Location).Path
$preserve = Join-Path $repo 'runtime\sync-1026\local-preserve'
$listFile = Join-Path $repo 'runtime\sync-1026\local-delta-list.txt'

# The 8 paths 86a9feb changes.
$upstreamTouched = @(
    'pacgate-ai/deploy/client-bundle/compose.bundle.yaml'
    'pacgate-ai/deploy/client-bundle/compose.prod.yaml'
    'pacgate-ai/deploy/client-bundle/patches/deer-flow-memory-prompt.py'
    'pacgate-ai/plans/031-aipc-latency-root-cause-and-fix.md'
    'pacgate-ai/plans/README.md'
    'pacgate-ai/scripts/run-all-checks.ps1'
    'pacgate-ai/scripts/test-memory-lane.ps1'
    'pacgate-ai/scripts/test-memory-prompt-stability.ps1'
)

$rows = (([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($listFile))) -split "`n") |
Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split "`t")[0] }

'--- A. restoring files 86a9feb does NOT touch ---'
$restored = 0
foreach ($p in $rows) {
    if ($upstreamTouched -contains $p) { continue }
    $src = Join-Path $preserve ($p -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { "SKIP_MISSING_PRESERVE $p"; continue }
    $target = Join-Path $repo ($p -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($src))
    $restored++
}
"restored_verbatim=$restored"

'--- B. merging files 86a9feb DOES touch ---'
"deferred to the explicit merge steps below"

# ---- B1. compose.bundle.yaml + compose.prod.yaml : insert our 3 mounts ----
# Anchors are upstream's own lines, so the insert is position-stable.
$mountAnchors = @(
    @{
        Path = 'pacgate-ai/deploy/client-bundle/compose.bundle.yaml'
        Rules = @(
            @{ After = '      - ./deer-flow-config.yaml:/app/backend/config.yaml:ro'
               Lines = @(
'      # Pacgate 2026-10-08: serve the skills tree (60 dirs: 37 PacGate legal + 23',
'      # upstream) from the merged pacgate-layer working copy. The published image',
'      # has NO /app/skills - re-verified against 0.2.6 on 2026-10-25, so this is',
'      # still required and is not a leftover. Without it the gateway resolves its',
'      # skills root to a missing dir and /api/skills returns [].',
'      - ../../../deer-flow/skills/public:/app/skills/public:ro')
            }
            @{ After = '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro'
               Lines = @(
'      # Pacgate (2026-10-10): strengthen the <uploaded_files> block so nemotron',
'      # actually calls read_file (30B MoE tool-choice variance buried the softer',
'      # instruction under 64k of tool/system context).',
'      - ./patches/deer-flow-uploads-middleware.py:/app/backend/packages/harness/deerflow/agents/middlewares/uploads_middleware.py:ro')
            }
            @{ After = '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro'
               Lines = @(
'      # Pacgate 2026-10-26: redact direct identifiers (USCC / 身份证 / 手机号 /',
'      # 银行卡 / email) from the memory lane input AND its outgoing payload.',
'      # pacgate-api refuses a payload containing one (HTTP 422), so the save',
'      # failed on essentially every turn of a research run. Person and',
'      # organisation NAMES stay permitted by design. See deer-flow-memory-updater.py.',
'      - ./patches/deer-flow-memory-updater.py:/app/backend/packages/harness/deerflow/agents/memory/updater.py:ro')
            }
        )
    }
    @{
        Path = 'pacgate-ai/deploy/client-bundle/compose.prod.yaml'
        Rules = @(
            # MISSED ON THE FIRST RUN: original prod DID carry this mount (line 252).
            # Restoring only what compose.bundle.yaml needed silently dropped it from
            # prod. Caught by diffing the merged file against the preserved original,
            # not by assuming the two files' local deltas were the same shape.
            @{ After = '      - ./deer-flow-config.yaml:/app/backend/config.yaml:ro'
               Lines = @(
'      # Pacgate 2026-10-08: serve the skills tree from the merged pacgate-layer',
'      # working copy. The published image has NO /app/skills - re-verified against',
'      # 0.2.6 on 2026-10-25. Without it the gateway resolves its skills root to a',
'      # missing dir and /api/skills returns []. See compose.bundle.yaml.',
'      - ../../../deer-flow/skills/public:/app/skills/public:ro')
            }
            @{ After = '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro'
               Lines = @(
'      # Pacgate (2026-10-10): strengthen the <uploaded_files> block (see',
'      # compose.bundle.yaml for the rationale).',
'      - ./patches/deer-flow-uploads-middleware.py:/app/backend/packages/harness/deerflow/agents/middlewares/uploads_middleware.py:ro')
            }
            @{ After = '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro'
               Lines = @(
'      # Pacgate 2026-10-26: redact direct identifiers from the memory lane',
'      # (see compose.bundle.yaml for the rationale).',
'      - ./patches/deer-flow-memory-updater.py:/app/backend/packages/harness/deerflow/agents/memory/updater.py:ro')
            }
        )
    }
)

foreach ($spec in $mountAnchors) {
    $fat = Join-Path $repo ($spec.Path -replace '/', '\')
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($fat))
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    foreach ($rule in $spec.Rules) {
        # Idempotence: skip if the mount path is already present.
        $mountPath = ($rule.Lines | Where-Object { $_ -match '^\s+- ' } | Select-Object -Last 1)
        $needle = ($mountPath -split ':')[0].Trim()
        if ($text.Contains($needle)) { "  already-present $needle"; continue }

        $anchor = $rule.After
        $idx = $text.IndexOf($anchor)
        if ($idx -lt 0) { throw "anchor not found in $($spec.Path): $anchor" }
        $insertAt = $idx + $anchor.Length
        $block = $nl + (($rule.Lines) -join $nl)
        $text = $text.Substring(0, $insertAt) + $block + $text.Substring($insertAt)
        "  inserted $needle  ->  $($spec.Path)"
    }
    [System.IO.File]::WriteAllText($fat, $text, [System.Text.UTF8Encoding]::new($false))
}

# ---- B2. run-all-checks.ps1 : re-register our prompt-contract gate ----
$rac = Join-Path $repo 'pacgate-ai\scripts\run-all-checks.ps1'
$t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($rac))
if ($t.Contains("'scripts/test-prompt-contract.ps1'")) {
    '  prompt-contract gate already registered'
}
else {
    # Insert immediately AFTER upstream's new memory-prompt gate registration.
    $anchor = "    'scripts/test-memory-prompt-stability.ps1'"
    $idx = $t.IndexOf($anchor)
    if ($idx -lt 0) { throw 'anchor not found: test-memory-prompt-stability registration' }
    $nl = if ($t -match "`r`n") { "`r`n" } else { "`n" }
    $block = @(
''
'    # PROMPT CONTRACT, registered 2026-10-24. The suite asserted PLUMBING;'
'    # nothing asserted that a PROMPT says what the product promises. That is'
'    # where the 红线 lives: SOUL_Sylvie_v1.0.md forbids issuing a "final legal'
'    # opinion" and forbids filling a legal conclusion from model knowledge when'
'    # the source cannot be found. Measured 2026-10-24 across 219'
'    # document-producing prompts: draft-for-review 1.8%, citation 47.0%,'
'    # uncertainty 5.9%.'
'    #'
'    # STATIC: reads YAML, no containers, no credentials, no model. It RATCHETS'
'    # against scripts/eval/baseline-prompt-contract.json so existing failures do'
'    # not make the suite permanently red, while a NEW clause-free prompt fails.'
"    'scripts/test-prompt-contract.ps1'"
    ) -join $nl
    $insertAt = $idx + $anchor.Length
    $t = $t.Substring(0, $insertAt) + $nl + $block + $t.Substring($insertAt)
    [System.IO.File]::WriteAllText($rac, $t, [System.Text.UTF8Encoding]::new($false))
    '  registered scripts/test-prompt-contract.ps1'
}

# ---- B3. test-memory-lane.ps1 : upstream WINS, no merge ----
# d1ed509 fixed the same two bugs independently; upstream's argv form and
# EAP-scoping are strictly better. Keep upstream's file as-is.
'  test-memory-lane.ps1: upstream version kept (supersedes our d1ed509 fix)'

'--- done ---'
