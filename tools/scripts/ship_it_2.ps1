Param(
  [string[]]$DeviceIds = @(),
  [string]$Repo = "marolam/prox-us",
  [string]$PublicRepo = "marolam/prox",
  [string]$PublicApkUrl = "",
  [string]$FirebaseProjectId = "prox-42bef",
  [string]$ReferralDownloadUrl = "https://us-central1-prox-42bef.cloudfunctions.net/referralApkDownload",
  [string]$ReferralCode = "",
  [ValidateSet("tester", "staging", "prod")]
  [string]$ReleaseChannel = "tester",
  [switch]$SkipPreflightChecks,
  [switch]$PreflightQuickTestsOnly,
  [switch]$SkipPreflightAnalyze,
  [switch]$SkipPreflightTests,
  [switch]$SkipPreflightSafetyGate,
  [switch]$SkipPreflightSnapshot,
  [switch]$SkipPreflightRollbackCanonicalCheck,
  [switch]$SkipBuildInstall,
  [switch]$SkipPublish,
  [switch]$SkipPublicMirror,
  [switch]$SkipDownloadTargetSync,
  [switch]$SkipRemoteConfigSync,
  [switch]$CleanInstall,
  [switch]$RequireAllDevices,
  [switch]$EnableBusinessMode,
  [switch]$SkipVersionBump,
  [switch]$MarkImportantUpdate,
  [string]$ImportantMinVersion = "",
  [ValidateRange(5, 240)]
  [int]$UpdatePollMinutes = 20
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

function Get-ConnectedAndroidDevices {
  $rows = @(& adb devices)
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to query adb devices."
  }

  $connected = New-Object System.Collections.Generic.List[string]
  foreach ($line in $rows) {
    if ($line -match "^(?<id>\S+)\s+device$") {
      $connected.Add($Matches["id"])
    }
  }
  return @($connected)
}

function Update-PubspecVersionForShip {
  Param([string]$Root)

  $pubspecPath = Join-Path $Root "pubspec.yaml"
  if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
  }

  $lines = @(Get-Content -Path $pubspecPath)
  $versionIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^version:\s*(?<v>\S+)\s*$") {
      $versionIndex = $i
      break
    }
  }

  if ($versionIndex -lt 0) {
    throw "Could not find version: line in pubspec.yaml"
  }

  $oldVersion = $Matches["v"].Trim()
  if (-not ($oldVersion -match "^(?<sem>\d+\.\d+\.\d+)(\+(?<build>\d+))?$")) {
    throw "Unsupported pubspec version format '$oldVersion'. Expected x.y.z or x.y.z+n"
  }

  $sem = $Matches["sem"]
  $buildRaw = $Matches["build"]
  $buildNum = 0
  if (-not [string]::IsNullOrWhiteSpace($buildRaw)) {
    $buildNum = [int]$buildRaw
  }

  $newVersion = "$sem+$($buildNum + 1)"
  $lines[$versionIndex] = "version: $newVersion"

  Set-Content -Path $pubspecPath -Value $lines -Encoding utf8

  return @{
    Old = $oldVersion
    New = $newVersion
    Path = $pubspecPath
  }
}

function Get-PubspecVersion {
  Param([string]$Root)

  $pubspecPath = Join-Path $Root "pubspec.yaml"
  if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
  }

  $versionLine = Get-Content -Path $pubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($versionLine)) {
    throw "Could not parse version from pubspec.yaml"
  }

  return ($versionLine -replace "^version:\s*", "").Trim()
}

$repoRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
} else {
  (Get-Location).Path
}
Set-Location $repoRoot

$pipelineScript = Join-Path $repoRoot "tools/scripts/release_build_install_publish.ps1"
if (-not (Test-Path $pipelineScript)) {
  throw "Missing pipeline script: $pipelineScript"
}

$preflightScript = Join-Path $repoRoot "tools/scripts/ship_it_preflight.ps1"
if (-not (Test-Path $preflightScript)) {
  throw "Missing preflight script: $preflightScript"
}

$syncScript = Join-Path $repoRoot "tools/scripts/sync_release_download_targets.ps1"
if (-not (Test-Path $syncScript)) {
  throw "Missing download target sync script: $syncScript"
}

$remoteConfigSyncScript = Join-Path $repoRoot "tools/scripts/sync_release_remote_config.ps1"
if (-not (Test-Path $remoteConfigSyncScript)) {
  throw "Missing remote config sync script: $remoteConfigSyncScript"
}

Write-Host "== Ship It #2 (prox-us asset release) ==" -ForegroundColor Cyan
Write-Host "Repo root: $repoRoot"
Write-Host "Repo slug: $Repo"
Write-Host "Public repo: $PublicRepo"
Write-Host "Channel:   $ReleaseChannel"
Write-Host "Business Mode build enabled: $($EnableBusinessMode.IsPresent)"

if (-not $SkipVersionBump) {
  $versionUpdate = Update-PubspecVersionForShip -Root $repoRoot
  Write-Host "Version bump: $($versionUpdate.Old) -> $($versionUpdate.New)" -ForegroundColor Cyan
} else {
  Write-Host "Skipped pubspec version bump by request." -ForegroundColor Yellow
}

if (-not $SkipBuildInstall) {
  Assert-Tool "adb"
  if ($DeviceIds.Count -eq 0) {
    $DeviceIds = @(Get-ConnectedAndroidDevices)
    if ($DeviceIds.Count -eq 0) {
      throw "No connected Android devices found. Connect device(s) or pass -DeviceIds explicitly."
    }
    Write-Host "Auto-detected connected devices: $($DeviceIds -join ', ')" -ForegroundColor Cyan
  }
}

if (-not $SkipPreflightChecks) {
  Write-Host "Running preflight checks before ship/publish..." -ForegroundColor Cyan
  $preflightParams = @{}
  if ($PreflightQuickTestsOnly) {
    $preflightParams["QuickTestsOnly"] = $true
  }
  if ($SkipPreflightAnalyze) {
    $preflightParams["SkipAnalyze"] = $true
  }
  if ($SkipPreflightTests) {
    $preflightParams["SkipTests"] = $true
  }
  if ($SkipPreflightSafetyGate) {
    $preflightParams["SkipSafetyGate"] = $true
  }
  if ($SkipPreflightSnapshot) {
    $preflightParams["SkipSnapshot"] = $true
  }
  if ($SkipPreflightRollbackCanonicalCheck) {
    $preflightParams["SkipRollbackCanonicalCheck"] = $true
  }

  & $preflightScript @preflightParams
  if ($LASTEXITCODE -ne 0) {
    throw "Preflight checks failed with exit code $LASTEXITCODE"
  }
}

$privateLatestApkUrl = "https://github.com/$Repo/releases/latest/download/app-release.apk"
if ([string]::IsNullOrWhiteSpace($PublicApkUrl)) {
  $PublicApkUrl = "https://github.com/$PublicRepo/releases/latest/download/app-release.apk"
}
$latestApkUrl = $PublicApkUrl

$pipelineParams = @{
  DeviceIds = $DeviceIds
  Repo = $Repo
  PublicApkUrl = $latestApkUrl
  ReleaseChannel = $ReleaseChannel
}

if ($SkipBuildInstall) {
  $pipelineParams["SkipBuildInstall"] = $true
}
if ($SkipPublish) {
  $pipelineParams["SkipPublish"] = $true
}
if ($CleanInstall) {
  $pipelineParams["CleanInstall"] = $true
}
if (-not $RequireAllDevices) {
  $pipelineParams["AllowPartialDeviceDeploy"] = $true
}
if ($EnableBusinessMode) {
  $pipelineParams["EnableBusinessMode"] = $true
}

& $pipelineScript @pipelineParams
if ($LASTEXITCODE -ne 0) {
  throw "Ship It #2 failed with exit code $LASTEXITCODE"
}

if (-not $SkipPublish -and -not $SkipPublicMirror) {
  if ($PublicRepo -ne $Repo) {
    $version = Get-PubspecVersion -Root $repoRoot
    $publishScript = Join-Path $repoRoot "tools/scripts/publish_github_release.ps1"
    if (-not (Test-Path $publishScript)) {
      throw "Missing publish script: $publishScript"
    }

    Write-Host "Mirroring release asset to public updater repo $PublicRepo..." -ForegroundColor Cyan
    & powershell -ExecutionPolicy Bypass -File $publishScript -Repo $PublicRepo -Tag "v$version" -Title "Prox $version" -Notes "Public APK mirror for tester update delivery."
    if ($LASTEXITCODE -ne 0) {
      throw "Public mirror publish failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Host "Skipped public mirror because PublicRepo matches Repo." -ForegroundColor Yellow
  }
} elseif ($SkipPublicMirror) {
  Write-Host "Skipped public APK mirror by request." -ForegroundColor Yellow
} else {
  Write-Host "Skipped public APK mirror because publish was skipped." -ForegroundColor Yellow
}

if (-not $SkipPublish -and -not $SkipDownloadTargetSync) {
  $syncParams = @{
    Repo = $PublicRepo
    ProjectId = $FirebaseProjectId
    PublicApkUrl = $latestApkUrl
    ReferralDownloadUrl = $ReferralDownloadUrl
  }
  if (-not [string]::IsNullOrWhiteSpace($ReferralCode)) {
    $syncParams["ReferralCode"] = $ReferralCode
  }

  & $syncScript @syncParams
  if ($LASTEXITCODE -ne 0) {
    throw "Download target sync failed with exit code $LASTEXITCODE"
  }
} elseif ($SkipDownloadTargetSync) {
  Write-Host "Skipped website/QR download target sync by request." -ForegroundColor Yellow
} else {
  Write-Host "Skipped download target sync because publish was skipped." -ForegroundColor Yellow
}

if (-not $SkipPublish -and -not $SkipRemoteConfigSync) {
  $latestVersion = Get-PubspecVersion -Root $repoRoot
  $rcParams = @{
    ProjectId = $FirebaseProjectId
    LatestVersion = $latestVersion
    DownloadUrl = $latestApkUrl
    UpdatePollMinutes = $UpdatePollMinutes
  }
  if ($MarkImportantUpdate) {
    $rcParams["MarkImportantUpdate"] = $true
  }
  if (-not [string]::IsNullOrWhiteSpace($ImportantMinVersion)) {
    $rcParams["ImportantMinVersion"] = $ImportantMinVersion
  }

  & $remoteConfigSyncScript @rcParams
  if ($LASTEXITCODE -ne 0) {
    throw "Remote Config sync failed with exit code $LASTEXITCODE"
  }
} elseif ($SkipRemoteConfigSync) {
  Write-Host "Skipped Remote Config sync by request." -ForegroundColor Yellow
} else {
  Write-Host "Skipped Remote Config sync because publish was skipped." -ForegroundColor Yellow
}

Write-Host "Ship It #2 complete." -ForegroundColor Green
Write-Host "Private asset URL: $privateLatestApkUrl" -ForegroundColor Green
Write-Host "Public update URL: $latestApkUrl" -ForegroundColor Green

exit 0
