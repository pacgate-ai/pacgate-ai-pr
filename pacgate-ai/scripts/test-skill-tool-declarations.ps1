# Test: every `allowed-tools` declaration in a SKILL.md must resolve to something real.
#
# WHY THIS EXISTS
#
# `filter_tools_by_skill_allowed_tools` (patches/deer-flow-tool-policy.py) unions
# every skill's `allowed-tools` declaration and keeps any tool matching one of
# them. Today that union is larger than the loaded surface, so nothing is dropped
# and a bad declaration is invisible: 162 tools in, 162 kept, 0 dropped
# (measured 2026-10-30 on 0.2.7). The moment an operator narrows the surface --
# enables a single skill, or turns on the qcc-* servers that 11 skills already
# reference -- a declaration that names a non-existent tool silently removes
# capability instead of failing.
#
# Found 2026-10-30: three declarations named tools that exist nowhere:
#   - `markitdown`          (diligence-issue-extraction, tabular-review)
#       markitdown is a CLI in the image, not an MCP tool. It is reachable only
#       through `bash`, which those skills also declare -- so the entry was dead
#       weight that trained readers to think a markitdown tool existed.
#   - `review_skill_package` (skill-reviewer)
#       no such tool in this build; the skill needs read_file/grep/glob/ls.
# Those are fixed. The qcc-* entries are NOT defects: those servers are
# configured and authenticated (probed 200 on qcc-company/-risk/-legal-case/
# -document, 60 tools total) and merely `enabled: false`, so the declaration is
# correct for a deployment that turns them on.
#
# WHAT IT ASSERTS
#
#   A1  The skill set loads inside the container (60 skills).
#   A2  Every declaration resolves to a loaded tool OR names a server that is
#       configured-but-disabled (reported, not failed).
#   A3  No declaration names something that exists NOWHERE: not a loaded tool, not
#       a configured server, not a built-in. This is the real defect class.
#   A4  No skill declares an `allowed-tools` list that resolves to ZERO tools.
#       Such a skill would be given no tools at all once any other skill declares
#       the field -- a silent capability wipe.
#
# Usage:  powershell -File scripts/test-skill-tool-declarations.ps1
# Exit:   0 = pass (warnings allowed), 1 = a real defect, 2 = could not check.

[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$Container = 'deer-flow'
)

$ErrorActionPreference = 'Continue'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$script:passed = 0
$script:failed = 0
$script:warned = 0

function Pass($m) { Write-Host "  [PASS] $m" -ForegroundColor Green; $script:passed++ }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:failed++ }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:warned++ }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

Write-Host '=== skill allowed-tools declarations resolve to real tools ===' -ForegroundColor Cyan

$running = (& docker ps --filter "name=^/$Container$" --format '{{.Names}}' 2>&1) -join ''
if ($running -notmatch [regex]::Escape($Container)) {
    Write-Host "RESULT: SKIP - container '$Container' is not running; cannot check." -ForegroundColor Yellow
    exit 2
}

$probe = @'
import json, os, sys, traceback

out = {"ok": False, "checks": [], "error": None, "skills": 0}

def check(name, cond, detail=""):
    out["checks"].append({"name": name, "pass": bool(cond), "detail": str(detail)})

try:
    from deerflow.skills.storage.local_skill_storage import LocalSkillStorage
    from deerflow.tools.tools import get_available_tools
    from deerflow.config.extensions_config import ExtensionsConfig

    skills = LocalSkillStorage().load_skills()
    out["skills"] = len(skills)
    check("A1 the skill set loads", len(skills) > 0, f"{len(skills)} skills")

    tools = {t.name for t in get_available_tools(model_name="gemma4-12b-local")}
    ext = ExtensionsConfig.from_file()
    configured = set((ext.mcp_servers or {}).keys())
    enabled = {n for n, s in (ext.mcp_servers or {}).items() if getattr(s, "enabled", False)}

    def resolves(decl):
        n = decl.replace("-", "_")
        return any(t == decl or t.startswith(n + "_") for t in tools)

    missing_everywhere = []
    disabled_only = []
    empty_skills = []

    for s in skills:
        at = s.allowed_tools
        if at is None:
            continue
        resolved = [d for d in at if resolves(d)]
        if not resolved:
            empty_skills.append(s.name)
        for d in at:
            if resolves(d):
                continue
            if d in configured and d not in enabled:
                disabled_only.append((s.name, d))
            elif d.replace("-", "_") in {c.replace("-", "_") for c in configured}:
                disabled_only.append((s.name, d))
            else:
                missing_everywhere.append((s.name, d))

    check("A3 no declaration names a tool that exists nowhere",
          not missing_everywhere, missing_everywhere[:12])
    check("A4 no skill resolves to an empty tool set",
          not empty_skills, empty_skills)

    out["disabled_only"] = disabled_only
    out["ok"] = True
except Exception:
    out["error"] = traceback.format_exc()

print("PROBE_JSON:" + json.dumps(out))
'@

$probePath = '/tmp/_skill_decl_probe.py'
$probe | & docker exec -i $Container sh -c "cat > $probePath" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail 'could not stage the probe inside the container'
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}

$raw = (& docker exec $Container /app/backend/.venv/bin/python $probePath 2>&1) -join "`n"
& docker exec $Container rm -f $probePath 2>&1 | Out-Null

$line = ($raw -split "`n" | Where-Object { $_ -match '^PROBE_JSON:' } | Select-Object -First 1)
if (-not $line) {
    Fail 'A1 the skill set could not be loaded (probe crashed)'
    Info (($raw -split "`n" | Select-Object -Last 12) -join "`n")
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}

$data = ($line -replace '^PROBE_JSON:', '') | ConvertFrom-Json
if (-not $data.ok) {
    Fail 'A1 the skills loaded but the probe raised'
    Info $data.error
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}

foreach ($c in $data.checks) {
    if ($c.pass) { Pass ("{0} ({1})" -f $c.name, $c.detail) }
    else { Fail ("{0} (got: {1})" -f $c.name, $c.detail) }
}

# Declarations that point at a configured-but-DISABLED server are legitimate:
# the skill is ready for a deployment that enables it. Report, do not fail.
if ($data.disabled_only -and $data.disabled_only.Count -gt 0) {
    $byServer = $data.disabled_only | Group-Object { $_[1] }
    foreach ($g in $byServer) {
        Warn ("{0} skill(s) declare '{1}' - server configured but enabled:false (legitimate, inert today)" -f $g.Count, $g.Name)
    }
}

Write-Host ''
if ($script:failed -gt 0) {
    Write-Host "RESULT: FAIL - $($script:failed) failure(s), $($script:passed) passed, $($script:warned) warning(s)." -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: every declaration resolves. ($($script:passed) passed, $($script:warned) warning(s))" -ForegroundColor Green
exit 0
