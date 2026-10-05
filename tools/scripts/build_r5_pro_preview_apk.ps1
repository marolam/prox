Param(
  [string]$DeviceId = "R5CT51EDX0H",
  [string]$PreviewLogin = "marty.marola@hotmail.com",
  [string]$TesterGuideUrl = "https://prox-us.com/tester-guide",
  [string]$TesterSupportUrl = "https://prox-us.com/tester-support",
  [switch]$CleanInstall,
  [switch]$FailIfNoReadyDevices
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
    [string]$TargetDeviceId,
    [string[]]$AdbArgs,
    [switch]$AllowFailure
  )
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & adb -s $TargetDeviceId @AdbArgs 2>&1
  $ErrorActionPreference = $previousPreference
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "adb command failed for device '$TargetDeviceId': adb -s $TargetDeviceId $($AdbArgs -join ' ')`n$output"
  }
  return [PSCustomObject]@{
    ExitCode = $exitCode
    Output = ($output | Out-String).Trim()
  }
}

function Test-DeviceReady {
  Param([string]$TargetDeviceId)
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $state = (& adb -s $TargetDeviceId get-state 2>$null | Out-String).Trim()
  $ErrorActionPreference = $previousPreference
  return $LASTEXITCODE -eq 0 -and $state -eq "device"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop
Set-Location $repoRoot

Assert-Tool "adb"
Assert-Tool "flutter"
Assert-Tool "powershell"

Write-Host "== Prox R5 Pro preview build ==" -ForegroundColor Cyan
Write-Host "Repo:          $($repoRoot.Path)"
Write-Host "Device:        $DeviceId"
Write-Host "Preview login: $PreviewLogin"

& powershell -ExecutionPolicy Bypass -File .\tools\scripts\safe_update_gate.ps1 -CreateSnapshot -CheckLocalCanonicalApk
if ($LASTEXITCODE -ne 0) {
  throw "Safe update gate failed. Refusing to build Pro preview APK."
}

$canonicalApk = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-release.apk"
$safeRollbackApk = Join-Path $repoRoot "artifacts/rollback/v1.0/app-release.apk"
$previewDir = Join-Path $repoRoot "artifacts/pro_preview"
$previewApk = Join-Path $previewDir "r5-pro-preview-app-release.apk"

if (-not (Test-Path $safeRollbackApk)) {
  throw "Safe rollback APK is missing: $safeRollbackApk"
}

if (-not (Test-Path $previewDir)) {
  New-Item -ItemType Directory -Path $previewDir | Out-Null
}

$buildArgs = @(
  "build",
  "apk",
  "--release",
  "--dart-define=PROX_TESTER=true",
  "--dart-define=PROX_TESTER_BUILD=true",
  "--dart-define=BUILD_FLAVOR=r5_pro_preview",
  "--dart-define=PROX_PRO_MODE_PREVIEW_ENABLED=true",
  "--dart-define=PROX_PRO_MODE_PREVIEW_LOGINS=$PreviewLogin",
  "--dart-define=PROX_TESTER_GUIDE_URL=$TesterGuideUrl",
  "--dart-define=PROX_TESTER_SUPPORT_URL=$TesterSupportUrl"
)

try {
  Write-Host "`nBuilding R5 Pro preview APK..." -ForegroundColor Cyan
  & flutter @buildArgs
  if ($LASTEXITCODE -ne 0) {
    throw "R5 Pro preview build failed with exit code $LASTEXITCODE."
  }

  if (-not (Test-Path $canonicalApk)) {
    throw "Flutter build did not produce the expected APK: $canonicalApk"
  }

  Copy-Item -Path $canonicalApk -Destination $previewApk -Force
  Write-Host "Preview APK copied to: $previewApk" -ForegroundColor Green

  if (-not (Test-DeviceReady -TargetDeviceId $DeviceId)) {
    if ($FailIfNoReadyDevices) {
      throw "R5 target device is not ready: $DeviceId"
    }
    Write-Warning "R5 target device is not ready: $DeviceId"
    exit 0
  }

  if ($CleanInstall) {
    Write-Host "Uninstalling com.prox.app from R5 for a clean preview install..."
    $uninstall = Invoke-Adb -TargetDeviceId $DeviceId -AdbArgs @("uninstall", "com.prox.app") -AllowFailure
    if ($uninstall.ExitCode -ne 0 -and $uninstall.Output -notmatch "Unknown package") {
      Write-Warning "Uninstall returned non-zero: $($uninstall.Output)"
    }
  }

  Write-Host "`nInstalling preview APK on R5..." -ForegroundColor Cyan
  $install = Invoke-Adb -TargetDeviceId $DeviceId -AdbArgs @("install", "-r", $previewApk) -AllowFailure
  if ($install.ExitCode -ne 0) {
    Write-Warning "Standard install failed; retrying with downgrade flag (-d)."
    $install = Invoke-Adb -TargetDeviceId $DeviceId -AdbArgs @("install", "-r", "-d", $previewApk) -AllowFailure
  }
  if ($install.ExitCode -ne 0) {
    throw "Install failed on R5: $($install.Output)"
  }

  Write-Host "Launching preview APK on R5..."
  Invoke-Adb -TargetDeviceId $DeviceId -AdbArgs @("shell", "am", "start", "-n", "com.prox.app/.MainActivity") | Out-Null
  Write-Host "R5 Pro preview installed and launched." -ForegroundColor Green
} finally {
  if (Test-Path $safeRollbackApk) {
    Copy-Item -Path $safeRollbackApk -Destination $canonicalApk -Force
    Write-Host "Safe rollback APK restored as the canonical local app-release.apk." -ForegroundColor Cyan
  }
}