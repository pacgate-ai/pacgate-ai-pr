$ErrorActionPreference = 'Continue'
$repo = 'c:\Users\pacga\github-pr\pacgate-law'
$pa   = Join-Path $repo 'pacgate-ai'
$src  = 'C:\pacgate-ai-pr'
$out  = Join-Path $repo 'runtime\relocate\E2E-STATUS.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add($s); Write-Host $s }

A 'END-TO-END STATUS'
A ('=' * 78)

# ============ 1. is the frontend failure caused by the relocation? ==========
A "`n=== 1. Is the deer-flow-frontend failure a relocation defect? ==="
A ''
A '  The build failed because COPY deploy/deer-flow-src/frontend was not found.'
A ''
A '  FINDING: deploy/deer-flow-src is GITIGNORED and UNTRACKED in the original'
A '  repo (0 tracked files; 574 files / 31.3 MB present on disk, ignored by'
A '  .gitignore:42). It is a GENERATED artifact - build-frontend.ps1 clones it'
A '  from the bytedance/deer-flow tag on demand.'
A ''
A '  So the failure is NOT a relocation defect - the directory was never in git'
A '  and never should have been migrated as source.'
A ''
A '  BUT it is a real (small) gap in MY cutover: the old repo had it on disk'
A '  from a previous build, and my runtime-state copy step transferred data/,'
A '  openviking/, .env, node_modules - but MISSED deploy/deer-flow-src.'
A '  Consequence: the frontend cannot build here until it is regenerated.'
A ''
foreach ($p in @(
        @{ l = 'original repo  (C:\pacgate-ai-pr)';   d = "$src\deploy\deer-flow-src" },
        @{ l = 'monorepo       (pacgate-ai)';         d = "$pa\deploy\deer-flow-src" })) {
    A ("  {0,-34} {1}" -f $p.l, $(if (Test-Path $p.d) { 'present on disk' } else { 'ABSENT' }))
}
A ''
A '  FIX (supported path): run deploy/build-frontend.ps1, which clones the'
A '  pinned source first and then builds. Or copy the 31.3 MB from the old repo.'

# ============ 2. build matrix ===============================================
A "`n=== 2. Build matrix ==="
$rows = @(
    @{ n = 'pacgate-api (Rust)';        img = 'pacgate-api:local-verify';          r = 'PASS';  note = 'built, ran against live DB, served HTTP 4/4' },
    @{ n = 'pacgate-mcp (Python)';      img = 'pacgate-mcp:local-verify';        r = 'PASS';  note = 'cached layers' },
    @{ n = 'deer-flow-pacgate';         img = 'deer-flow-pacgate:local-verify';  r = 'PASS';  note = 'exit=0, 3919.8s (65 min)' },
    @{ n = 'deer-flow-frontend';        img = 'deer-flow-frontend:local-verify'; r = 'FAIL*'; note = 'needs build-frontend.ps1 (clones source first)' }
)
A ("  {0,-24} {1,-10} {2}" -f 'BUILD', 'RESULT', 'NOTE')
A ('  ' + ('-' * 74))
foreach ($r in $rows) { A ("  {0,-24} {1,-10} {2}" -f $r.n, $r.r, $r.note) }

A "`n=== 3. Images actually present ==="
foreach ($r in $rows) {
    $found = @(docker images --format '{{.Repository}}:{{.Tag}}|{{.Size}}' | Where-Object { $_ -like "$($r.img)*" })
    A ("  {0,-34} {1}" -f $r.img, $(if ($found) { ($found -join '') } else { '(not built)' }))
}

# ============ 4. relocation deliverables ====================================
A "`n=== 4. Relocation deliverables (the actual task) ==="
$importOk = (@(& git -C $repo ls-tree -r --name-only HEAD | Where-Object { $_ -like 'pacgate-ai/*' }).Count) -gt 0
& git -C $repo cat-file -e 9d8fc3b 2>$null
$commitOk = ($LASTEXITCODE -eq 0)
$cf = "$(docker inspect pacgate-db 2>$null | Select-String -Pattern 'config_files' | ForEach-Object { $_.Line })"
$pathOk = $cf -like '*pacgate-law*'

A ("  {0,-30} {1,-6} {2}" -f 'content imported',          $(if ($importOk) { 'OK' } else { 'FAIL' }), 'pacgate-ai/* files present')
A ("  {0,-30} {1,-6} {2}" -f '9d8fc3b import commit',     $(if ($commitOk) { 'OK' } else { 'FAIL' }), 'the import commit exists')
A ("  {0,-30} {1,-6} {2}" -f 'stack on new path',         $(if ($pathOk) { 'OK' } else { 'FAIL' }), $cf)

# ============ 5. containers / volumes =======================================
A "`n=== 5. Runtime ==="
A ("  containers running : {0}" -f @(docker ps -q).Count)
$vol = (docker inspect pacgate-db --format '{{json .Mounts}}' 2>$null | ConvertFrom-Json)
$v = @($vol | Where-Object { $_.Destination -eq '/var/lib/postgresql/data' } | Select-Object -First 1).Name
A ("  pacgate-db volume  : {0}" -f $v)
$t = (& docker exec pacgate-db psql -U pacgate -d pacgate -tAc 'select count(*) from tenants;' 2>&1) -join ''
A ("  tenants in DB      : {0}" -f $t.Trim())

# ============ 6. outstanding ================================================
A "`n=== 6. Outstanding (why this is NOT fully e2e) ==="
A ''
A '  1. NO GIT REMOTE. github.com is reachable but gh is not authenticated.'
A '     The monorepo is still single-copy-on-this-disk despite the mirror.'
A '  2. deer-flow-frontend not built (needs its documented entry point).'
A '  3. Credential rotation OUTSTANDING - 4 files still publicly readable'
A '     on GitHub. Deleting cannot un-publish a commit.'
A '  4. Task 5 (archive C:\pacgate-ai-pr) not done - intentionally deferred.'
A '  5. pacgate-ai-assets/ deferred (would need deleting its .git).'
A '  6. Containers still run PULLED images, not the ones just built. Swapping'
A '     them in is an untested deployment step.'

A "`n=== VERDICT ==="
A '  Relocation: ESSENTIALLY DONE. Content imported, stack cut over and verified,'
A '              platform builds and runs from the new path.'
A '  Fully E2E:  NO - see section 6. The two that matter are the missing git'
A '              remote and the un-rotated credentials.'

[System.IO.File]::WriteAllLines($out, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote $out"