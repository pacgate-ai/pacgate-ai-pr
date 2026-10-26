# Verify the 8 files upstream 86a9feb touches, classifying each against our local subtree.
# Read-only. Prints one line per file: SAME / DIFFERS (local delta) / ABSENT.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$git = 'C:\Program Files\Git\cmd\git.exe'
$files = @(
    'deploy/client-bundle/compose.bundle.yaml',
    'deploy/client-bundle/compose.prod.yaml',
    'deploy/client-bundle/patches/deer-flow-memory-prompt.py',
    'plans/031-aipc-latency-root-cause-and-fix.md',
    'plans/README.md',
    'scripts/run-all-checks.ps1',
    'scripts/test-memory-lane.ps1',
    'scripts/test-memory-prompt-stability.ps1'
)

function Test-Blob([string]$rev, [string]$path) {
    # `trustExitCode` is NOT used here: git writes "fatal:" to stderr on a
    # missing path, and under $ErrorActionPreference='Stop' PS 5.1 promotes
    # native stderr to a terminating error. Redirect into a variable so the
    # exit code is the only signal.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & $git cat-file -e ("{0}:{1}" -f $rev, $path) 2>&1
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
    return ($LASTEXITCODE -eq 0)
}

function Get-Blob([string]$rev, [string]$path) {
    return (& $git rev-parse ("{0}:{1}" -f $rev, $path)).Trim()
}

foreach ($f in $files) {
    $localPath = "pacgate-ai/$f"
    $hasLoc = Test-Blob 'HEAD' $localPath
    $hasUp = Test-Blob '337fb9d' $f
    if (-not $hasLoc) {
        $verdict = 'LOCAL: ABSENT  (upstream CREATES it)'
    }
    elseif (-not $hasUp) {
        $verdict = 'UPSTREAM BASE: ABSENT  (local-only file)'
    }
    else {
        $l = Get-Blob 'HEAD' $localPath
        $u = Get-Blob '337fb9d' $f
        if ($l -eq $u) { $verdict = 'SAME  (clean - swap is byte-identical)' }
        else { $verdict = "DIFFERS  -> LOCAL DELTA MUST BE RE-APPLIED" }
    }
    Write-Output ("{0,-58} {1}" -f $f, $verdict)
}
