# Prove the new gate is not blind: reverse the prompt block order (memory block
# back in front of the conversation), expect a FAIL, then restore from the exact
# original bytes and prove the file is byte-identical and green again.
#
# Line-array based, not string-replace based: this file is CRLF, so a search for
# "a`nb" never matches "a`r`nb" and the mutation silently no-ops (it did on the
# first attempt, which is why the guard below exists).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\pacgate-ai')

$patch = (Resolve-Path '.\deploy\client-bundle\patches\deer-flow-memory-prompt.py').Path
$gate = '.\scripts\test-memory-prompt-stability.ps1'

$orig = [System.IO.File]::ReadAllBytes($patch)
$origHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash
"orig_sha256=$origHash"

& powershell -NoProfile -ExecutionPolicy Bypass -File $gate *> $null
"baseline_exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw 'baseline already red - mutation test would prove nothing' }

try {
    $text = [System.Text.Encoding]::UTF8.GetString($orig)
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]]($text -split "`r`n"))
    if ($lines.Count -lt 2) { $lines.Clear(); $lines.AddRange([string[]]($text -split "`n")) }

    $convHdr = -1; $memHdr = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^New Conversation to Process:\s*$') { $convHdr = $i }
        if ($lines[$i] -match '^Current Memory State:\s*$') { $memHdr = $i }
    }
    if ($convHdr -lt 0 -or $memHdr -lt 0) { throw "block headers not found (conv=$convHdr mem=$memHdr)" }
    if ($convHdr -gt $memHdr) { throw 'template is already memory-first - unexpected baseline' }

    # Each block is header + 3 lines (<tag>, {placeholder}, </tag>).
    $convBlock = @($lines.GetRange($convHdr, 4))
    $memBlock = @($lines.GetRange($memHdr, 4))
    $gap = @($lines.GetRange($convHdr + 4, $memHdr - ($convHdr + 4)))

    $mutated = New-Object System.Collections.Generic.List[string]
    $mutated.AddRange([string[]]@($lines.GetRange(0, $convHdr)))
    $mutated.AddRange([string[]]$memBlock)
    $mutated.AddRange([string[]]$gap)
    $mutated.AddRange([string[]]$convBlock)
    $mutated.AddRange([string[]]@($lines.GetRange($memHdr + 4, $lines.Count - ($memHdr + 4))))

    [System.IO.File]::WriteAllBytes($patch, [System.Text.Encoding]::UTF8.GetBytes(($mutated -join $nl)))

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1 | Select-Object -Last 5
    "mutant_order_exit=$LASTEXITCODE"
    if ($LASTEXITCODE -eq 0) { throw 'gate PASSED on a reversed order - blind gate' }
}
finally {
    [System.IO.File]::WriteAllBytes($patch, $orig)
}

$restoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash
"restored_sha256=$restoredHash"
"byte_identical=$($restoredHash -eq $origHash)"

& powershell -NoProfile -ExecutionPolicy Bypass -File $gate *> $null
"restored_exit=$LASTEXITCODE"
