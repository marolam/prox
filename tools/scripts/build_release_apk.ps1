Param(
  [string[]]$DeviceIds = @("R5CT51EDX0H", "ZY22L74Z8N"),
  [string]$PackageName = "com.prox.app",
  [string]$LaunchActivity = "com.prox.app/.MainActivity",
  [string]$TesterGuideUrl = "https://prox-us.com/tester-guide",
  [string]$TesterSupportUrl = "https://prox-us.com/tester-support",
  [string]$ExternalCheckoutSessionUrl = "",
  [switch]$SkipBuild,
  [switch]$CleanInstall,
  [switch]$FailIfNoReadyDevices,
  [switch]$FailOnAnyDeviceIssue
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH."
  }
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
  $ErrorActionPreference = $prev
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "adb command failed for device '$DeviceId': adb -s $DeviceId $($AdbArgs -join ' ')`n$output"
  }
  return [PSCustomObject]@{
    ExitCode = $exitCode
    Output = ($output | Out-String).Trim()
  }
}

function Test-DeviceReady {
  Param([string]$DeviceId)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $state = (& adb -s $DeviceId get-state 2>$null | Out-String).Trim()
  $ErrorActionPreference = $prev
  return $LASTEXITCODE -eq 0 -and $state -eq "device"
}

Assert-Tool "adb"
Assert-Tool "powershell"

function Resolve-ApkPath {
  Param([string]$RepoPath)

  $apkCandidates = @(
    (Join-Path $RepoPath "build/app/outputs/flutter-apk/app-release.apk"),
    (Join-Path $RepoPath "android/app/build/outputs/flutter-apk/app-release.apk")
  )

  $existing = @($apkCandidates | Where-Object { Test-Path $_ })
  if ($existing.Count -eq 0) {
    throw "Release APK not found. Checked: $($apkCandidates -join ', ')"
  }

  return ($existing |
    ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1).FullName
}

$repoPathInput = (Get-Location).Path
$resolvedRepoPath = Resolve-Path $repoPathInput -ErrorAction Stop
Set-Location $resolvedRepoPath

$envLoader = Join-Path $PSScriptRoot "import_env_file.ps1"
if (Test-Path $envLoader) {
  . $envLoader -EnvFilePath (Join-Path $resolvedRepoPath "tools/.env/payment.local.env")
}

Write-Host "== Prox release deploy to devices ==" -ForegroundColor Cyan
Write-Host "Repo:    $resolvedRepoPath"
Write-Host "Devices: $($DeviceIds -join ', ')"
Write-Host "Package: $PackageName"

if ([string]::IsNullOrWhiteSpace($ExternalCheckoutSessionUrl)) {
  $ExternalCheckoutSessionUrl = $env:PROX_EXTERNAL_CHECKOUT_SESSION_URL
}

if (-not $SkipBuild) {
  $preBuildApkPath = $null
  $preBuildApkTime = $null
  try {
    $preBuildApkPath = Resolve-ApkPath -RepoPath $resolvedRepoPath
    $preBuildApkTime = (Get-Item $preBuildApkPath).LastWriteTime
  } catch {
    # No prior APK is acceptable before the first successful build.
  }

  Write-Host "`nBuilding latest release APK..." -ForegroundColor Cyan
  $buildArgs = @(
    "build",
    "apk",
    "--release",
    "--dart-define=PROX_TESTER_GUIDE_URL=$TesterGuideUrl",
    "--dart-define=PROX_TESTER_SUPPORT_URL=$TesterSupportUrl"
  )
  if (-not [string]::IsNullOrWhiteSpace($ExternalCheckoutSessionUrl)) {
    $buildArgs += "--dart-define=PROX_EXTERNAL_CHECKOUT_SESSION_URL=$ExternalCheckoutSessionUrl"
    Write-Host "Using PROX_EXTERNAL_CHECKOUT_SESSION_URL dart-define." -ForegroundColor Cyan
  }
  else {
    Write-Warning "PROX_EXTERNAL_CHECKOUT_SESSION_URL not provided; app may fall back to local checkout intent scaffold."
  }
  & flutter @buildArgs
  $buildExitCode = $LASTEXITCODE

  $postBuildApkPath = Resolve-ApkPath -RepoPath $resolvedRepoPath
  $postBuildApkTime = (Get-Item $postBuildApkPath).LastWriteTime
  $isFreshApk = ($null -eq $preBuildApkTime) -or ($postBuildApkTime -gt $preBuildApkTime)

  if ($buildExitCode -ne 0) {
    throw "Release build failed (flutter exit code: $buildExitCode). Refusing to continue even if an APK timestamp changed."
  }

  if (-not $isFreshApk) {
    throw "Release build reported success but did not produce a fresh APK."
  }
}

$apkPath = Resolve-ApkPath -RepoPath $resolvedRepoPath
$apkItem = Get-Item $apkPath
Write-Host "APK:     $apkPath"
Write-Host "APK time:$($apkItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"

$results = New-Object System.Collections.Generic.List[object]
$readyDeviceCount = 0

foreach ($deviceId in $DeviceIds) {
  Write-Host "`n== Device $deviceId ==" -ForegroundColor Cyan
  if (-not (Test-DeviceReady -DeviceId $deviceId)) {
    Write-Warning "Device not ready or not connected: $deviceId"
    $results.Add([PSCustomObject]@{ Device = $deviceId; Status = "not-ready" })
    continue
  }
  $readyDeviceCount++
  try {
    if ($CleanInstall) {
      Write-Host "Uninstalling $PackageName (clean install requested; this clears app data)..."
      $uninstall = Invoke-Adb -DeviceId $deviceId -AdbArgs @("uninstall", $PackageName) -AllowFailure
      if ($uninstall.ExitCode -ne 0 -and $uninstall.Output -notmatch "Unknown package") {
        Write-Warning "Uninstall returned non-zero: $($uninstall.Output)"
      }
    }

    Write-Host "Installing release APK..."
    $install = Invoke-Adb -DeviceId $deviceId -AdbArgs @("install", "-r", "$apkPath") -AllowFailure
    if ($install.ExitCode -ne 0) {
      Write-Warning "Standard install failed; retrying with downgrade flag (-d)."
      $install = Invoke-Adb -DeviceId $deviceId -AdbArgs @("install", "-r", "-d", "$apkPath") -AllowFailure
    }
    if ($install.ExitCode -ne 0) {
      Write-Warning "Install failed on ${deviceId}: $($install.Output)"
      $results.Add([PSCustomObject]@{ Device = $deviceId; Status = "install-failed" })
      continue
    }
    Write-Host "Launching app..."
    $launch = Invoke-Adb -DeviceId $deviceId -AdbArgs @("shell", "am", "start", "-n", $LaunchActivity) -AllowFailure
    if ($launch.ExitCode -ne 0) {
      Write-Warning "Launch failed on ${deviceId}: $($launch.Output)"
      $results.Add([PSCustomObject]@{ Device = $deviceId; Status = "launch-failed" })
      continue
    }
    Write-Host "Success on $deviceId" -ForegroundColor Green
    $results.Add([PSCustomObject]@{ Device = $deviceId; Status = "ok" })
  } catch {
    Write-Warning "Unexpected failure on ${deviceId}: $($_.Exception.Message)"
    $results.Add([PSCustomObject]@{ Device = $deviceId; Status = "error" })
  }
}

Write-Host "`n== Summary ==" -ForegroundColor Cyan
$results | ForEach-Object {
  Write-Host "  $($_.Device): $($_.Status)"
}

$failed = @($results | Where-Object { $_.Status -notin @("ok", "not-ready") })
$notReady = @($results | Where-Object { $_.Status -eq "not-ready" })

if ($readyDeviceCount -eq 0 -and $FailIfNoReadyDevices) {
  Write-Error "No target devices were ready. Failing because -FailIfNoReadyDevices is set."
  exit 1
}

if ($failed.Count -gt 0 -and $FailOnAnyDeviceIssue) {
  Write-Error "Deployment had $($failed.Count) failing ready device(s). Failing because -FailOnAnyDeviceIssue is set."
  exit 1
}

if ($notReady.Count -gt 0 -or $failed.Count -gt 0) {
  Write-Warning "Deployment completed with warnings (not-ready: $($notReady.Count), failed-ready-devices: $($failed.Count))."
  Write-Host "APK build succeeded and artifact is ready for manual install/testing." -ForegroundColor Yellow
  exit 0
}

Write-Host "All devices updated and app launched." -ForegroundColor Green
exit 0
