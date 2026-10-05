Param(
  [int]$PollSeconds = 4,
  [int]$QuietWindowSeconds = 2,
  [string[]]$WatchRoots = @("lib", "assets", "android", "pubspec.yaml")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
}

function Get-WatchTargets {
  Param(
    [string]$RepoRoot,
    [string[]]$Roots
  )

  $targets = New-Object System.Collections.Generic.List[object]
  foreach ($root in $Roots) {
    $path = Join-Path $RepoRoot $root
    if (Test-Path $path) {
      $targets.Add((Get-Item $path))
    }
  }
  return $targets
}

function Get-LatestSourceTick {
  Param([System.Collections.Generic.List[object]]$Targets)

  $latest = 0L
  foreach ($target in $Targets) {
    if ($target.PSIsContainer) {
      $files = Get-ChildItem -Path $target.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".dart", ".yaml", ".yml", ".gradle", ".kts", ".xml", ".json") }
      foreach ($f in $files) {
        if ($f.LastWriteTimeUtc.Ticks -gt $latest) {
          $latest = $f.LastWriteTimeUtc.Ticks
        }
      }
    }
    else {
      if ($target.LastWriteTimeUtc.Ticks -gt $latest) {
        $latest = $target.LastWriteTimeUtc.Ticks
      }
    }
  }
  return $latest
}

function Invoke-DebugBuild {
  Param([string]$RepoRoot)

  Push-Location $RepoRoot
  try {
    Write-Host "[watch_debug_build] Running flutter build apk --debug ..." -ForegroundColor Cyan
    & flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build apk --debug failed with exit code $LASTEXITCODE"
    }
    Write-Host "[watch_debug_build] Build complete." -ForegroundColor Green
  }
  finally {
    Pop-Location
  }
}

$repoRoot = Resolve-RepoRoot
$targets = Get-WatchTargets -RepoRoot $repoRoot -Roots $WatchRoots

if ($targets.Count -eq 0) {
  throw "No watch targets found."
}

Write-Host "== Debug APK auto-builder ==" -ForegroundColor Cyan
Write-Host "Repo:        $repoRoot"
Write-Host "Targets:     $($WatchRoots -join ', ')"
Write-Host "Poll seconds:$PollSeconds"

$lastSeen = Get-LatestSourceTick -Targets $targets
$lastBuildAt = 0L

# Build once at startup so watcher/deployer has a fresh baseline.
Invoke-DebugBuild -RepoRoot $repoRoot
$lastBuildAt = [DateTime]::UtcNow.Ticks

while ($true) {
  Start-Sleep -Seconds $PollSeconds

  $latest = Get-LatestSourceTick -Targets $targets
  if ($latest -le $lastSeen) {
    continue
  }

  $lastSeen = $latest
  Write-Host "[watch_debug_build] Change detected. Waiting for quiet window..." -ForegroundColor Yellow
  Start-Sleep -Seconds $QuietWindowSeconds

  $confirmLatest = Get-LatestSourceTick -Targets $targets
  if ($confirmLatest -gt $lastSeen) {
    $lastSeen = $confirmLatest
    Write-Host "[watch_debug_build] Additional changes detected, delaying build." -ForegroundColor Yellow
    continue
  }

  if ([DateTime]::UtcNow.Ticks - $lastBuildAt -lt [TimeSpan]::FromSeconds(2).Ticks) {
    continue
  }

  try {
    Invoke-DebugBuild -RepoRoot $repoRoot
    $lastBuildAt = [DateTime]::UtcNow.Ticks
  }
  catch {
    Write-Warning "[watch_debug_build] Build failed: $($_.Exception.Message)"
  }
}
