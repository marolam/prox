Param(
  [string]$ProjectId = "prox-42bef",
  [string]$LatestVersion,
  [ValidateSet('android', 'ios', 'both')]
  [string]$Platform = 'android',
  [string]$DownloadUrl = "https://github.com/marolam/prox/releases/latest/download/app-release.apk",
  [string]$IosDownloadUrl = "https://www.prox-us.com/tester-portal.html",
  [switch]$MarkImportantUpdate,
  [string]$ImportantMinVersion = "",
  [ValidateRange(5, 240)]
  [int]$UpdatePollMinutes = 20,
  [bool]$ForceLatestEnabled = $true,
  [string]$MinimumRequiredVersion = '',
  [string]$MinimumRequiredNotes = 'Please install the latest update for matching and safety fixes.',
  [switch]$IncludeLegacyAndroidPolicy,
  [switch]$PrepareOnly,
  [string]$InputTemplatePath = '',
  [string]$OutputPath = '',
  [switch]$DisableUpdateCheck
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

function Get-TemplateParameterNode {
  Param(
    [object]$Template,
    [string]$Key
  )

  $parametersProp = $Template.PSObject.Properties["parameters"]
  if ($null -eq $parametersProp -or $null -eq $parametersProp.Value) {
    $Template | Add-Member -MemberType NoteProperty -Name parameters -Value ([pscustomobject]@{}) -Force
  }

  $matches = @()
  $paramNode = $Template.parameters.PSObject.Properties[$Key]
  if ($null -ne $paramNode -and $null -ne $paramNode.Value) { $matches += $paramNode.Value }
  $groups = $Template.PSObject.Properties['parameterGroups']
  if ($groups -and $groups.Value) {
    foreach ($group in $groups.Value.PSObject.Properties) {
      $groupParameters = $group.Value.PSObject.Properties['parameters']
      if ($groupParameters -and $groupParameters.Value) {
        $groupNode = $groupParameters.Value.PSObject.Properties[$Key]
        if ($groupNode -and $null -ne $groupNode.Value) { $matches += $groupNode.Value }
      }
    }
  }
  if ($matches.Count -gt 1) { throw "Parameter '$Key' occurs in more than one template group." }
  if ($matches.Count -eq 1) { return $matches[0] }
  $node = [pscustomobject]@{}
  $Template.parameters | Add-Member -MemberType NoteProperty -Name $Key -Value $node -Force
  return $node
}

function Set-AndroidPolicyCondition {
  Param([object]$Template, [string]$Name, [string]$Expression, [string[]]$PolicyKeys)

  $conditions = @()
  $conditionsProperty = $Template.PSObject.Properties['conditions']
  if ($conditionsProperty -and $conditionsProperty.Value) { $conditions = @($conditionsProperty.Value) }
  $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $ownedCondition = $null
  foreach ($condition in $conditions) {
    if (-not $names.Add($condition.name)) { throw "Duplicate Remote Config condition '$($condition.name)'." }
    if ($condition.name -ceq $Name) {
      if ($condition.expression -cne $Expression) {
        throw "Reserved condition '$Name' has a conflicting expression. Review it before activating a legacy policy."
      }
      $ownedCondition = $condition
    }
  }

  # This condition will have highest priority. Never change the priority of an
  # unrelated parameter that happens to reference the reserved condition name.
  $parameterMaps = @()
  $parametersProperty = $Template.PSObject.Properties['parameters']
  if ($parametersProperty -and $parametersProperty.Value) { $parameterMaps += $parametersProperty.Value }
  $groups = $Template.PSObject.Properties['parameterGroups']
  if ($groups -and $groups.Value) {
    foreach ($group in $groups.Value.PSObject.Properties) {
      $groupParameters = $group.Value.PSObject.Properties['parameters']
      if ($groupParameters -and $groupParameters.Value) { $parameterMaps += $groupParameters.Value }
    }
  }
  foreach ($map in $parameterMaps) {
    foreach ($parameter in $map.PSObject.Properties) {
      $conditional = $parameter.Value.PSObject.Properties['conditionalValues']
      if ($conditional -and $conditional.Value -and $conditional.Value.PSObject.Properties[$Name]) {
        if (-not $ownedCondition -or $parameter.Name -cnotin $PolicyKeys) {
          throw "Reserved condition '$Name' is referenced by conflicting parameter '$($parameter.Name)'."
        }
      }
    }
  }
  if (-not $ownedCondition) {
    $ownedCondition = [pscustomobject]@{ name = $Name; expression = $Expression; tagColor = 'BLUE' }
  }
  $mergedConditions = @($ownedCondition) + @($conditions | Where-Object { $_.name -cne $Name })
  $Template | Add-Member -MemberType NoteProperty -Name conditions -Value $mergedConditions -Force
}

function Set-ParamValue {
  Param(
    [object]$Template,
    [string]$Key,
    [string]$Value,
    [string]$ConditionName = ''
  )

  $node = Get-TemplateParameterNode -Template $Template -Key $Key
  if ($ConditionName) {
    $conditional = $node.PSObject.Properties['conditionalValues']
    if (-not $conditional -or -not $conditional.Value) {
      $node | Add-Member -MemberType NoteProperty -Name conditionalValues -Value ([pscustomobject]@{}) -Force
    }
    $node.conditionalValues | Add-Member -MemberType NoteProperty -Name $ConditionName -Value ([pscustomobject]@{ value = $Value }) -Force
  } else {
    # RemoteConfigParameterValue is a union: replace useInAppDefault rather than
    # producing an invalid object containing both that member and a literal value.
    $node | Add-Member -MemberType NoteProperty -Name defaultValue -Value ([pscustomobject]@{ value = $Value }) -Force
  }
}

function Merge-ReleasePolicy {
  Param([object]$Template)
  if ($Platform -in @('android', 'both') -and -not $IncludeLegacyAndroidPolicy) {
    $conditions = $Template.PSObject.Properties['conditions']
    if ($conditions -and @($conditions.Value | Where-Object { $_.name -ceq 'prox_legacy_android_update_policy' }).Count -gt 0) {
      throw 'An active legacy Android condition overrides defaults. Use Platform android with IncludeLegacyAndroidPolicy and a pinned APK URL, then update iOS separately.'
    }
  }
  if ($IncludeLegacyAndroidPolicy) {
    Set-AndroidPolicyCondition -Template $Template -Name $legacyConditionName -Expression $legacyConditionExpression -PolicyKeys @($policyValues.Keys)
  }
  foreach ($entry in $policyValues.GetEnumerator()) {
    Set-ParamValue -Template $Template -Key $entry.Key -Value $entry.Value -ConditionName $legacyConditionName
  }
  return $Template
}

if ($InputTemplatePath -and -not $PrepareOnly) { throw 'InputTemplatePath is allowed only with PrepareOnly. Deployment always fetches the current template.' }
if ($IncludeLegacyAndroidPolicy -and $Platform -ne 'android') { throw 'IncludeLegacyAndroidPolicy requires Platform android.' }

if ([string]::IsNullOrWhiteSpace($LatestVersion)) {
  throw "LatestVersion is required. Pass -LatestVersion from ship script."
}

$versionPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?(?:\+[0-9]+)?$'
if ($LatestVersion.Trim() -notmatch $versionPattern) {
  throw 'LatestVersion must be an installed package version, such as 0.18.8+18 (not a release alias).'
}
if ([string]::IsNullOrWhiteSpace($MinimumRequiredVersion)) {
  $MinimumRequiredVersion = if ($ForceLatestEnabled) { $LatestVersion.Trim() } else { '' }
}
foreach ($versionValue in @($MinimumRequiredVersion, $ImportantMinVersion)) {
  if ($versionValue -and $versionValue -notmatch $versionPattern) { throw "Invalid policy version: $versionValue" }
}
foreach ($urlValue in @($DownloadUrl, $IosDownloadUrl)) {
  $parsedUrl = $null
  if (-not [Uri]::TryCreate($urlValue, [UriKind]::Absolute, [ref]$parsedUrl) -or
      $parsedUrl.Scheme -ne 'https' -or $parsedUrl.UserInfo) {
    throw 'Update URLs must be absolute HTTPS URLs without credentials.'
  }
}
if ($Platform -in @('ios', 'both')) {
  $iosUri = [Uri]$IosDownloadUrl
  if ($iosUri.Host -notin @('apps.apple.com', 'testflight.apple.com')) {
    throw 'An iOS version gate requires the released App Store or TestFlight URL. A portal or raw IPA is insufficient.'
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..') -ErrorAction Stop).Path
$legacyConditionName = ''
$legacyConditionExpression = ''
if ($IncludeLegacyAndroidPolicy) {
  # Build 18 reads shared keys only. Scope their values to the actual Android
  # Firebase app instead of changing the defaults delivered to older iOS apps.
  $androidConfigPath = Join-Path $repoRoot 'android/app/src/release/google-services.json'
  $androidConfig = Get-Content -LiteralPath $androidConfigPath -Raw | ConvertFrom-Json
  if ($androidConfig.project_info.project_id -cne $ProjectId) {
    throw 'ProjectId does not match the local release Android Firebase configuration.'
  }
  $gradle = Get-Content -LiteralPath (Join-Path $repoRoot 'android/app/build.gradle') -Raw
  $packageMatches = [regex]::Matches($gradle, '(?m)^\s*applicationId\s+["'']([^"'']+)["'']\s*$')
  if ($packageMatches.Count -ne 1) { throw 'Cannot resolve a unique literal Android release applicationId.' }
  $packageId = $packageMatches[0].Groups[1].Value
  $clients = @($androidConfig.client | Where-Object { $_.client_info.android_client_info.package_name -ceq $packageId })
  if ($clients.Count -ne 1) { throw 'The Android release applicationId must match exactly one Firebase client.' }
  $firebaseAppId = [string]$clients[0].client_info.mobilesdk_app_id
  $projectNumber = [regex]::Escape([string]$androidConfig.project_info.project_number)
  if ($firebaseAppId -cnotmatch "^1:${projectNumber}:android:[0-9a-f]+$") {
    throw 'The Firebase app ID must identify the configured Android project.'
  }
  $apkUri = [Uri]$DownloadUrl
  $apkPath = [Uri]::UnescapeDataString($apkUri.AbsolutePath)
  $pinnedPath = '^/[^/]+/[^/]+/releases/download/v?' + [regex]::Escape($LatestVersion.Trim()) + '/[^/]+\.apk$'
  if ($apkUri.Host -ine 'github.com' -or $apkUri.Query -or $apkUri.Fragment -or $apkPath -cnotmatch $pinnedPath) {
    throw 'Legacy Android policy requires a pinned GitHub APK asset URL whose release tag matches LatestVersion (for example /releases/download/v0.19.0+19/app-release.apk). Publish and verify that asset before activating the policy.'
  }
  $legacyConditionName = 'prox_legacy_android_update_policy'
  $legacyConditionExpression = "app.id == '$firebaseAppId'"
}

$importantMin = if ($ImportantMinVersion) { $ImportantMinVersion.Trim() } else { $LatestVersion.Trim() }
$enabledValue = (-not $DisableUpdateCheck).ToString().ToLowerInvariant()
$policyValues = [ordered]@{
  update_check_enabled = $enabledValue
  update_force_latest_enabled = $ForceLatestEnabled.ToString().ToLowerInvariant()
  update_important_enabled = $MarkImportantUpdate.IsPresent.ToString().ToLowerInvariant()
  update_minimum_required_enabled = (-not [string]::IsNullOrWhiteSpace($MinimumRequiredVersion)).ToString().ToLowerInvariant()
  update_minimum_required_notes = $MinimumRequiredNotes
  update_poll_minutes = $UpdatePollMinutes.ToString()
}
$platforms = if ($Platform -eq 'both') { @('android', 'ios') } else { @($Platform) }
foreach ($targetPlatform in $platforms) {
  $policyValues["update_latest_version_$targetPlatform"] = $LatestVersion.Trim()
  $policyValues["update_minimum_required_version_$targetPlatform"] = $MinimumRequiredVersion.Trim()
  $policyValues["update_important_min_version_$targetPlatform"] = $importantMin
}
if ($Platform -ne 'both') {
  foreach ($key in @('update_check_enabled', 'update_force_latest_enabled',
      'update_important_enabled', 'update_minimum_required_enabled')) {
    $policyValues["${key}_$Platform"] = $policyValues[$key]
    if (-not $IncludeLegacyAndroidPolicy) { $policyValues.Remove($key) }
  }
} else {
  foreach ($key in @('update_check_enabled', 'update_force_latest_enabled',
      'update_important_enabled', 'update_minimum_required_enabled')) {
    foreach ($targetPlatform in $platforms) {
      $policyValues["${key}_$targetPlatform"] = $policyValues[$key]
    }
  }
}
if ($Platform -in @('android', 'both')) { $policyValues['update_download_url'] = $DownloadUrl.Trim() }
if ($Platform -in @('ios', 'both')) { $policyValues['update_download_url_ios'] = $IosDownloadUrl.Trim() }
if ($Platform -eq 'both' -or $IncludeLegacyAndroidPolicy) {
  # Legacy clients read the shared policy. Advance it only after both platforms
  # have the same installable release, or explicitly condition them to Android.
  $policyValues['update_latest_version'] = $LatestVersion.Trim()
  $policyValues['update_minimum_required_version'] = $MinimumRequiredVersion.Trim()
  $policyValues['update_important_min_version'] = $importantMin
}

if ($PrepareOnly) {
  $preview = if ($InputTemplatePath) {
    Get-Content -LiteralPath $InputTemplatePath -Raw | ConvertFrom-Json
  } else { [pscustomobject]@{ parameters = [pscustomobject]@{} } }
  $preview = Merge-ReleasePolicy -Template $preview
  $previewJson = $preview | ConvertTo-Json -Depth 30
  if ($OutputPath) { Set-Content -LiteralPath $OutputPath -Value $previewJson -Encoding utf8 }
  else { Write-Output $previewJson }
  exit 0
}

Assert-Tool "firebase"

Set-Location $repoRoot

$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("prox_rc_sync_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$templatePath = Join-Path $tmpDir "remoteconfig.template.json"
$configPath = Join-Path $tmpDir "firebase.remoteconfig.json"

try {
  Write-Host "== Sync release Remote Config update keys ==" -ForegroundColor Cyan
  Write-Host "Project:         $ProjectId"
  Write-Host "Latest version:  $LatestVersion"
  Write-Host "Download URL:    $DownloadUrl"
  Write-Host "iOS download URL:$IosDownloadUrl"
  Write-Host "Important update:$($MarkImportantUpdate.IsPresent)"
  Write-Host "Force latest:    $ForceLatestEnabled"
  if ($IncludeLegacyAndroidPolicy) {
    Write-Host "Legacy scope:    $legacyConditionExpression (highest-priority update condition)"
  }

  & firebase remoteconfig:get --project $ProjectId -o $templatePath
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to fetch Remote Config template."
  }

  $raw = Get-Content -Path $templatePath -Raw
  $template = ConvertFrom-Json -InputObject $raw

  $template = Merge-ReleasePolicy -Template $template

  $json = $template | ConvertTo-Json -Depth 30
  Set-Content -Path $templatePath -Value $json -Encoding utf8

  $deployConfig = @{
    remoteconfig = @{
      template = $templatePath
    }
  } | ConvertTo-Json -Depth 5
  Set-Content -Path $configPath -Value $deployConfig -Encoding utf8

  & firebase deploy --project $ProjectId --only remoteconfig --config $configPath
  if ($LASTEXITCODE -ne 0) {
    throw "Remote Config deploy failed with exit code $LASTEXITCODE"
  }

  Write-Host "Remote Config release update keys synced." -ForegroundColor Green
}
finally {
  if (Test-Path $tmpDir) {
    $resolvedTemporary = [IO.Path]::GetFullPath($tmpDir)
    $allowedTemporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemporary.StartsWith($allowedTemporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolvedTemporary)).StartsWith('prox_rc_sync_')) {
      throw 'Refusing to remove a temporary path outside the Remote Config workspace.'
    }
    Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
