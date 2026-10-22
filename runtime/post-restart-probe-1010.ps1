$checks = @(
  @{n='nginx (frontend entry)'; u='http://localhost:8089/'},
  @{n='pacgate-api version'; u='http://localhost:8089/pacgate/version'},
  @{n='pacgate-mcp'; u='http://localhost:8000/mcp'},
  @{n='openviking'; u='http://localhost:1933/'},
  @{n='deer-flow gateway'; u='http://localhost:8001/health'},
  @{n='ocr-service'; u='http://localhost:8100/health'},
  @{n='frontend SSR'; u='http://localhost:8090/'},
  @{n='qm portal'; u='http://localhost:8091/'}
)
foreach ($c in $checks) {
  try {
    $r = Invoke-WebRequest -Uri $c.u -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Output ("{0}: HTTP {1}" -f $c.n, $r.StatusCode)
  } catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $msg = $_.Exception.Message
    if ($msg.Length -gt 70) { $msg = $msg.Substring(0, 70) }
    Write-Output ("{0}: HTTP {1} ({2})" -f $c.n, $code, $msg)
  }
}