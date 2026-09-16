<#
.SYNOPSIS
    Captures a pinned inventory of every Docker container and image on this
    machine, and maps each container back to the compose project that owns it.

.DESCRIPTION
    Produces two files next to this script:
      - runtime-inventory.json  (machine-readable, full fidelity)
      - RUNTIME-INVENTORY.md    (human-readable, grouped by compose project)

    The point is reproducibility: for every running container we record the
    exact image digest, so a rebuild months from now can pin to the same bits
    instead of whatever a floating tag happens to point at.

.PARAMETER OutDir
    Directory to write the two output files into. Defaults to the script folder.

.EXAMPLE
    powershell -File .\capture-runtime.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not reliably populated while default parameter values are
# being bound (notably under `powershell -File` with a relative path), so
# resolve the script's own directory *after* binding instead of using it as a
# default value. This keeps the script runnable from any working directory.
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Split-Path -Parent $MyInvocation.MyCommand.Path) }
}
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = (Get-Location).Path }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker CLI not found on PATH."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Write-Host "Enumerating containers..." -ForegroundColor Cyan
$names = @(docker ps -a --format '{{.Names}}')

$records = @()
foreach ($n in $names) {
    $raw = docker inspect $n 2>$null | ConvertFrom-Json
    if (-not $raw) { continue }
    $c = $raw[0]
    $labels = $c.Config.Labels
    $imgRef = $c.Config.Image

    # Resolve the registry digest for this image ref. Empty when the image was
    # built locally and never pulled from a registry.
    $digest = ''
    try {
        $repoDigests = docker image inspect $imgRef --format '{{json .RepoDigests}}' 2>$null | ConvertFrom-Json
        if ($repoDigests -and @($repoDigests).Count -gt 0) {
            $digest = (@($repoDigests)[0] -split '@')[-1]
        }
    } catch { }

    # Two independent facts, deliberately kept separate:
    #
    #   refPinned    - does the *image reference itself* name immutable bits?
    #                  A ref is pinned only when it carries an @sha256: digest.
    #                  A floating ref means "docker compose pull" next month may
    #                  hand you different code than you are running now.
    #   digest       - the bits this container is *actually* running right now.
    #                  Always recorded, so even a floating ref is forensically
    #                  recoverable.
    #
    # A moving or implicit tag (:latest, :main, or no tag at all) is the
    # dangerous case, because it silently changes under you on every pull.
    $refPinned = $imgRef -match '@sha256:'
    $tagPart = if ($imgRef -match '@') { ($imgRef -split '@')[0] } else { $imgRef }
    $hasTag = $tagPart -match ':[^/:]+$'
    $movingTag = $tagPart -match ':(latest|main|master|stable|edge|dev|nightly)$'
    $floatingTag = (-not $refPinned) -and ((-not $hasTag) -or $movingTag)
    $floatingReason = if ($refPinned) { '' }
                      elseif (-not $hasTag) { 'no tag (implicit :latest)' }
                      elseif ($movingTag) { 'moving tag ' + ($tagPart -replace '^.*:', ':') }
                      else { '' }

    $ports = @()
    if ($c.NetworkSettings.Ports) {
        foreach ($p in $c.NetworkSettings.Ports.PSObject.Properties) {
            if ($p.Value) {
                $ports += ('{0} -> host {1}' -f $p.Name, $p.Value[0].HostPort)
            } else {
                $ports += ('{0} (internal only)' -f $p.Name)
            }
        }
    }

    $records += [PSCustomObject]@{
        container         = $n
        state             = $c.State.Status
        imageRef          = $imgRef
        imageId           = $c.Image
        digest            = $digest
        refPinned         = $refPinned
        floatingTag       = $floatingTag
        floatingReason    = $floatingReason
        composeProject    = $labels.'com.docker.compose.project'
        composeService    = $labels.'com.docker.compose.service'
        composeWorkingDir = $labels.'com.docker.compose.project.working_dir'
        composeConfigFile = $labels.'com.docker.compose.project.config_files'
        restartPolicy     = $c.HostConfig.RestartPolicy.Name
        networks          = @($c.NetworkSettings.Networks.PSObject.Properties.Name)
        ports             = $ports
        created           = $c.Created
    }
}

$records = $records | Sort-Object composeProject, container

# ---------------------------------------------------------------- JSON output
$jsonObj = [PSCustomObject]@{
    generatedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    dockerVersion   = (docker version --format '{{.Server.Version}}' 2>$null)
    containerCount  = $records.Count
    containers      = $records
}
Write-Utf8 -Path (Join-Path $OutDir 'runtime-inventory.json') -Content ($jsonObj | ConvertTo-Json -Depth 8)

# ------------------------------------------------------------ Markdown output
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Runtime Inventory (generated)')
[void]$sb.AppendLine()
[void]$sb.AppendLine('> Generated by `runtime/capture-runtime.ps1`. Do not hand-edit.')
[void]$sb.AppendLine()
[void]$sb.AppendLine(('Generated: `{0}`  ' -f $jsonObj.generatedAt))
[void]$sb.AppendLine(('Docker server: `{0}`  ' -f $jsonObj.dockerVersion))
[void]$sb.AppendLine(('Containers: **{0}**' -f $jsonObj.containerCount))
[void]$sb.AppendLine()

# Flag anything that is not reproducible from a compose file + pinned image.
$unmanaged = @($records | Where-Object { -not $_.composeProject })
$floating  = @($records | Where-Object { $_.floatingTag })

[void]$sb.AppendLine('## Reproducibility risks')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Two distinct problems are tracked separately:')
[void]$sb.AppendLine()
[void]$sb.AppendLine('- **Unmanaged** — started outside compose, so no compose file rebuilds it and no project owns its lifecycle.')
[void]$sb.AppendLine('- **Floating ref** — the image reference is not pinned by digest, so a future `pull` can silently change the running code.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('The `Digest` column is forensic: even when a ref floats, the exact bits currently')
[void]$sb.AppendLine('running are recorded, so the running state is always recoverable.')
[void]$sb.AppendLine()
if ($unmanaged.Count -eq 0) {
    [void]$sb.AppendLine('- No unmanaged containers detected.')
} else {
    [void]$sb.AppendLine(('### Unmanaged containers ({0})' -f $unmanaged.Count))
    [void]$sb.AppendLine()
    foreach ($u in $unmanaged) { [void]$sb.AppendLine(('  - `{0}` uses `{1}`' -f $u.container, $u.imageRef)) }
}
[void]$sb.AppendLine()
if ($floating.Count -eq 0) {
    [void]$sb.AppendLine('- No floating image refs detected.')
} else {
    [void]$sb.AppendLine(('### Floating image refs ({0})' -f $floating.Count))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Container | Compose project | Image ref | Why it floats |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($f in $floating) {
        $projName = if ($f.composeProject) { $f.composeProject } else { '(unmanaged)' }
        [void]$sb.AppendLine(('| `{0}` | {1} | `{2}` | {3} |' -f $f.container, $projName, $f.imageRef, $f.floatingReason))
    }
}
[void]$sb.AppendLine()

# Per-project tables.
$projects = $records | Group-Object { if ($_.composeProject) { $_.composeProject } else { '(unmanaged)' } } | Sort-Object Name
foreach ($proj in $projects) {
    [void]$sb.AppendLine(('## Project: `{0}`' -f $proj.Name))
    [void]$sb.AppendLine()
    $wd = ($proj.Group | Where-Object { $_.composeWorkingDir } | Select-Object -First 1).composeWorkingDir
    $cf = ($proj.Group | Where-Object { $_.composeConfigFile } | Select-Object -First 1).composeConfigFile
    if ($wd) { [void]$sb.AppendLine(('- Working dir: `{0}`' -f $wd)) }
    if ($cf) { [void]$sb.AppendLine(('- Compose file: `{0}`' -f $cf)) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Container | Service | State | Image | Digest of running bits | Ref pinned | Restart | Ports |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
    foreach ($r in ($proj.Group | Sort-Object container)) {
        $pin = if ($r.refPinned) { 'yes (digest)' } elseif ($r.floatingTag) { '**NO** (' + $r.floatingReason + ')' } else { 'yes (tag)' }
        $dig = if ($r.digest) { '`' + $r.digest.Substring(0, [Math]::Min(19, $r.digest.Length)) + '...`' } else { '-' }
        $prt = if ($r.ports.Count) { ($r.ports -join '<br>') } else { '-' }
        [void]$sb.AppendLine(('| `{0}` | {1} | {2} | `{3}` | {4} | {5} | {6} | {7} |' -f `
            $r.container, $r.composeService, $r.state, $r.imageRef, $dig, $pin, $r.restartPolicy, $prt))
    }
    [void]$sb.AppendLine()
}

Write-Utf8 -Path (Join-Path $OutDir 'RUNTIME-INVENTORY.md') -Content $sb.ToString()

Write-Host ''
Write-Host ('Wrote {0} containers.' -f $records.Count) -ForegroundColor Green
Write-Host ('  ' + (Join-Path $OutDir 'runtime-inventory.json'))
Write-Host ('  ' + (Join-Path $OutDir 'RUNTIME-INVENTORY.md'))
if ($unmanaged.Count -gt 0) { Write-Host ('  ! {0} unmanaged container(s)' -f $unmanaged.Count) -ForegroundColor Yellow }
if ($floating.Count -gt 0)  { Write-Host ('  ! {0} floating image ref(s)' -f $floating.Count) -ForegroundColor Yellow }
