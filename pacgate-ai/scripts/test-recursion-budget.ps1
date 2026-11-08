# Test: the lead-agent recursion budget must default to its CEILING, not to a
# floor that real work cannot finish under.
#
# WHY THIS EXISTS
#
# `patches/deer-flow-run-recursion-cap.py` introduced DEERFLOW_MAX_RECURSION_LIMIT
# as a ceiling so a thrashing run cannot ask for an unbounded budget. But it kept
# `config: dict = {"recursion_limit": 100}` as the DEFAULT, and only clamped when
# the caller explicitly asked for MORE. So the two callers diverged:
#
#   chat UI  -> sends recursion_limit: 1000 -> clamped to 500  (the ceiling works)
#   API / IM -> sends nothing               -> gets 100        (the floor applies)
#
# Measured live 2026-10-30 on 0.2.7 (thread 4de2965b, run 27e0916c):
#
#   Recursion limit of 100 reached without hitting a stop condition.
#
# and that thread's own checkpoints prove it was NOT thrashing — it completed
# its real work first, then spent the remaining budget on ONE dead-end detour:
#
#   step  ~2  read_file  /mnt/playbooks/nda-playbook.md        OK
#   step  ~4  read_file  /mnt/user-data/uploads/nda6.md        OK
#   step  ~6  officecli  create /mnt/user-data/outputs/NDA-redline.docx   OK
#   step  ~8..24  officecli add x4, validate -> "Validation passed: no errors"
#   step ~25  write_file /mnt/user-data/outputs/NDA-review.md  OK  <-- DONE
#   step ~27  read_file  .../NDA-redline.docx  -> "binary file, use bash" (misroutes)
#   step ~29  bash pandoc ...                   -> the misroute's consequence
#   step 100  killed
#
# Both deliverables were written and validated BEFORE the kill. The run died
# with nothing left to do, because the default budget (100) is ~12 LLM calls
# while LangGraph charges ~9 super-steps per LLM call in this graph. A 12-call
# run therefore consumes the entire budget by design.
#
# Compare the workload the stack is actually asked to do:
#   d35307ec  max_step 5767  599 LLM calls  glm-5.3-flash-cloud
#   f7f240f6  max_step 3154  deepseek-v4.1-flash-cloud
#   dcced4b5  max_step 1589  deepseek-v4.1-flash-cloud
#
# A ceiling of 500 was below every one of those. The ceiling is now 4000, which
# clears the deepest observed run with ~2.5x headroom, because the separate
# guards already stop a real loop:
#   * LoopDetectionMiddleware  layer 1 (identical tool-call hash, warn 3 /
#     hard-stop 5) and layer 2 (per-tool frequency window, bash 100/150)
#   * DEERFLOW_STREAM_IDLE_TIMEOUT_S  and the 420 s stall detector
# A run that does real work is therefore NOT bounded by this number, and a run
# that repeats itself is stopped by loop detection long before 500.
#
# WHAT IT ASSERTS
#
#   R1  The patch file exists and is the mount target for gateway/services.py.
#   R2  BOTH compose files mount it (install.ps1 uses compose.prod.yaml).
#   R3  No caller config (the API / IM channel path) defaults to the CEILING,
#       not to a hardcoded 100. This is the defect.
#   R4  An empty config ({}) also defaults to the CEILING.
#   R5  An explicit request BELOW the server floor is raised to the floor, and one
#       between the floor and the ceiling is honoured verbatim. The floor exists
#       because a below-floor budget cannot complete a deep run: a caller asking
#       for 50 would burn 50 super-steps and fail mid-task. See
#       deploy/DEFECT-recursion-budget-floor.md (the floor is the intended fix).
#   R6  An ABOVE-ceiling request is clamped to the ceiling.
#   R7  DEERFLOW_MAX_RECURSION_LIMIT actually controls the default AND the cap
#       (the env var is the only lever, so it must not be cosmetic).
#   R8  The ceiling is high enough for the deepest observed NON-looping workload
#       (max_step 1589 => a 4-digit ceiling, not 3).
#   R9  Live: the container's effective default is the ceiling.
#   R10 A real agent run on gemma4 finishes its document work without the
#       recursion wall (SKIP when no stack / no upload fixture).
#
# Usage:  powershell -File scripts/test-recursion-budget.ps1
# Exit:   0 = all assertions pass, 1 = a failure, 2 = could not check (no stack).

[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$Container = 'deer-flow',
    # Deepest observed max_step across threads that were NOT cut by loop
    # detection. 1589 (thread dcced4b5, deepseek-v4.1-flash-cloud). Raise only
    # with a new measurement, so the ceiling cannot silently drop below it.
    [int]$ObservedDeepestSteps = 1589
)

$ErrorActionPreference = 'Continue'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$script:passed = 0
$script:failed = 0

function Pass($m) { Write-Host "  [PASS] $m" -ForegroundColor Green; $script:passed++ }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:failed++ }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

Write-Host '=== lead-agent recursion budget (default must be the ceiling) ===' -ForegroundColor Cyan

$patchRel = 'deploy/client-bundle/patches/deer-flow-run-recursion-cap.py'
$patchPath = Join-Path $RepoRoot ($patchRel -replace '/', '\')

# --- R1: patch present and is the mount target --------------------------------
if (Test-Path $patchPath) {
    Pass 'R1 the patch file exists'

    $decl = Select-String -Path $patchPath -Pattern '_PACGATE_MAX_RECURSION_LIMIT\s*=' -Quiet
    if ($decl) { Pass 'R1 the patch derives a ceiling from DEERFLOW_MAX_RECURSION_LIMIT' }
    else { Fail 'R1 the patch has no _PACGATE_MAX_RECURSION_LIMIT (no ceiling configured)' }
} else {
    Fail "R1 the patch file is missing: $patchRel"
}

# --- R2: mount parity across BOTH compose files -------------------------------
foreach ($cf in @('compose.bundle.yaml', 'compose.prod.yaml')) {
    $cfPath = Join-Path $RepoRoot ('deploy/client-bundle/' + $cf)
    if (-not (Test-Path $cfPath)) { Fail "R2 $cf is missing"; continue }
    if (Select-String -Path $cfPath -Pattern 'deer-flow-run-recursion-cap.py' -SimpleMatch -Quiet) {
        Pass "R2 $cf mounts the patch over gateway/services.py"
    } else {
        Fail "R2 $cf does NOT mount the patch (absent from the deployment path)"
        Info 'install.ps1 uses compose.prod.yaml; a bundle-only mount leaves the defect live.'
    }
}

# --- preflight ---------------------------------------------------------------
$running = (& docker ps --filter "name=^/$Container$" --format '{{.Names}}' 2>&1) -join ''
if ($running -notmatch [regex]::Escape($Container)) {
    Write-Host "RESULT: SKIP - container '$Container' is not running; R3-R10 cannot be checked." -ForegroundColor Yellow
    Write-Host "passed=$script:passed failed=$script:failed"
    exit 2
}

# Run a python snippet INSIDE the container against the LIVE patched module.
# The venv python is required: the system python has no yaml/langgraph.
function Invoke-BuildRunConfig {
    param([string]$JsonConfig, [string]$Ceiling = '')

    $envPrefix = if ($Ceiling) { "DEERFLOW_MAX_RECURSION_LIMIT=$Ceiling " } else { '' }
    $py = @"
import sys, os, json
sys.path.insert(0, '/app/backend/packages/harness')
sys.path.insert(0, '/app/backend')
import logging; logging.disable(logging.CRITICAL)
from app.gateway.services import build_run_config, _PACGATE_MAX_RECURSION_LIMIT
cfg = json.loads('''$JsonConfig''')
result = build_run_config('probe-thread', cfg, None, assistant_id=None)
print(json.dumps({'limit': result.get('recursion_limit'), 'ceiling': _PACGATE_MAX_RECURSION_LIMIT}))
"@
    $tmp = Join-Path $env:TEMP ("rbc-" + [guid]::NewGuid().ToString('N') + ".py")
    [System.IO.File]::WriteAllText($tmp, $py, (New-Object System.Text.UTF8Encoding($false)))
    try {
        & docker cp $tmp "${Container}:/tmp/probe_rbc.py" 2>&1 | Out-Null
        $raw = & docker exec $Container sh -c "cd /app/backend && ${envPrefix}.venv/bin/python /tmp/probe_rbc.py 2>/dev/null"
        $line = ($raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
        if (-not $line) { return $null }
        return $line | ConvertFrom-Json
    } finally {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        & docker exec $Container sh -c 'rm -f /tmp/probe_rbc.py' 2>&1 | Out-Null
    }
}

$ceiling = $null
$noCfg = Invoke-BuildRunConfig -JsonConfig 'null'
if (-not $noCfg) {
    Write-Host 'RESULT: SKIP - could not import the patched build_run_config in the container.' -ForegroundColor Yellow
    Write-Host "passed=$script:passed failed=$script:failed"
    exit 2
}
$ceiling = [int]$noCfg.ceiling
Info "live ceiling (DEERFLOW_MAX_RECURSION_LIMIT) = $ceiling"

# --- R3: the API / channel path (no caller config) gets the CEILING ----------
if ([int]$noCfg.limit -eq $ceiling) {
    Pass "R3 no caller config defaults to the ceiling ($($noCfg.limit))"
} elseif ([int]$noCfg.limit -lt 300) {
    Fail "R3 no caller config defaults to $($noCfg.limit) — a floor, not the ceiling ($ceiling)"
    Info 'The API/IM path sends no config, so it inherits this. Measured: thread 4de2965b died at'
    Info 'this number AFTER writing and validating both deliverables (max_step 101).'
} else {
    Fail "R3 no caller config defaults to $($noCfg.limit), which is not the ceiling ($ceiling)"
}

# --- R4: an empty config behaves like no config ------------------------------
$emptyCfg = Invoke-BuildRunConfig -JsonConfig '{}'
if ($emptyCfg -and [int]$emptyCfg.limit -eq $ceiling) {
    Pass "R4 an empty config also defaults to the ceiling ($($emptyCfg.limit))"
} else {
    Fail "R4 an empty config defaults to $($emptyCfg.limit) instead of the ceiling ($ceiling)"
}

# --- R5: a below-floor request is raised to the floor ------------------------
# The floor is the documented fix (deploy/DEFECT-recursion-budget-floor.md):
# a budget under it cannot finish a deep run. This assertion previously required
# the OPPOSITE (50 honoured verbatim), encoding the pre-floor contract.
$small = Invoke-BuildRunConfig -JsonConfig '{"recursion_limit": 50}'
$floor = if ($env:DEERFLOW_MIN_RECURSION_LIMIT) { [int]$env:DEERFLOW_MIN_RECURSION_LIMIT } else { 2000 }
if ($small -and [int]$small.limit -eq $floor) {
    Pass "R5 a below-floor request (50) is raised to the floor ($floor)"
} else {
    Fail "R5 a below-floor request (50) became $($small.limit); expected the floor ($floor)"
}

# --- R5b: a request between floor and ceiling is honoured verbatim -----------
$mid = Invoke-BuildRunConfig -JsonConfig '{"recursion_limit": 3000}'
if ($mid -and [int]$mid.limit -eq 3000) {
    Pass 'R5b an in-range request (3000) is honoured verbatim'
} else {
    Fail "R5b an in-range request (3000) became $($mid.limit) — it must not be altered"
}

# --- R6: an explicit LARGER request is clamped -------------------------------
$big = Invoke-BuildRunConfig -JsonConfig '{"recursion_limit": 100000}'
if ($big -and [int]$big.limit -eq $ceiling) {
    Pass "R6 an explicit above-ceiling request (100000) is clamped to $ceiling"
} else {
    Fail "R6 an explicit request of 100000 became $($big.limit) instead of the ceiling ($ceiling)"
}

# --- R7: the env var controls BOTH the default and the cap -------------------
$altCeiling = 1234
$alt = Invoke-BuildRunConfig -JsonConfig 'null' -Ceiling $altCeiling
$altBig = Invoke-BuildRunConfig -JsonConfig '{"recursion_limit": 99999}' -Ceiling $altCeiling
if ($alt -and $altBig -and [int]$alt.ceiling -eq $altCeiling -and
    [int]$alt.limit -eq $altCeiling -and [int]$altBig.limit -eq $altCeiling) {
    Pass "R7 DEERFLOW_MAX_RECURSION_LIMIT=$altCeiling drives both the default and the cap"
} else {
    Fail ("R7 the env var is not authoritative: ceiling={0} default={1} clamped={2}" -f `
            $alt.ceiling, $alt.limit, $altBig.limit)
    Info 'An env-tunable ceiling that does not also set the default cannot raise the budget'
    Info 'for the API/IM path, which is the path that actually failed.'
}

# --- R8: the ceiling must clear the deepest observed non-looping workload ----
if ($ceiling -gt $ObservedDeepestSteps) {
    Pass "R8 the ceiling ($ceiling) clears the deepest observed workload ($ObservedDeepestSteps steps)"
} else {
    Fail "R8 the ceiling ($ceiling) is below the deepest observed workload ($ObservedDeepestSteps steps)"
    Info 'Thread dcced4b5 reached 1589 super-steps doing real work; 111a45b2 1588;'
    Info 'f7f240f6 3154; d35307ec 5767. A ceiling under these caps legitimate runs.'
}

# --- R9: the live container's effective default is the ceiling ---------------
$envCeiling = (& docker exec $Container sh -c 'echo $DEERFLOW_MAX_RECURSION_LIMIT' 2>&1) -join ''
$envCeiling = $envCeiling.Trim()
if ($envCeiling -match '^\d+$') {
    if ([int]$envCeiling -eq $ceiling) {
        Pass "R9 the container's DEERFLOW_MAX_RECURSION_LIMIT is $envCeiling and is in effect"
    } else {
        Fail "R9 the container env says $envCeiling but the module loaded $ceiling"
    }
} else {
    Info "R9 DEERFLOW_MAX_RECURSION_LIMIT is unset in the container; the module default ($ceiling) applies"
    Pass 'R9 an unset env var still yields a usable ceiling'
}

# --- R10: live end-to-end (informational; needs an upload fixture) -----------
# Skipped deliberately: a document run takes minutes and needs credentials. The
# R3-R9 assertions are the defect and they are exact. Recorded here so the gap
# is visible rather than implied.
Info 'R10 live document run: not automated (minutes + credentials). Verified manually; see runtime/AUDIT-2026-10-30-mcp-skills-nda.md.'

Write-Host ''
if ($script:failed -gt 0) {
    Write-Host "RESULT: $script:failed failed, $script:passed passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $script:passed passed, 0 failed" -ForegroundColor Green
exit 0
