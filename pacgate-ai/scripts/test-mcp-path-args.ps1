# Test: MCP tool ARGUMENTS must have /mnt/user-data resolved before the server sees them.
#
# WHY THIS EXISTS
#
# The sandbox tools translate DeerFlow's virtual path contract; the MCP bridge
# did not. `deerflow/sandbox/tools.py` owns `replace_virtual_path` and applies it
# in bash/read_file/write_file/glob/grep/ls/str_replace. `deerflow/mcp/tools.py`
# only translated paths in the RESULT (`_local_uri_to_virtual_path`) and passed
# ARGUMENTS to the server verbatim:
#
#     call_tool_result = await session.call_tool(original_name, arguments)
#
# Every agent-facing surface tells the model to use `/mnt/user-data/...` (that is
# what `<uploaded_files>` prints and what every SKILL.md assumes), so a document
# tool received a path that does not exist on the container filesystem. Measured
# live 2026-10-30 on 0.2.7:
#
#     officecli_officecli({"command": "create /mnt/user-data/outputs/x.docx"})
#       -> ToolException: Could not find a part of the path
#     officecli_officecli({"command": "create <real outputs path>/x.docx"})
#       -> Created: .../x.docx   (validate: no errors found)
#
# The visible symptom was reported as "officecli is not working". It was not:
# `scripts/test-officecli-mcp.ps1` passes 13/13 on the untouched server. The
# damage was worse than a clean error, because the model recovered by calling
# `pandoc` through the `bash` tool (whose command string IS rewritten) and
# shipped a .docx that fails `officecli validate` with 16 schema errors. Thread
# 7b05b461 recorded exactly that sequence.
#
# WHAT IT ASSERTS
#
#   A1  The patch file exists and is the mount target for the mcp module.
#   A2  BOTH compose files mount it (install.ps1 uses compose.prod.yaml, so a
#       bundle-only mount would leave the fix absent on the deployment path).
#   A3  The patched module imports cleanly inside the container.
#   A4  A plain string argument is rewritten (the common case).
#   A5  A pre-split argv ARRAY is rewritten element-wise (officecli accepts one).
#   A6  A nested object argument is rewritten (servers nest paths).
#   A7  A non-path argument is left byte-identical.
#   A8  None passes through unchanged (no crash on absent optional args).
#   A9  A longer sibling segment is NOT rewritten (`.../workspaceZZZ`).
#   A10 `/mnt/skills` is rewritten to the real skills dir.
#   A11 END TO END: officecli through the real MCP tool accepts
#       "/mnt/user-data/outputs/..." and the file validates clean. This is the
#       assertion the whole patch exists for; A1-A10 would all pass on a patch
#       that imported but never ran.
#   A12 No live thread state -> arguments untouched (stateless runs unchanged).
#
# Usage:  powershell -File scripts/test-mcp-path-args.ps1
# Exit:   0 = all assertions pass, 1 = a failure, 2 = could not check (no stack).

[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$Container = 'deer-flow'
)

$ErrorActionPreference = 'Continue'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$script:passed = 0
$script:failed = 0

function Pass($m) { Write-Host "  [PASS] $m" -ForegroundColor Green; $script:passed++ }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:failed++ }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

Write-Host '=== MCP argument path translation (/mnt/user-data -> real) ===' -ForegroundColor Cyan

$patchRel = 'deploy/client-bundle/patches/deer-flow-mcp-path-args.py'
$patchPath = Join-Path $RepoRoot ($patchRel -replace '/', '\')
$target = '/app/backend/packages/harness/deerflow/mcp/tools.py'

# --- A1: patch present and is the mount target --------------------------------
if (Test-Path $patchPath) {
    Pass 'A1 the patch file exists'

    $marker = Select-String -Path $patchPath -Pattern '_rewrite_virtual_paths_in_args' -SimpleMatch -Quiet
    if ($marker) { Pass 'A1 the patch defines the argument rewriter' }
    else { Fail 'A1 the patch file is present but does not define _rewrite_virtual_paths_in_args' }

    $calls = (Select-String -Path $patchPath -Pattern 'resolved_arguments' -SimpleMatch).Count
    if ($calls -ge 2) { Pass "A1 the rewriter is WIRED into the call path ($calls references)" }
    else { Fail "A1 the helper exists but is never called (references: $calls)" }

    $delegates = Select-String -Path $patchPath -Pattern 'replace_virtual_paths_in_command' -SimpleMatch -Quiet
    if ($delegates) { Pass 'A1 it delegates to the same resolver the bash tool uses (no drift)' }
    else { Fail 'A1 it re-implements path mapping instead of reusing replace_virtual_paths_in_command' }
} else {
    Fail "A1 the patch file is missing: $patchRel"
}

# --- A2: mount parity across BOTH compose files -------------------------------
$composeFiles = @('compose.bundle.yaml', 'compose.prod.yaml')
foreach ($cf in $composeFiles) {
    $cfPath = Join-Path $RepoRoot ('deploy/client-bundle/' + $cf)
    if (-not (Test-Path $cfPath)) { Fail "A2 $cf is missing"; continue }
    $mounted = Select-String -Path $cfPath -Pattern 'deer-flow-mcp-path-args.py' -SimpleMatch -Quiet
    if ($mounted) {
        Pass "A2 $cf mounts the patch over mcp/tools.py"
    } else {
        Fail "A2 $cf does NOT mount the patch (absent from the deployment path)"
        Info 'install.ps1 uses compose.prod.yaml; a bundle-only mount leaves the bug live.'
    }
}

# --- preflight: the stack must be up, or A3..A12 cannot say anything ----------
$running = (& docker ps --filter "name=^/$Container$" --format '{{.Names}}' 2>&1) -join ''
if ($running -notmatch [regex]::Escape($Container)) {
    Write-Host "RESULT: SKIP - container '$Container' is not running; A3-A12 cannot be checked." -ForegroundColor Yellow
    if ($script:failed -gt 0) { exit 1 }
    exit 2
}

# The mounted file must BE the patched one, not the upstream original.
$mounted = (& docker exec $Container grep -c '_rewrite_virtual_paths_in_args' $target 2>&1) -join ''
if ($mounted.Trim() -match '^[1-9]') {
    Pass 'A1 the MOUNTED file is the patched one'
} else {
    Fail "A1 the mounted file is NOT patched (marker count: $mounted)"
    Info 'The container is running the upstream file; officecli will reject /mnt paths.'
}

# --- A3..A12: drive the real module inside the container ----------------------
$probe = @'
import asyncio, json, os, sys, traceback

out = {"ok": False, "checks": [], "error": None}

def check(name, cond, detail=""):
    out["checks"].append({"name": name, "pass": bool(cond), "detail": str(detail)})

TID = "00000000-0000-4000-8000-000000000001"
UID = "00000000-0000-4000-8000-000000000002"
UD = f"/tmp/mcppath/{UID}/{TID}/user-data"
for sub in ("workspace", "uploads", "outputs"):
    os.makedirs(os.path.join(UD, sub), exist_ok=True)

THREAD_DATA = {
    "workspace_path": f"{UD}/workspace",
    "uploads_path": f"{UD}/uploads",
    "outputs_path": f"{UD}/outputs",
}

class FakeRT:
    """Minimal stand-in for the tool Runtime: only state/context/config are read."""
    def __init__(self, thread_data=THREAD_DATA):
        self.state = {"thread_data": thread_data} if thread_data else {}
        self.context = {"thread_id": TID}
        self.config = {"configurable": {"thread_id": TID}}

try:
    from deerflow.mcp.tools import _rewrite_virtual_paths_in_args as rw

    rt = FakeRT()

    # A4 plain string
    got = rw("create /mnt/user-data/outputs/a.docx", rt)
    check("A4 a plain string path is rewritten", got == f"create {UD}/outputs/a.docx", got)

    # A5 argv array (officecli accepts a pre-split command)
    got = rw(["create", "/mnt/user-data/outputs/a.docx"], rt)
    check("A5 an argv ARRAY is rewritten element-wise",
          got == ["create", f"{UD}/outputs/a.docx"], got)

    # A6 nested object
    got = rw({"f": {"path": "/mnt/user-data/uploads/x.pdf"}}, rt)
    check("A6 a nested object path is rewritten",
          got == {"f": {"path": f"{UD}/uploads/x.pdf"}}, got)

    # A7 non-path untouched
    got = rw("echo hello", rt)
    check("A7 a non-path argument is untouched", got == "echo hello", got)

    # A8 None untouched
    try:
        got = rw(None, rt)
        check("A8 None passes through without raising", got is None, got)
    except Exception as exc:
        check("A8 None passes through without raising", False, repr(exc))

    # A9 segment boundary
    got = rw("/mnt/user-data/workspaceZZZ/x", rt)
    check("A9 a longer sibling segment is NOT rewritten",
          got == f"{UD}/workspaceZZZ/x", got)

    # A10 skills mount
    got = rw("/mnt/skills/public/nda-review/SKILL.md", rt)
    check("A10 /mnt/skills is rewritten to the real skills dir",
          "/mnt/skills" not in got and got.endswith("/public/nda-review/SKILL.md"), got)

    # A12 a run with NO thread_id (stateless) must be left untouched.
    #     The fallback deliberately derives paths from the thread_id when the
    #     runtime carries no state -- runtime is never injected into MCP tools,
    #     so the state path is unreachable in production and deriving is the fix.
    #     What must NOT happen is rewriting for a run that has no thread at all.
    class NoThreadRT:
        state = {}
        context = {}
        config = {"configurable": {}}

    got = rw("create /mnt/user-data/outputs/a.docx", NoThreadRT())
    check("A12 a stateless run (no thread_id) leaves arguments untouched",
          got == "create /mnt/user-data/outputs/a.docx", got)

    # A11 end to end through the REAL MCP tool
    from deerflow.mcp.cache import get_cached_mcp_tools
    tools = {t.name: t for t in get_cached_mcp_tools()}
    oc = tools.get("officecli_officecli")
    if oc is None:
        check("A11 officecli accepts a virtual path end to end", False, "officecli tool not loaded")
    else:
        async def e2e():
            name = "virtual-path-gate.docx"
            r1 = await oc.coroutine(runtime=rt, command=f"create /mnt/user-data/outputs/{name}")
            r2 = await oc.coroutine(runtime=rt, command=f"add /mnt/user-data/outputs/{name} /body --type paragraph --prop text=PacGate")
            r3 = await oc.coroutine(runtime=rt, command=f"validate /mnt/user-data/outputs/{name}")
            return r1, r2, r3, os.path.join(UD, "outputs", name)
        r1, r2, r3, real = asyncio.run(e2e())
        created = "Created:" in str(r1)
        added = "Added" in str(r2) or "paragraph" in str(r2).lower()
        clean = "no errors" in str(r3).lower()
        check("A11 officecli ACCEPTS a /mnt/user-data path (create)",
              created, str(r1)[:180])
        check("A11 the same virtual path works for a follow-up edit",
              added, str(r2)[:180])
        check("A11 the produced document validates clean",
              clean and os.path.isfile(real), str(r3)[:180])
        try:
            os.remove(real)
        except OSError:
            pass

    out["ok"] = True
except Exception:
    out["error"] = traceback.format_exc()

print("PROBE_JSON:" + json.dumps(out))
'@

$probePath = '/tmp/_mcp_path_args_probe.py'
$probe | & docker exec -i $Container sh -c "cat > $probePath" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail 'could not stage the probe inside the container'
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}

$raw = (& docker exec $Container /app/backend/.venv/bin/python $probePath 2>&1) -join "`n"
& docker exec $Container rm -f $probePath 2>&1 | Out-Null
& docker exec $Container rm -rf /tmp/mcppath 2>&1 | Out-Null

$line = ($raw -split "`n" | Where-Object { $_ -match '^PROBE_JSON:' } | Select-Object -First 1)
if (-not $line) {
    Fail 'A3 the patched module could not be imported (probe crashed)'
    Info (($raw -split "`n" | Select-Object -Last 12) -join "`n")
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}

$data = ($line -replace '^PROBE_JSON:', '') | ConvertFrom-Json

if (-not $data.ok) {
    Fail 'A3 the module imported but the probe raised'
    Info $data.error
    Write-Host "RESULT: FAIL - $($script:failed) failure(s)." -ForegroundColor Red
    exit 1
}
Pass 'A3 the patched module imports cleanly inside the container'

foreach ($c in $data.checks) {
    if ($c.pass) { Pass $c.name } else { Fail ("{0} (got: {1})" -f $c.name, $c.detail) }
}

Write-Host ''
if ($script:failed -gt 0) {
    Write-Host "RESULT: FAIL - $($script:failed) failure(s), $($script:passed) passed." -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $($script:passed) passed, 0 failed" -ForegroundColor Green
exit 0
