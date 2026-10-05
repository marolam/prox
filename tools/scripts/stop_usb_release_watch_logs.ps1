Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
$logDir = Join-Path $repoRoot "logs/logcat"

if (-not (Test-Path $logDir)) {
  Write-Host "No log directory found at $logDir"
  exit 0
}

$pidFiles = @(Get-ChildItem -Path $logDir -File -Filter "usb_watch_pids_*.json" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending)

if (-not $pidFiles -or $pidFiles.Count -eq 0) {
  Write-Host "No usb watch PID files found in $logDir"
  exit 0
}

foreach ($pidFile in $pidFiles) {
  Write-Host "Stopping logcat entries from $($pidFile.FullName)"
  $entries = Get-Content $pidFile.FullName | ConvertFrom-Json
  foreach ($entry in $entries) {
    try {
      Stop-Process -Id $entry.Pid -Force -ErrorAction SilentlyContinue
      Write-Host "Stopped $($entry.Device) pid $($entry.Pid)"
    }
    catch {
      Write-Warning "Failed to stop pid $($entry.Pid) for $($entry.Device)"
    }
  }
  Remove-Item $pidFile.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host "USB watch logcat processes stopped."
