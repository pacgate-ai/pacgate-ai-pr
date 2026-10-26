# Verify every merge anchor exists in the UPSTREAM 86a9feb copies BEFORE the swap,
# so a missing anchor fails here (cheap, reversible) rather than mid-apply.
$ErrorActionPreference = 'Stop'
$out = Join-Path $env:TEMP '86a9feb'

$checks = @(
    @{ File = 'deploy/client-bundle/compose.bundle.yaml'
       Anchors = @(
        '      - ./deer-flow-config.yaml:/app/backend/config.yaml:ro'
        '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro'
        '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro'
        '      - ./patches/deer-flow-memory-prompt.py:/app/backend/packages/harness/deerflow/agents/memory/prompt.py:ro')
    }
    @{ File = 'deploy/client-bundle/compose.prod.yaml'
       Anchors = @(
        '      - ./patches/deer-flow-uploads.py:/app/backend/app/gateway/routers/uploads.py:ro'
        '      - ./patches/deer-flow-memory-storage.py:/app/backend/packages/harness/deerflow/agents/memory/storage.py:ro'
        '      - ./patches/deer-flow-memory-prompt.py:/app/backend/packages/harness/deerflow/agents/memory/prompt.py:ro')
    }
    @{ File = 'scripts/run-all-checks.ps1'
       Anchors = @("    'scripts/test-memory-prompt-stability.ps1'")
    }
)

$bad = 0
foreach ($c in $checks) {
    $fat = Join-Path $out ($c.File -replace '/', '\')
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($fat))
    foreach ($a in $c.Anchors) {
        $ok = $text.Contains($a)
        if (-not $ok) { $bad++ }
        '{0,-6} {1,-42} {2}' -f $(if ($ok) { 'OK' } else { 'MISSING' }), $c.File, $a.Trim()
    }
}

# Also confirm upstream does NOT already carry our mounts (i.e. they really are local-only).
'--- our mounts must be ABSENT upstream (proof they are local deltas) ---'
$bundle = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $out 'deploy\client-bundle\compose.bundle.yaml')))
foreach ($m in @('deer-flow-memory-updater.py', 'deer-flow-uploads-middleware.py', 'deer-flow/skills/public')) {
    '{0,-6} absent_upstream={1}' -f $m, (-not $bundle.Contains($m))
}
"anchor_failures=$bad"
