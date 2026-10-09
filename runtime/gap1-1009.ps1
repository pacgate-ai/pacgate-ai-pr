# Gap 1 execution: build the v0.1.25 release-prep commit in the worktree.
# Steps: (1) verify/insert patch mounts in compose.bundle.yaml, (2) insert
# summarization block into deer-flow-config.yaml (NO model_name - falls back
# to the default chat model, portable), (3) bump pins 0.1.24 -> 0.1.25,
# (4) validate compose config, (5) report status.
$ErrorActionPreference = 'Stop'
$wt = 'C:\Users\pacga\github-pr\pacgate-law\runtime\wt-v0125'

# --- 1. compose.bundle.yaml: insert the 2 patch mounts after the sync.py mount ---
$composePath = Join-Path $wt 'deploy\client-bundle\compose.bundle.yaml'
$bytes = [System.IO.File]::ReadAllBytes($composePath)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$anchor = '      - ./patches/deer-flow-sync.py:/app/backend/packages/harness/deerflow/tools/sync.py:ro'
$insertion = @'

      # Pacgate 2026-10-08: prefix-aware skill allowed-tools matching. Skills
      # declare bare MCP server names (pkulaw, yuandian-law, pacgate) but tool
      # names are prefixed (pkulaw_*, pacgate_pacgate_*); exact-match filtering
      # dropped ALL 137 MCP tools once any skill declared allowed-tools (agent
      # left with bash/read_file only). The patch matches exact or
      # "<normalized-declaration>_" prefixes.
      - ./patches/deer-flow-tool-policy.py:/app/backend/packages/harness/deerflow/skills/tool_policy.py:ro
      # Pacgate 2026-10-08: exclude skill-reviewer eval fixtures
      # (*/evals/fixtures/) from skill discovery - they are test data, not
      # user-facing skills (5 phantom skills, one with an empty allowed-tools).
      - ./patches/deer-flow-skill-storage.py:/app/backend/packages/harness/deerflow/skills/storage/skill_storage.py:ro
'@
if ($text.Contains('deer-flow-tool-policy.py')) {
    Write-Output 'compose: patch mounts ALREADY present (skipping insert)'
} elseif ($text.Contains($anchor)) {
    $text = $text.Replace($anchor, $anchor + $insertion)
    [System.IO.File]::WriteAllBytes($composePath, [System.Text.Encoding]::UTF8.GetBytes($text))
    Write-Output 'compose: patch mounts INSERTED'
} else {
    Write-Output 'compose: ANCHOR NOT FOUND - ABORT'
    exit 1
}

# --- 2. deer-flow-config.yaml: insert the summarization block before sandbox: ---
$cfgPath = Join-Path $wt 'deploy\client-bundle\deer-flow-config.yaml'
$bytes = [System.IO.File]::ReadAllBytes($cfgPath)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
if ($text.Contains('summarization:')) {
    Write-Output 'config: summarization block ALREADY present (skipping insert)'
} else {
    $anchor2 = 'sandbox:'
    $block2 = @'
# Pacgate 2026-10-09: ENABLE conversation summarization. Root cause this
# fixes: summarization was UNCONFIGURED (null -> disabled by default), so
# long threads grew unbounded. The trigger counts MESSAGE tokens only
# (~16k for 50 msgs) while real per-call input is ~83k (12k tools+system +
# 16k messages + cloud overhead), so the old 48k threshold was structurally
# unreachable - summarization never fired and every call re-sent the full
# 83k context (1.3-1.7M tokens burned per document run, 60-120s per call).
# All three 2026-10-08 stalls ("no astream output for 420s") happened at
# input=64-65k - exactly the 65536-token ctx slot Ollama allocates.
# 12000 message-tokens engages after ~40 messages; keep=12000 preserves the
# recent verbatim context. No model_name pin: the summarizer runs on the
# default chat model (same runner slot, no VRAM swap). Verified live
# 2026-10-09: hook fired, summary executed, next model call input bounded
# 32,770 (was 83k).
summarization:
  enabled: true
  trigger:
    - type: tokens
      value: 12000
  keep:
    type: tokens
    value: 12000
  trim_tokens_to_summarize: 8000

sandbox:
'@
    if ($text.Contains($anchor2)) {
        $text = $text.Replace($anchor2, $block2)
        [System.IO.File]::WriteAllBytes($cfgPath, [System.Text.Encoding]::UTF8.GetBytes($text))
        Write-Output 'config: summarization block INSERTED'
    } else {
        Write-Output 'config: ANCHOR NOT FOUND - ABORT'
        exit 1
    }
}

# --- 3. bump pins 0.1.24 -> 0.1.25 in both compose files ---
foreach ($cf in @('deploy\client-bundle\compose.bundle.yaml', 'deploy\client-bundle\compose.prod.yaml')) {
    $p = Join-Path $wt $cf
    $b = [System.IO.File]::ReadAllBytes($p)
    $t = [System.Text.Encoding]::UTF8.GetString($b)
    $count = ([regex]::Matches($t, ':0\.1\.24')).Count
    $t = $t -replace ':0\.1\.24', ':0.1.25'
    [System.IO.File]::WriteAllBytes($p, [System.Text.Encoding]::UTF8.GetBytes($t))
    Write-Output "bump: $cf - $count pins -> 0.1.25"
}

# --- 4. validate compose config ---
Push-Location (Join-Path $wt 'deploy\client-bundle')
# PS 5.1 treats docker's stderr warnings as errors under $ErrorActionPreference=Stop;
# run via cmd to get a clean exit code.
cmd /c "docker compose -f compose.bundle.yaml config > nul 2>&1"
$cfgExit = $LASTEXITCODE
if ($cfgExit -eq 0) { Write-Output 'compose config: VALID' } else { Write-Output "compose config: INVALID (exit $cfgExit)"; Pop-Location; exit 1 }
Pop-Location

# --- 5. status ---
Set-Location $wt
git add deploy/client-bundle/patches/deer-flow-tool-policy.py deploy/client-bundle/patches/deer-flow-skill-storage.py deploy/client-bundle/compose.bundle.yaml deploy/client-bundle/deer-flow-config.yaml deploy/client-bundle/compose.prod.yaml
Write-Output '--- staged ---'
git diff --cached --stat | Select-Object -Last 8
Write-Output '--- secret scan on staged diff ---'
$secretHits = git diff --cached | Select-String -Pattern 'api_key|API_KEY|Bearer|password|sk-|secret' | Select-Object -First 3
if ($secretHits) { Write-Output 'SECRET HITS FOUND:'; $secretHits } else { Write-Output '(clean)' }
