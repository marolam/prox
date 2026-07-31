Param(
  [string[]]$DeviceIds = @("R5CT51EDX0H", "ZY22L74Z8N"),
  [string]$Repo = "marolam/prox-us",
  [string]$PublicApkUrl = "",
  [string]$PackageName = "com.prox.app",
  [string]$LaunchActivity = "com.prox.app/.MainActivity",
  [ValidateSet("tester", "staging", "prod")]
  [string]$ReleaseChannel = "prod",
  [switch]$SkipBuildInstall,
  [switch]$SkipPublish,
  [switch]$EnableBusinessMode,
  [switch]$CleanInstall,
  [switch]$AllowPartialDeviceDeploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
} else {
  (Get-Location).Path
}

Set-Location $repoRoot

$buildScript = Join-Path $repoRoot "tools/scripts/build_release_apk.ps1"
$publishScript = Join-Path $repoRoot "tools/scripts/publish_github_release.ps1"

if (-not (Test-Path $buildScript)) {
  throw "Missing build script: $buildScript"
}
if (-not (Test-Path $publishScript)) {
  throw "Missing publish script: $publishScript"
}

Write-Host "== Prox One-Command Release Pipeline ==" -ForegroundColor Cyan
Write-Host "Repo root: $repoRoot"
Write-Host "Repo slug: $Repo"
Write-Host "Devices:   $($DeviceIds -join ', ')"
Write-Host "Channel:   $ReleaseChannel"
Write-Host "Business Mode build enabled: $($EnableBusinessMode.IsPresent)"

$latestUrl = "https://github.com/$Repo/releases/latest/download/app-release.apk"
if ([string]::IsNullOrWhiteSpace($PublicApkUrl)) {
  $PublicApkUrl = $latestUrl
}

if (-not $SkipBuildInstall) {
  Write-Host "`nStep 1/2: Build + Install on connected devices" -ForegroundColor Cyan
  $invokeParams = @{
    DeviceIds = $DeviceIds
    PackageName = $PackageName
    LaunchActivity = $LaunchActivity
    ReleaseChannel = $ReleaseChannel
    PublicApkUrl = $PublicApkUrl
  }
  if ($CleanInstall) {
    $invokeParams["CleanInstall"] = $true
  }
  if ($EnableBusinessMode) {
    $invokeParams["EnableBusinessMode"] = $true
  }
  if ($AllowPartialDeviceDeploy) {
    $invokeParams["AllowPartialDeviceDeploy"] = $true
  } else {
    # For ship readiness, fail if no ready devices or any ready-device install/launch issue occurs.
    $invokeParams["FailIfNoReadyDevices"] = $true
    $invokeParams["FailOnAnyDeviceIssue"] = $true
  }

  & $buildScript @invokeParams
  if ($LASTEXITCODE -ne 0) {
    throw "Build/install step failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host "`nStep 1/2: Skipped build/install by request." -ForegroundColor Yellow
}

if (-not $SkipPublish) {
  Write-Host "`nStep 2/2: Publish GitHub release assets" -ForegroundColor Cyan
  & powershell -ExecutionPolicy Bypass -File $publishScript -Repo $Repo
  if ($LASTEXITCODE -ne 0) {
    throw "Publish step failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host "`nStep 2/2: Skipped publish by request." -ForegroundColor Yellow
}

Write-Host "`nPipeline complete." -ForegroundColor Green
Write-Host "Latest APK URL: $latestUrl" -ForegroundColor Green
if ($PublicApkUrl -ne $latestUrl) {
  Write-Host "Public APK URL: $PublicApkUrl" -ForegroundColor Green
}

exit 0
