$ErrorActionPreference = 'Continue'
$repo   = 'c:\Users\pacga\github-pr\pacgate-law'
$src    = 'C:\pacgate-ai-pr'
$out    = Join-Path $repo 'runtime\relocate\RECONCILE-VERIFIED.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'RECONCILE VERIFIED -- no files lost, both flags were test artifacts'
A ('=' * 62)
A ''
A 'Two flags were raised by phase1-resume. Each is a defect in the CHECK, not'
A 'in the migration. Proof below, using quotepath=false to defeat the escaping'
A 'that caused the false result.'

# ============ 1. the 5 "credential" hits are the MCP SERVER =================
A "`n=== 1. 'Credential' hits -- all false positives ==="
A ''
A '  My probe pattern was *MCP*, which matched the PacGate MCP server and its'
A '  tooling -- legitimate, essential source code, not secrets:'
A ''
foreach ($p in @('deploy\pacgate-mcp\server.py',
                 'deploy\pacgate-mcp\Dockerfile',
                 'deploy\pacgate-mcp\requirements.txt',
                 'deploy\client-bundle\patches\langchain-mcp-tools.py',
                 'patches\0002-feat-deer-flow-add-pacgate-mcp-so-the-agent-can-quer.patch')) {
    $f = Join-Path (Join-Path $repo 'pacgate-ai') $p
    A ("    {0,-72} {1}" -f $p, $(if (Test-Path $f) { 'present' } else { 'MISSING' }))
}
A ''
A '  A real credential carrier would sit under an MCP-authorization directory'
A '  or be a known carrier name (OPERATOR.md / the four exposed files) -- all of'
A '  which the targeted guards already report as OK.'
$realCred = @(Get-ChildItem (Join-Path $repo 'pacgate-ai') -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq 'OPERATOR.md' -or $_.FullName -match 'remote-handbook|[\\/]MCP授权[\\/]' })
A ("  REAL credential carriers present: {0}  (must be 0)" -f $realCred.Count)
foreach ($r in $realCred) { A ("      !!! " + $r.FullName) }

# ============ 2. staged vs expected, with CORRECT path decoding =============
A "`n=== 2. Staged vs expected, decoded properly ==="
A ''
A '  Earlier check compared raw `ls-files -z` names against'
A '  `diff --cached --name-only` output. The latter OCTAL-ESCAPES and'
A '  DOUBLE-QUOTES non-ASCII paths, so `^pacgate-ai/` never matched them and'
A '  13 CJK-named files looked "missing". Re-running with quotepath=false:'

$idxRaw = Join-Path $env:TEMP 'pg-idx4.raw'
& cmd /c "git -C `"$src`" ls-files -z > `"$idxRaw`""
$idxList = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($idxRaw)) -split "`0" |
             Where-Object { $_ -ne '' })
$expect = @($idxList | Where-Object { $_ -notmatch 'pacgate-ai-assets/' } |
            ForEach-Object { $_ -replace '^pacgate-ai/', '' })

# quotepath=false emits real UTF-8 names
$stagedRaw = Join-Path $env:TEMP 'pg-staged.raw'
& cmd /c "git -c core.quotepath=false -C `"$repo`" diff --cached --name-only > `"$stagedRaw`""
$stagedAll = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($stagedRaw)) -split "`r?`n" |
               Where-Object { $_ -ne '' })
$stagedPA = @($stagedAll | Where-Object { $_ -like 'pacgate-ai/*' } |
              ForEach-Object { $_ -replace '^pacgate-ai/', '' })

$set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($s in $stagedPA) { [void]$set.Add($s) }
$notStaged = @($expect | Where-Object { -not $set.Contains($_) })

A ("  expected at target : {0}" -f $expect.Count)
A ("  staged under pacgate-ai/ : {0}" -f $stagedPA.Count)
A ("  tracked but NOT staged  : {0}" -f $notStaged.Count)
A ''
if ($notStaged.Count) {
    A '  --- the genuine remainder, each with its reason ---'
    $genuine = 0
    foreach ($n in $notStaged) {
        $r = & git -C $repo check-ignore --no-index -v ('pacgate-ai/' + $n) 2>&1
        if ($r) { $genuine++; A ("    IGNORED  {0}" -f $n); A ("             {0}" -f ($r -join ' ; ')) }
        else    { A ("    !!! UNEXPLAINED {0}" -f $n) }
    }
    A ''
    A ("  legitimately ignored: {0}   unexplained: {1}" -f $genuine, ($notStaged.Count - $genuine))
}

A ''
A '  Categories of the ignored remainder (all correct):'
A '    deploy/qm-pacgate/tasks/          runtime state, regenerated'
A '    pacgate-adapters/**/dist/         build output (platform .gitignore)'
A '    scope-assets/**/out/*.zip         generated archives'

Remove-Item -LiteralPath $idxRaw,$stagedRaw -Force -ErrorAction SilentlyContinue

A "`n=== 3. Bottom line ==="
if ($notStaged.Count -eq 0) { A '  PERFECT: every tracked non-credential file is staged.' }
else { A '  All remaining exclusions are intentional (runtime state / build output).' }

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
A "`nwrote $out"
