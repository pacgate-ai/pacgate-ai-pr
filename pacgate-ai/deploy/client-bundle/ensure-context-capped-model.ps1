# ensure-context-capped-model.ps1
#
# AIPC1 memory-wall fix (2026-10-16). Creates the LOCAL DERIVATIVE Ollama tags
# that bake a context ceiling into a model whose upstream tag declares 262144.
#
#   gemma4-legal:12b-chat  = FROM gemma4:12b-it-q8_0      + num_ctx 131072
#   qwen3.8-legal:27b-mid  = FROM qwen3.8:27b-mtp-q4_K_M  + num_ctx  32768
#
# WHY: those base tags declare a 262144-token context. On this 16GB card the KV
# cache at that size does not fit beside the weights, so Ollama splits the runner
# across CPU+GPU ("2%/98% CPU/GPU" for gemma4 q8_0) and commits 18-27GB of host
# RAM - host free RAM falls to ~1GB, which is the wall that stalled every
# deer-flow session.
#
# WHY THE CAP LIVES IN THE TAG, NOT IN A SETTING (measured 2026-10-16):
#   * A per-request `options.num_ctx` does NOT reach the runner on either route
#     (/api/chat or /v1/chat/completions): a call with num_ctx=16384 still produced
#     `-c 262144`. Verified.
#   * `OLLAMA_CONTEXT_LENGTH` is a SERVER-WIDE default. Once `ollama serve` is
#     restarted with it (observed: server start 21:38, runner came up at
#     `-c 131072`, scheduler logged system_free=3.7GiB and did not escalate), it is
#     honoured. But it is GLOBAL: it cannot differ per model, and this box needs
#     131072 for gemma4 yet only 32768 for the 27B Mid tier - one value cannot
#     express both. It also silently does nothing until the server is restarted,
#     which is exactly the kind of invisible state that produced the original bug.
#   * A tag cap is route-independent and per-model, so it is the mechanism used here.
#     Verified 100% GPU at num_ctx 32768 / 65536 / 98304 / 131072 / 196608.
#
# IDEMPOTENT: safe to re-run. Rebuilds a tag only if it is missing or its
# num_ctx differs from the target.
#
# See: runtime/AIPC1-MEMORY-OPTIMIZATION-2026-10-16.md

[CmdletBinding()]
param(
    # Back-compat single-tag mode. With no switches the script builds the full
    # canonical set; pass -Target to build just one.
    [int]    $NumCtx = 0,
    [string] $Source = '',
    [string] $Target = ''
)

$ErrorActionPreference = 'Stop'

$ollama = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
if (-not (Test-Path $ollama)) {
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "ollama.exe not found (looked in $ollama and PATH)" }
    $ollama = $cmd.Source
}

# The canonical capped roster. Keep in sync with deploy/client-bundle/.env
# (PACGATE_MODEL_*), ollama-models.txt and the $localDerived map in install.ps1.
$Capped = @(
    [pscustomobject]@{ Target = 'gemma4-legal:12b-chat'; Source = 'gemma4:12b-it-q8_0';     NumCtx = 131072 }
    [pscustomobject]@{ Target = 'qwen3.8-legal:27b-mid'; Source = 'qwen3.8:27b-mtp-q4_K_M'; NumCtx = 32768  }
)

if ($Target) {
    if (-not $Source) { throw "-Target requires -Source" }
    if ($NumCtx -le 0) { throw "-Target requires -NumCtx" }
    $Capped = @([pscustomobject]@{ Target = $Target; Source = $Source; NumCtx = $NumCtx })
}

function Get-NumCtx([string]$tag) {
    $r = Invoke-OllamaQuiet @('show', $tag, '--parameters')
    if ($r.ExitCode -ne 0) { return $null }
    $line = $r.Output | Where-Object { $_ -match '^\s*num_ctx\s+(\d+)' } | Select-Object -First 1
    if ($line -and $line -match '(\d+)') { return [int]$Matches[1] }
    return $null
}

# Windows PowerShell 5.1 trap (documented in install.ps1 and
# smoke-deer-flow-outputs.ps1): under $ErrorActionPreference = 'Stop', ANY native
# command that writes to stderr becomes a TERMINATING error once a redirection
# (2>&1 / 2>$null / *>) is attached. `ollama show <not-yet-created-tag>` writes the
# model-not-found message to stderr, so probing a tag that does not exist yet would
# kill this script on a FRESH install - exactly the run that needs it. Lower the
# preference for the duration of the call and restore it; $LASTEXITCODE survives
# the boundary. PowerShell 7 is unaffected either way.
function Invoke-OllamaQuiet {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $ollama @Arguments 2>&1
        return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Ensure-Capped($spec) {
    Write-Host "ensure-context-capped-model: $($spec.Target)  num_ctx=$($spec.NumCtx)  FROM $($spec.Source)"

    if ((Invoke-OllamaQuiet @('show', $spec.Source)).ExitCode -ne 0) {
        throw "Source tag '$($spec.Source)' is not installed. Run: ollama pull $($spec.Source)"
    }

    $current = Get-NumCtx $spec.Target
    if ($current -eq $spec.NumCtx) {
        Write-Host "  [ok] already exists with num_ctx=$($spec.NumCtx) - nothing to do."
        return
    }
    if ($null -ne $current) {
        Write-Host "  [..] exists with num_ctx=$current - rebuilding at $($spec.NumCtx)."
    } else {
        Write-Host "  [..] missing - creating at num_ctx=$($spec.NumCtx)."
    }

    $mf = Join-Path $env:TEMP "Modelfile.$($spec.Target -replace '[:/]','-')"
    @"
FROM $($spec.Source)
PARAMETER num_ctx $($spec.NumCtx)
PARAMETER temperature 1
PARAMETER top_k 64
PARAMETER top_p 0.95
"@ | Set-Content -Path $mf -Encoding ASCII

    $create = Invoke-OllamaQuiet @('create', $spec.Target, '-f', $mf)
    if ($create.ExitCode -ne 0) {
        Remove-Item $mf -Force -ErrorAction SilentlyContinue
        throw "ollama create failed for $($spec.Target) (exit $($create.ExitCode)): $($create.Output -join ' ')"
    }
    Remove-Item $mf -Force -ErrorAction SilentlyContinue

    $now = Get-NumCtx $spec.Target
    if ($now -ne $spec.NumCtx) { throw "verification failed: '$($spec.Target)' reports num_ctx=$now, expected $($spec.NumCtx)" }
    Write-Host "  [ok] created and verified with num_ctx=$($spec.NumCtx)."
}

foreach ($spec in $Capped) { Ensure-Capped $spec }

Write-Host ""
Write-Host "Verify the runner fits in VRAM. In 'ollama ps', PROCESSOR should show"
Write-Host "100% GPU for gemma4-legal:12b-chat (the 27B Mid tier still shares some"
Write-Host "layers with the CPU by design):
  ollama run gemma4-legal:12b-chat `"Say OK`"
  ollama ps"
