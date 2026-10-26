# Run the PacGate OUTPUT evals: does the product produce CORRECT legal output?
#
# WHY THIS IS NOT PART OF run-all-checks.ps1
# ==========================================
#
# The 48-gate suite answers "is the stack wired correctly". Every one of those
# gates is deterministic and fast, and together they are already a ~20 minute
# run. These evals answer a different question - "is the generated output
# correct" - and they are neither fast nor free: each one executes a real
# workflow against a real model and pays for a real generation.
#
# Mixing them in would do two bad things at once:
#
#   1. make the gate suite slow enough that people stop running it, which is the
#      documented way a suite stops being read (see run-all-checks.ps1's own
#      header on the "runner that is red when nothing is wrong");
#   2. blur the difference between "a mount is wrong" (binary, deterministic)
#      and "the model produced nothing on 1 run in 3" (a RATE).
#
# So the evals live here, and the split is deliberate: a gate NEVER gets weaker
# by being here, and an eval NEVER blocks a release on a probabilistic result.
#
# THE RATE IS THE POINT
# =====================
#
# test-document-generation-e2e.ps1 already runs the generation path once. This
# suite exists because one sample cannot distinguish:
#
#     "generation works"            from
#     "generation works 2 times in 3"
#
# Measured 2026-10-24 on this box: the `generate_docx` step hit its tool-round
# cap on 1 of 3 runs, returned empty content, and the route still answered
# HTTP 200. A single-shot gate passes that stack. generation_reliability.py is
# the only thing that reports it.
#
# EXIT CODES, and why 2 is honoured here too
# ==========================================
#
# Every eval uses the same convention as the live-stack gates:
#   0 pass | 1 a real failure | 2 CANNOT CHECK (stack down / no credentials)
#
# 2 does not fail the run, for the same reason it does not in run-all-checks.ps1:
# on a clean machine with no stack up, a red result would teach people to ignore
# the suite rather than trust it. It is a carve-out on the EXIT CODE only -
# nothing here can turn an observed failure green.
#
# LLM-AS-JUDGE IS DELIBERATELY ABSENT
# ===================================
#
# Egress policy on this project is "client data does not leave the box". Grading
# cloud-generated output with a cloud judge would open a SECOND egress path that
# test-chat-no-auto-egress.ps1 and audit-sanitized-chunk-egress.ps1 exist to
# close. Every eval here is a CODE grader: deterministic, offline, and unable to
# be talked out of a finding. A judge lane can be added later against the LOCAL
# qwen3.8-legal:27b-mid, but only on top of a calibrated code-graded baseline -
# and it must be local when it lands.
#
# Usage:
#   pwsh -File scripts/eval/run-evals.ps1
#   pwsh -File scripts/eval/run-evals.ps1 -Runs 5        # larger reliability sample
#   pwsh -File scripts/eval/run-evals.ps1 -SkipLive      # only the offline evals
[CmdletBinding()]
param(
    # Sample size for the reliability eval. Each run costs a real generation, so
    # the default is the smallest number that can distinguish 100% from 2-in-3.
    [int]$Runs = 3,
    # The workflow under evaluation. Default reads a document and generates a
    # memo, so it exercises citation AND generation in one pass.
    [string]$WorkflowId = '00000000-0000-0000-0000-000000000301',
    [switch]$SkipLive
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot

# Python is NOT on PATH on this box - AGENTS.md records this and it has bitten
# every script that assumed otherwise. Resolve it once, and CANNOT CHECK rather
# than crash if it is genuinely absent.
$python = 'C:\Program Files\Python313\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source }
    else {
        Write-Host 'CANNOT CHECK: no Python interpreter found (expected C:\Program Files\Python313\python.exe)' -ForegroundColor Yellow
        exit 2
    }
}

# The console code page on this box is GBK (936). A Chinese workflow name written
# to it arrives as mojibake, so a failing prompt is reported as 椤圭洰妗ｆ and
# nobody can tell WHICH one failed. AGENTS.md documents this trap for git's CJK
# paths; this is the same fix for Python's output.
$prevOut = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$env:PYTHONIOENCODING = 'utf-8'

$script:pass = 0
$script:fail = 0
$script:skip = 0

function Invoke-Eval {
    # NOTE: the parameter is $ScriptArgs, NOT $Args. `$Args` is an automatic
    # variable holding a function's unbound arguments, and declaring it as a
    # parameter makes binding silently fail: the first version of this runner
    # used `-ScriptArgs @('--baseline', ...)` and the baseline never arrived, so the
    # lint reported all 219 prompts as regressions and the runner went red on a
    # tree where the direct invocation passed. Diagnosed by running the python
    # command by hand and comparing - the argument was the only difference.
    param([string]$Name, [string]$Script, [string[]]$ScriptArgs = @())

    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $argv = @($Script) + $ScriptArgs
    & $python @argv
    $code = $LASTEXITCODE

    switch ($code) {
        0 { Write-Host "  -> PASS ($Name)" -ForegroundColor Green; $script:pass++ }
        2 { Write-Host "  -> CANNOT CHECK ($Name)" -ForegroundColor Yellow; $script:skip++ }
        default { Write-Host "  -> FAIL ($Name, exit $code)" -ForegroundColor Red; $script:fail++ }
    }
}

Write-Host 'PAC GATE OUTPUT EVALS' -ForegroundColor Cyan
Write-Host '====================='
Write-Host "python  : $python"
Write-Host "workflow: $WorkflowId"
Write-Host "runs    : $Runs"

# ── Offline evals: no stack, no model, no egress ────────────────────────────

# The grader itself must be proven able to FAIL before it is trusted to pass
# anything. Two graders in this repo shipped unable to fail (a silently skipped
# 60 of 832 files; a collapsed 19-element JSON array) and both reported green.
Invoke-Eval -Name 'citation grader self-test' `
    -Script 'scripts/eval/test_citation_integrity_grader.py'

# Same reasoning for the substance matcher. Its first version used a plain
# substring test and a bare `45` matched inside `9145010000`, reporting the
# payment term as present in an output that never mentioned it.
Invoke-Eval -Name 'substance matching self-test' `
    -Script 'scripts/eval/test_answer_substance_matching.py'

# The static prompt contract. Offline and deterministic, so it also runs as a
# gate in run-all-checks.ps1 - it is repeated here so the eval report is a
# complete statement of output quality rather than a partial one.
Invoke-Eval -Name 'prompt contract lint' `
    -Script 'scripts/eval/prompt_contract_lint.py' `
    -ScriptArgs @('--baseline', 'scripts/eval/baseline-prompt-contract.json')

if (-not $SkipLive) {
    # ── Live evals: need the stack, credentials, and a real model ───────────

    # Build the corpus. Generated rather than committed, following
    # test-legal-journey.ps1: the text lives in build_fixtures.py so a change to a
    # fixture shows up in a diff, and no client document becomes test data.
    $fxDir = Join-Path ([System.IO.Path]::GetTempPath()) 'pacgate-eval-fixtures'
    Invoke-Eval -Name 'fixture corpus' `
        -Script 'scripts/eval/build_fixtures.py' `
        -ScriptArgs @('--out', $fxDir)

    # Citation integrity: does the model cite text that actually exists?
    # CANNOT CHECK (2) when the run returns no citations at all - that is a
    # weaker finding than fabrication and must not be reported as either.
    Invoke-Eval -Name 'citation integrity' `
        -Script 'scripts/eval/citation_integrity.py' `
        -ScriptArgs @('--workflow-id', $WorkflowId)

    # Answer substance: were the CONTROLLED facts from the fixture carried into
    # the output? Citation integrity proves a quote is real; this proves the
    # right number was read out of it. A memo can cite a genuine 45-day sentence
    # and still state 30 days - every other check passes that.
    Invoke-Eval -Name 'answer substance' `
        -Script 'scripts/eval/answer_substance.py' `
        -ScriptArgs @('--workflow-id', $WorkflowId)

    # Generation reliability: measured as a RATE, because one sample cannot tell
    # "works" from "works 2 times in 3".
    Invoke-Eval -Name 'generation reliability' `
        -Script 'scripts/eval/generation_reliability.py' `
        -ScriptArgs @('--workflow-id', $WorkflowId, '--runs', "$Runs")
}
else {
    Write-Host ''
    Write-Host 'Live evals SKIPPED (-SkipLive)' -ForegroundColor Yellow
}

try { [Console]::OutputEncoding = $prevOut } catch { }

Write-Host ''
Write-Host '====================='
Write-Host ("EVALS: {0} passed, {1} failed, {2} cannot check" -f $script:pass, $script:fail, $script:skip) `
    -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })

if ($script:fail -gt 0) { exit 1 }
exit 0

