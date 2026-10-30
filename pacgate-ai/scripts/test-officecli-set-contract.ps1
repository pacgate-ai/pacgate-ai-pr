# officecli `set` path-contract gate: the selector form `set` accepts is the one the
# sandbox forbids, so every document skill must use `batch --input`.
#
# WHY THIS EXISTS. Found 2026-10-30 while regenerating the NDA deliverables. officecli
# is internally inconsistent about selector syntax:
#
#     officecli get <f> "body/p[1]"    -> resolves
#     officecli set <f> "body/p[1]"    -> Error: No elements matched selector
#     officecli set <f> "/body/p[1]"   -> works
#
# But deer-flow's sandbox (`validate_local_bash_command_paths`) rejects any token that
# starts with `/` on a bash command line as an unsafe absolute path:
#
#     Error: Unsafe absolute paths in command: /tr[1]/tc[1]. Use paths under /mnt/user-data
#
# So the ONLY form `set` accepts is the one the sandbox refuses. An agent that follows
# the obvious path burns its whole budget discovering this - measured: one run spent
# 599 s and produced zero deliverables, then reported the tool as "unusable".
#
# The workaround is `officecli batch <file> --input <json>`: the `/` lives in file
# CONTENT, never in the command string, so the sandbox never sees it. This gate pins
# that contract so a future officecli upgrade (or a sandbox change) cannot silently
# break document generation again.
#
# Asserts:
#   S1  `get` accepts the bare selector            (baseline: the tool works at all)
#   S2  `set` REJECTS the bare selector            (the inconsistency still exists)
#   S3  `set` accepts the leading-slash selector   (the only form that works)
#   S4  `batch --input` succeeds with `/` paths    (the workaround)
#   S5  the batch edit actually landed             (not a no-op)
#   S6  the result validates clean                 (no schema damage)
#   S7  CJK survives the batch path                (the legal-document requirement)
#   S8  the playbook documents the workaround      (skills inherit it)
#
# S2 is deliberately an assertion that the DEFECT exists. If officecli ever fixes the
# inconsistency, S2 fails and this gate tells you to delete the workaround - which is
# the correct outcome, not a false alarm.
#
# Container-only: officecli exists ONLY in deer-flow-pacgate. Exits 2 (CANNOT CHECK)
# when that image is not available locally.
#
# Exit 2 means CANNOT CHECK and must never be read as a failure of the code.
[CmdletBinding()]
param(
    [string]$Image = '',
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  [PASS] $name" -ForegroundColor Green; $script:pass++ }
    else {
        Write-Host "  [FAIL] $name" -ForegroundColor Red
        if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
        $script:fail++
    }
}
function CannotCheck($why) {
    Write-Host "[SKIP] CANNOT CHECK: $why" -ForegroundColor Yellow
    Write-Host "RESULT: $pass passed, $fail failed (CANNOT CHECK)" -ForegroundColor Yellow
    exit 2
}

Write-Host '=== officecli set/batch path-contract gate ===' -ForegroundColor Cyan

if (-not $Image) {
    try { $Image = (docker inspect deer-flow --format '{{.Config.Image}}' 2>$null | Out-String).Trim() } catch { }
}
if (-not $Image) {
    . (Join-Path $PSScriptRoot 'lib/Release-ImageState.ps1')
    $ver = Get-ReleaseVersion -RepoRoot $repoRoot
    if ($ver) { $Image = "ghcr.io/jzkk720/deer-flow-pacgate:$ver" }
}
if (-not $Image) { CannotCheck 'could not determine the deer-flow image that carries officecli' }

$null = docker image inspect $Image 2>&1
if ($LASTEXITCODE -ne 0) { CannotCheck "$Image is not present locally (release window, or not pulled)" }
Write-Host "  image: $Image" -ForegroundColor DarkGray

$work = Join-Path ([System.IO.Path]::GetDirectoryName($PSScriptRoot)) "deploy/officecli-set-gate-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# The probe script runs INSIDE the container. Written with LF and no CR so `sh` parses
# it; the JSON heredoc keeps `/` out of every command line, which is the whole point.
$probe = @'
set -u
cd /w
rm -f t.docx b.json

officecli create t.docx >/dev/null 2>&1
officecli add t.docx body --type paragraph --prop text="原始文字" >/dev/null 2>&1

echo "--- S1 get bare ---"
officecli get t.docx "body/p[1]" 2>&1 | head -1

echo "--- S2 set bare ---"
officecli set t.docx "body/p[1]" --prop text="BARE" 2>&1 | head -1

echo "--- S3 set slash ---"
officecli set t.docx "/body/p[1]" --prop text="SLASH" 2>&1 | head -1

echo "--- S4 batch input ---"
cat > b.json <<'EOF'
[
 {"command":"set","path":"/body/p[1]","props":{"text":"批量写入的中文"}},
 {"command":"add","parent":"/body","type":"paragraph","props":{"text":"第二条 违约责任"}}
]
EOF
officecli batch t.docx --input b.json 2>&1 | tail -2

echo "--- S5 landed ---"
officecli get t.docx "body/p[1]" 2>&1 | head -1

echo "--- S6 validate ---"
officecli validate t.docx 2>&1 | tail -1

echo "--- S7 cjk ---"
officecli view t.docx text 2>&1 | head -3
'@

$probePath = Join-Path $work 'probe.sh'
[System.IO.File]::WriteAllText($probePath, ($probe -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$out = (docker run --rm -v "${work}:/w" --entrypoint sh $Image -c "OFFICECLI_SKIP_UPDATE=1 sh /w/probe.sh 2>&1") | Out-String
if (-not $KeepArtifacts) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

function Section($name) {
    $m = [regex]::Match($out, "(?s)--- $name ---\r?\n(.*?)(?=\r?\n--- |\z)")
    if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return '' }
}

$s1 = Section 'S1 get bare'
$s2 = Section 'S2 set bare'
$s3 = Section 'S3 set slash'
$s4 = Section 'S4 batch input'
$s5 = Section 'S5 landed'
$s6 = Section 'S6 validate'
$s7 = Section 'S7 cjk'

Write-Host ''
Write-Host 'selector syntax'
Check 'S1 `get` accepts the bare selector' ($s1 -match 'paragraph') "got: $s1"
Check 'S2 `set` REJECTS the bare selector (the defect this gate works around)' `
    ($s2 -match 'No elements matched selector') `
    "officecli may have fixed the inconsistency - if so, delete the batch workaround and this assertion. got: $s2"
Check 'S3 `set` accepts the leading-slash selector' ($s3 -match 'Updated') "got: $s3"

Write-Host ''
Write-Host 'batch --input workaround'
Check 'S4 `batch --input` succeeds with `/` paths' ($s4 -match 'succeeded' -and $s4 -notmatch '[1-9]\d* failed') "got: $s4"
Check 'S5 the batch edit actually landed' ($s5 -match '批量写入的中文') "got: $s5"
Check 'S6 the result validates clean' ($s6 -match 'no errors found') "got: $s6"
Check 'S7 CJK survives the batch path' ($s7 -match '批量写入的中文' -and $s7 -match '第二条 违约责任') "got: $s7"

Write-Host ''
Write-Host 'documentation'
$pb = Join-Path $repoRoot 'deploy/client-bundle/playbooks/nda-playbook.md'
$pbText = if (Test-Path $pb) { Get-Content -Raw -LiteralPath $pb } else { '' }
Check 'S8 the playbook documents the batch --input workaround' `
    ($pbText -match 'batch\s+.*--input' -and $pbText -match 'No elements matched selector') `
    "playbook must warn that `set` needs a leading / and that it must go through batch --input: $pb"

Write-Host ''
if ($fail -eq 0) {
    Write-Host "RESULT: $pass passed, 0 failed" -ForegroundColor Green
    exit 0
}
Write-Host "RESULT: $pass passed, $fail failed" -ForegroundColor Red
exit 1
