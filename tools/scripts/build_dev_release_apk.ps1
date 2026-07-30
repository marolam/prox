Param(
  [string[]]$DeviceIds = @("R5CT51EDX0H", "ZY22L74Z8N"),
  [string]$PackageName = "com.prox.app",
  [string]$LaunchActivity = "com.prox.app/.MainActivity",
  [string]$TesterGuideUrl = "https://prox-us.com/tester-guide",
  [string]$TesterSupportUrl = "https://prox-us.com/tester-support",
  [string]$ExternalCheckoutSessionUrl = "",
  [switch]$EnableBizMonthlyDevPrice,
  [switch]$CleanInstall,
  [switch]$FailIfNoReadyDevices,
  [switch]$FailOnAnyDeviceIssue
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop
Set-Location $repoRoot

$envLoader = Join-Path $PSScriptRoot "import_env_file.ps1"
if (Test-Path $envLoader) {
  . $envLoader -EnvFilePath (Join-Path $repoRoot "tools/.env/payment.local.env")
}

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH."
  }
}

Assert-Tool "flutter"
Assert-Tool "powershell"

Write-Host "== Prox dev release deploy ==" -ForegroundColor Cyan
Write-Host "Repo:    $($repoRoot.Path)"
Write-Host "Devices: $($DeviceIds -join ', ')"
Write-Host "Package: $PackageName"
if ($EnableBizMonthlyDevPrice) {
  Write-Host "Dev monthly price toggle requested: PROX_BIZ_MONTHLY_DEV_PRICE_ENABLED=true" -ForegroundColor Yellow
  Write-Host "Reminder: this is a backend env var and must be set in your Functions runtime environment." -ForegroundColor Yellow
}

if ([string]::IsNullOrWhiteSpace($ExternalCheckoutSessionUrl)) {
  $ExternalCheckoutSessionUrl = $env:PROX_EXTERNAL_CHECKOUT_SESSION_URL
}

Write-Host "`nBuilding dev/tester release APK..." -ForegroundColor Cyan
$buildArgs = @(
  "build",
  "apk",
  "--release",
  "--dart-define=PROX_TESTER=true",
  "--dart-define=PROX_TESTER_BUILD=true",
  "--dart-define=BUILD_FLAVOR=dev_release",
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
if ($LASTEXITCODE -ne 0) {
  throw "Dev release build failed (flutter exit code: $LASTEXITCODE)."
}

$installScript = Join-Path $repoRoot "tools/scripts/build_release_apk.ps1"
if (-not (Test-Path $installScript)) {
  throw "Missing install/launch script: $installScript"
}

Write-Host "`nInstalling + launching APK on target devices..." -ForegroundColor Cyan

$invokeArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $installScript,
  "-SkipBuild",
  "-PackageName", $PackageName,
  "-LaunchActivity", $LaunchActivity,
  "-TesterGuideUrl", $TesterGuideUrl,
  "-TesterSupportUrl", $TesterSupportUrl
)

if ($DeviceIds.Count -gt 0) {
  $invokeArgs += "-DeviceIds"
  $invokeArgs += $DeviceIds
}
if ($CleanInstall) {
  $invokeArgs += "-CleanInstall"
}
if ($FailIfNoReadyDevices) {
  $invokeArgs += "-FailIfNoReadyDevices"
}
if ($FailOnAnyDeviceIssue) {
  $invokeArgs += "-FailOnAnyDeviceIssue"
}

& powershell @invokeArgs
exit $LASTEXITCODE
