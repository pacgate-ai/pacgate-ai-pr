# Gate: the firm's 220 workflow prompts must carry the red-line clauses.
#
# WHY THIS GATE EXISTS
# ====================
#
# The suite had 113 scripts and every one asserted PLUMBING: the mount is right,
# the file is OOXML, the tool name appeared in `tools_used`. Searched all of them
# for `citation|引用|草稿|fabricat|hallucin` - the only hits were two unrelated
# identity-fabrication warnings in test-sync-capability.ps1. Nothing asserted that
# a PROMPT says what the product promises.
#
# That mattered because the workflow library is where the product's behaviour is
# actually written down, and the measured state on 2026-10-24 was:
#
#   RED_LINE_DRAFT       4 of 219 document-producing prompts   ( 1.8%)
#   RED_LINE_CITATION  103 of 219                              (47.0%)
#   RED_LINE_UNCERTAIN  13 of 219                              ( 5.9%)
#
# Those three are not style preferences. They are the 红线 in
# SOUL_Sylvie_v1.0.md section 禁止事项:
#
#   "不出具\"最终法律意见\"——我的一切法律产出都是供她复核的草稿"
#   "检索不到依据时如实报告,不得用模型自身知识或网络内容无声填补法律结论"
#
# A generate_docx prompt that omits them asks the model to produce exactly what
# the charter forbids - and 215 of 219 currently do.
#
# WHY A RATCHET AND NOT A FLAT FAILURE
# ====================================
#
# 219 prompts are failing RIGHT NOW. Failing every run on that makes the suite
# permanently red, which is the documented way a gate stops being read (see
# check-tracked-file-size.ps1's treatment of already-committed oversize files).
# So the accepted debt is recorded in scripts/eval/baseline-prompt-contract.json
# and the gate fails only on a REGRESSION - a prompt that ships without a clause.
# The count is printed on every run so the debt stays visible, and the baseline
# is only ever allowed to shrink.
#
# Regenerating the baseline is a deliberate act that should appear in review:
#   python scripts/eval/prompt_contract_lint.py --write-baseline <file>
#
# This is a STATIC gate: no stack, no credentials, no containers, no model.
[CmdletBinding()]
param(
    [string]$Baseline = 'scripts/eval/baseline-prompt-contract.json'
)

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

# Python is NOT on PATH on this box - AGENTS.md records it, and every script that
# assumed otherwise has failed here. Resolve, then CANNOT CHECK rather than crash.
$python = 'C:\Program Files\Python313\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host 'CANNOT CHECK: no Python interpreter found'
        exit 2
    }
    $python = $cmd.Source
}

$linter = 'scripts/eval/prompt_contract_lint.py'
if (-not (Test-Path -LiteralPath $linter)) {
    Write-Host "CANNOT CHECK: $linter is missing - the lint cannot run at all"
    exit 2
}
if (-not (Test-Path -LiteralPath $Baseline)) {
    Write-Host "CANNOT CHECK: baseline $Baseline is missing. Without it every prompt reads as a regression."
    exit 2
}

# The console code page here is GBK (936). A Chinese workflow name written to it
# arrives as mojibake, so a failing prompt is reported as 椤圭洰妗ｆ and nobody can
# tell which one failed. AGENTS.md documents this trap for git's CJK paths; this
# is the same fix for Python's stdout.
$prevOut = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$env:PYTHONIOENCODING = 'utf-8'

try {
    & $python $linter --baseline $Baseline
    $code = $LASTEXITCODE
}
finally {
    try { [Console]::OutputEncoding = $prevOut } catch { }
}

# 0 = pass, 1 = a new prompt shipped without a clause, anything else = could not
# check. Passing 2 through unchanged keeps the suite's exit-2 contract intact.
exit $code
