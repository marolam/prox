Param(
  [string[]]$DeviceIds = @("R5CT51EDX0H", "ZY22L74Z8N"),
  [string]$PackageName = "com.prox.app",
  [string]$LaunchActivity = "com.prox.app/.MainActivity",
  [string]$LaunchRoute = "/nearby",
  [switch]$FreshSessionOnLaunch,
  [switch]$ClearAppDataOnLaunch,
  [ValidateSet("release", "debug")]
  [string]$ApkMode = "release",
  [int]$PollSeconds = 8,
  [switch]$DeployLatestOnStart
)

if (-not $PSBoundParameters.ContainsKey("FreshSessionOnLaunch")) {
  $FreshSessionOnLaunch = $true
}

if (-not $PSBoundParameters.ContainsKey("ClearAppDataOnLaunch")) {
  $ClearAppDataOnLaunch = $true
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH."
  }
}

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
}

function Get-LatestApk {
  Param(
    [string]$RepoRoot,
    [string]$Mode
  )

  $suffix = if ($Mode -eq "debug") { "debug" } else { "release" }
  $apkCandidates = @(
    (Join-Path $RepoRoot "build/app/outputs/flutter-apk/app-$suffix.apk"),
    (Join-Path $RepoRoot "android/app/build/outputs/flutter-apk/app-$suffix.apk")
  )

  $existing = @($apkCandidates | Where-Object { Test-Path $_ })
  if ($existing.Count -eq 0) {
    return $null
  }

  return ($existing |
    ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1)
}

function Test-DeviceReady {
  Param([string]$DeviceId)

  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $state = (& adb -s $DeviceId get-state 2>$null | Out-String).Trim()
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $prev

  return $exitCode -eq 0 -and $state -eq "device"
}

function Invoke-Adb {
  Param(
    [string]$DeviceId,
    [string[]]$AdbArgs,
    [switch]$AllowFailure
  )

  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & adb -s $DeviceId @AdbArgs 2>&1
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $prev

  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "adb failed for '$DeviceId': adb -s $DeviceId $($AdbArgs -join ' ')`n$output"
  }

  return [PSCustomObject]@{
    ExitCode = $exitCode
    Output = ($output | Out-String).Trim()
  }
}

function Start-DeviceLogcat {
  Param(
    [string]$DeviceId,
    [string]$LogDir,
    [string]$SessionId
  )

  if (-not (Test-DeviceReady -DeviceId $DeviceId)) {
    Write-Warning "Skipping logcat start for not-ready device: $DeviceId"
    return $null
  }

  Invoke-Adb -DeviceId $DeviceId -AdbArgs @("logcat", "-c") -AllowFailure | Out-Null

  $logFile = Join-Path $LogDir "usb_watch_${DeviceId}_${SessionId}.logcat.txt"
  $errFile = Join-Path $LogDir "usb_watch_${DeviceId}_${SessionId}.err.txt"

  $proc = Start-Process -FilePath "adb" -ArgumentList "-s", $DeviceId, "logcat", "-v", "time" `
    -RedirectStandardOutput $logFile -RedirectStandardError $errFile -PassThru -NoNewWindow

  Write-Host "Logcat started for $DeviceId -> $logFile"
  return [PSCustomObject]@{
    Device = $DeviceId
    Pid = $proc.Id
    LogFile = $logFile
    ErrFile = $errFile
  }
}

function Deploy-ToReadyDevices {
  Param(
    [string[]]$TargetDeviceIds,
    [string]$ApkPath,
    [string]$Package,
    [string]$Activity,
    [string]$Route,
    [bool]$FreshSession,
    [bool]$ClearAppData
  )

  Write-Host "`nDeploying $ApkPath" -ForegroundColor Cyan
  foreach ($deviceId in $TargetDeviceIds) {
    if (-not (Test-DeviceReady -DeviceId $deviceId)) {
      Write-Warning "Device not ready: $deviceId"
      continue
    }

    Write-Host "[$deviceId] Installing..."
    $install = Invoke-Adb -DeviceId $deviceId -AdbArgs @("install", "-r", $ApkPath) -AllowFailure
    if ($install.ExitCode -ne 0) {
      Write-Warning "[$deviceId] Install failed, retrying with -d"
      $install = Invoke-Adb -DeviceId $deviceId -AdbArgs @("install", "-r", "-d", $ApkPath) -AllowFailure
    }
    if ($install.ExitCode -ne 0) {
      Write-Warning "[$deviceId] Install failed: $($install.Output)"
      continue
    }

    if ($ClearAppData) {
      Write-Host "[$deviceId] Clearing app data for strict fresh instance..."
      $clear = Invoke-Adb -DeviceId $deviceId -AdbArgs @("shell", "pm", "clear", $Package) -AllowFailure
      if ($clear.ExitCode -ne 0) {
        Write-Warning "[$deviceId] App data clear failed (continuing): $($clear.Output)"
      }
    }

    Write-Host "[$deviceId] Launching..."
    $launchArgs = @("shell", "am", "start")
    if ($FreshSession) {
      # -S force-stops target app before launch for a fresh process/session.
      $launchArgs += "-S"
    }
    $launchArgs += @("-W", "-n", $Activity)
    if ($Route.Trim().Length -gt 0) {
      $launchArgs += @("--es", "route", $Route)
    }

    $launch = Invoke-Adb -DeviceId $deviceId -AdbArgs $launchArgs -AllowFailure
    if ($launch.ExitCode -ne 0) {
      Write-Warning "[$deviceId] Launch failed, retrying without route extra."
      $fallbackLaunch = Invoke-Adb -DeviceId $deviceId -AdbArgs @(
        "shell", "am", "start", "-W", "-n", $Activity
      ) -AllowFailure
      if ($fallbackLaunch.ExitCode -ne 0) {
        Write-Warning "[$deviceId] Launch failed: $($fallbackLaunch.Output)"
        continue
      }
    }

    Write-Host "[$deviceId] OK" -ForegroundColor Green
  }
}

Assert-Tool "adb"

$repoRoot = Resolve-RepoRoot
$logDir = Join-Path $repoRoot "logs/logcat"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$sessionId = Get-Date -Format "yyyyMMdd_HHmmss"
$pidFile = Join-Path $logDir "usb_watch_pids_$sessionId.json"

Write-Host "== USB release watcher ==" -ForegroundColor Cyan
Write-Host "Repo:         $repoRoot"
Write-Host "Devices:      $($DeviceIds -join ', ')"
Write-Host "APK mode:     $ApkMode"
Write-Host "Launch route: $LaunchRoute"
Write-Host "Fresh launch: $FreshSessionOnLaunch"
Write-Host "Clear data:   $ClearAppDataOnLaunch"
Write-Host "Log directory:$logDir"
Write-Host "Poll seconds: $PollSeconds"

$logcatRecords = New-Object System.Collections.Generic.List[object]
foreach ($deviceId in $DeviceIds) {
  $record = Start-DeviceLogcat -DeviceId $deviceId -LogDir $logDir -SessionId $sessionId
  if ($null -ne $record) {
    $logcatRecords.Add($record)
  }
}

if ($logcatRecords.Count -gt 0) {
  $logcatRecords | ConvertTo-Json | Set-Content -Path $pidFile -Encoding UTF8
  Write-Host "Watcher PID file: $pidFile"
}
else {
  Write-Warning "No ready devices for logcat capture at startup."
}

$latestApk = Get-LatestApk -RepoRoot $repoRoot -Mode $ApkMode
$knownTicks = 0L
if ($null -ne $latestApk) {
  $knownTicks = $latestApk.LastWriteTimeUtc.Ticks
  Write-Host "Initial APK: $($latestApk.FullName) ($($latestApk.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))"

  if ($DeployLatestOnStart) {
    Deploy-ToReadyDevices -TargetDeviceIds $DeviceIds -ApkPath $latestApk.FullName -Package $PackageName -Activity $LaunchActivity -Route $LaunchRoute -FreshSession $FreshSessionOnLaunch -ClearAppData $ClearAppDataOnLaunch
  }
}
else {
  Write-Warning "No release APK found yet. Waiting for first build output..."
}

Write-Host "Watching for fresh release APK updates. Press Ctrl+C to stop." -ForegroundColor Cyan

while ($true) {
  Start-Sleep -Seconds $PollSeconds

  $candidate = Get-LatestApk -RepoRoot $repoRoot -Mode $ApkMode
  if ($null -eq $candidate) {
    continue
  }

  $candidateTicks = $candidate.LastWriteTimeUtc.Ticks
  if ($candidateTicks -le $knownTicks) {
    continue
  }

  $knownTicks = $candidateTicks
  Write-Host "`nDetected new APK timestamp: $($candidate.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
  Deploy-ToReadyDevices -TargetDeviceIds $DeviceIds -ApkPath $candidate.FullName -Package $PackageName -Activity $LaunchActivity -Route $LaunchRoute -FreshSession $FreshSessionOnLaunch -ClearAppData $ClearAppDataOnLaunch
}
