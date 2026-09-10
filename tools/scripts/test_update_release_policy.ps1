Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$script = Join-Path $PSScriptRoot 'sync_release_remote_config.ps1'

function Read-PreparedTemplate {
  Param([string[]]$PolicyArguments)
  $output = & $engine -NoProfile -ExecutionPolicy Bypass -File $script -PrepareOnly @PolicyArguments
  if ($LASTEXITCODE -ne 0) { throw 'Policy preparation failed.' }
  return ($output | Out-String | ConvertFrom-Json)
}

function Assert-RejectedPolicy {
  Param([string[]]$PolicyArguments, [string]$Reason)
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $engine -NoProfile -ExecutionPolicy Bypass -File $script -PrepareOnly @PolicyArguments *> $null
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previous
  if ($exitCode -eq 0) { throw "An invalid policy was accepted: $Reason" }
}

function Assert-SameJson {
  Param([object]$Actual, [object]$Expected, [string]$Reason)
  if (($Actual | ConvertTo-Json -Depth 30 -Compress) -cne ($Expected | ConvertTo-Json -Depth 30 -Compress)) {
    throw $Reason
  }
}

function Get-EffectiveValue {
  Param([object]$Template, [object]$Parameter, [string[]]$MatchingConditions)
  foreach ($condition in $Template.conditions) {
    if ($condition.name -cin $MatchingConditions) {
      $conditional = $Parameter.PSObject.Properties['conditionalValues']
      if ($conditional -and $conditional.Value.PSObject.Properties[$condition.name]) {
        return $conditional.Value.($condition.name).value
      }
    }
  }
  $default = $Parameter.PSObject.Properties['defaultValue']
  if ($default -and $default.Value.PSObject.Properties['value']) { return $default.Value.value }
  return $null
}

$android = (Read-PreparedTemplate -PolicyArguments @('-LatestVersion', '0.18.8+18')).parameters
if ($android.update_latest_version_android.defaultValue.value -ne '0.18.8+18') {
  throw 'Android policy did not preserve the full installed version.'
}
if ($android.PSObject.Properties['update_latest_version_ios'] -or
    $android.PSObject.Properties['update_latest_version'] -or
    $android.PSObject.Properties['update_force_latest_enabled']) {
  throw 'An Android-only release modified a shared or iOS policy.'
}

$paired = (Read-PreparedTemplate -PolicyArguments @('-LatestVersion', '0.18.8+18', '-Platform', 'both',
  '-IosDownloadUrl', 'https://testflight.apple.com/join/release')).parameters
foreach ($key in @('update_latest_version', 'update_latest_version_android', 'update_latest_version_ios',
    'update_minimum_required_version_android', 'update_minimum_required_version_ios')) {
  if ($paired.$key.defaultValue.value -ne '0.18.8+18') { throw "Paired policy mismatch: $key" }
}

foreach ($invalid in @(
  @('-LatestVersion', 'release-2026'),
  @('-LatestVersion', '0.18.8+18', '-Platform', 'ios'),
  @('-LatestVersion', '0.18.8+18', '-DownloadUrl', 'http://example.com/app.apk')
)) {
  Assert-RejectedPolicy -PolicyArguments $invalid -Reason 'invalid version or install URL'
}

$conditionName = 'prox_legacy_android_update_policy'
$androidAppId = '1:12575732319:android:c5ec68ebc2de45de5561ea'
$pinnedUrl = 'https://github.com/marolam/prox/releases/download/v0.19.0+19/app-release.apk'
$legacyArguments = @('-LatestVersion', '0.19.0+19', '-Platform', 'android',
  '-IncludeLegacyAndroidPolicy', '-DownloadUrl', $pinnedUrl)
$legacy = Read-PreparedTemplate -PolicyArguments $legacyArguments
if (@($legacy.conditions).Count -ne 1 -or $legacy.conditions[0].name -cne $conditionName -or
    $legacy.conditions[0].expression -cne "app.id == '$androidAppId'") {
  throw 'Legacy policy did not target the actual release Firebase Android app.'
}
foreach ($parameter in $legacy.parameters.PSObject.Properties) {
  if ($parameter.Name.EndsWith('_ios') -or $parameter.Value.PSObject.Properties['defaultValue']) {
    throw "Legacy Android mode changed a default or iOS parameter: $($parameter.Name)"
  }
  if (@($parameter.Value.conditionalValues.PSObject.Properties).Count -ne 1 -or
      -not $parameter.Value.conditionalValues.PSObject.Properties[$conditionName]) {
    throw "Legacy Android parameter has an unscoped value: $($parameter.Name)"
  }
}
foreach ($key in @('update_latest_version', 'update_minimum_required_version',
    'update_latest_version_android', 'update_minimum_required_version_android')) {
  if ($legacy.parameters.$key.conditionalValues.$conditionName.value -cne '0.19.0+19') {
    throw "Legacy or current Android version is incorrect: $key"
  }
}
foreach ($key in @('update_check_enabled', 'update_force_latest_enabled', 'update_minimum_required_enabled',
    'update_check_enabled_android', 'update_force_latest_enabled_android', 'update_minimum_required_enabled_android')) {
  if ($legacy.parameters.$key.conditionalValues.$conditionName.value -cne 'true') {
    throw "Legacy or current Android enforcement was not enabled: $key"
  }
}
if ($legacy.parameters.update_download_url.conditionalValues.$conditionName.value -cne $pinnedUrl) {
  throw 'Legacy Android policy lost its pinned APK URL.'
}

# A real template may group update keys and contain other Android/iOS cohorts.
# Exercise exactly the merge function used after fetching a live template.
$fixture = @'
{
  "conditions": [
    {"name":"ios_testers","expression":"app.id == '1:12575732319:ios:example'","tagColor":"GREEN"},
    {"name":"previous_android","expression":"app.id == '1:12575732319:android:c5ec68ebc2de45de5561ea'","tagColor":"PINK"}
  ],
  "parameters": {
    "update_latest_version":{"defaultValue":{"value":"0.18.8+18"},"conditionalValues":{"ios_testers":{"value":"0.18.7+17"},"previous_android":{"value":"0.18.8+18"}},"description":"Keep global fallback","valueType":"STRING"},
    "update_minimum_required_version":{"defaultValue":{"value":"0.18.8+18"},"conditionalValues":{"ios_testers":{"value":"0.18.7+17"}}},
    "update_minimum_required_enabled":{"defaultValue":{"value":"false"},"conditionalValues":{"ios_testers":{"value":"false"}},"valueType":"BOOLEAN"},
    "update_force_latest_enabled":{"defaultValue":{"value":"false"},"conditionalValues":{"ios_testers":{"value":"false"}}},
    "update_check_enabled":{"defaultValue":{"value":"true"}},
    "update_poll_minutes":{"defaultValue":{"value":"45"},"valueType":"NUMBER"},
    "update_minimum_required_notes":{"defaultValue":{"value":"Existing iOS notes"}},
    "update_download_url":{"defaultValue":{"value":"https://github.com/marolam/prox/releases/latest/download/app-release.apk"}},
    "update_download_url_ios":{"defaultValue":{"value":"https://testflight.apple.com/join/existing"}},
    "update_latest_version_ios":{"defaultValue":{"value":"0.18.7+17"},"conditionalValues":{"ios_testers":{"value":"0.18.8+18"}}},
    "unrelated_feature":{"defaultValue":{"value":"off"},"conditionalValues":{"ios_testers":{"value":"on"},"previous_android":{"value":"on"}},"description":"Do not modify"}
  },
  "parameterGroups": {
    "Android Updates":{"description":"Existing grouping","parameters":{
      "update_latest_version_android":{"defaultValue":{"useInAppDefault":true},"conditionalValues":{"previous_android":{"value":"0.18.8+18"}},"description":"Keep this grouped","valueType":"STRING"}
    }},
    "Other settings":{"description":"Keep group metadata","parameters":{"feature_limit":{"defaultValue":{"value":"12"},"valueType":"NUMBER"}}}
  },
  "version":{"versionNumber":"52","description":"Original template metadata"}
}
'@ | ConvertFrom-Json
$fixturePath = [IO.Path]::GetTempFileName()
$repeatPath = [IO.Path]::GetTempFileName()
try {
  $fixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $fixturePath -Encoding utf8
  $merged = Read-PreparedTemplate -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $fixturePath))
  Assert-SameJson -Actual @($merged.conditions | Select-Object -Skip 1) -Expected $fixture.conditions -Reason 'Unrelated conditions or their relative priority changed.'
  Assert-SameJson -Actual $merged.version -Expected $fixture.version -Reason 'Template metadata changed.'
  foreach ($parameter in $fixture.parameters.PSObject.Properties) {
    $actual = $merged.parameters.($parameter.Name)
    Assert-SameJson -Actual $actual.defaultValue -Expected $parameter.Value.defaultValue -Reason "Global default changed: $($parameter.Name)"
    foreach ($metadata in @('description', 'valueType')) {
      if ($parameter.Value.PSObject.Properties[$metadata]) {
        Assert-SameJson -Actual $actual.$metadata -Expected $parameter.Value.$metadata -Reason "Parameter metadata changed: $($parameter.Name)"
      }
    }
    if ($parameter.Value.PSObject.Properties['conditionalValues']) {
      foreach ($oldCondition in $parameter.Value.conditionalValues.PSObject.Properties) {
        Assert-SameJson -Actual $actual.conditionalValues.($oldCondition.Name) -Expected $oldCondition.Value -Reason "Existing conditional value changed: $($parameter.Name)"
      }
    }
    if ($parameter.Name.EndsWith('_ios') -or $parameter.Name -eq 'unrelated_feature') {
      Assert-SameJson -Actual $actual -Expected $parameter.Value -Reason "Unrelated/iOS parameter changed: $($parameter.Name)"
    }
  }
  $androidGroup = $merged.parameterGroups.'Android Updates'
  Assert-SameJson -Actual $androidGroup.description -Expected $fixture.parameterGroups.'Android Updates'.description -Reason 'Update group description changed.'
  Assert-SameJson -Actual $androidGroup.parameters.update_latest_version_android.defaultValue -Expected $fixture.parameterGroups.'Android Updates'.parameters.update_latest_version_android.defaultValue -Reason 'Grouped Android default changed.'
  Assert-SameJson -Actual $merged.parameterGroups.'Other settings' -Expected $fixture.parameterGroups.'Other settings' -Reason 'Unrelated parameter group changed.'
  if ($merged.parameters.PSObject.Properties['update_latest_version_android']) { throw 'Grouped key was duplicated at template root.' }
  foreach ($key in @('update_latest_version', 'update_minimum_required_version')) {
    $androidValue = Get-EffectiveValue -Template $merged -Parameter $merged.parameters.$key -MatchingConditions @($conditionName, 'previous_android')
    $iosValue = Get-EffectiveValue -Template $merged -Parameter $merged.parameters.$key -MatchingConditions @('ios_testers')
    $globalValue = Get-EffectiveValue -Template $merged -Parameter $merged.parameters.$key -MatchingConditions @()
    if ($androidValue -cne '0.19.0+19' -or $iosValue -cne '0.18.7+17' -or $globalValue -cne '0.18.8+18') {
      throw "Legacy effective value isolation failed: $key"
    }
  }
  $currentAndroid = Get-EffectiveValue -Template $merged -Parameter $androidGroup.parameters.update_latest_version_android -MatchingConditions @($conditionName, 'previous_android')
  if ($currentAndroid -cne '0.19.0+19') { throw 'Current Android override did not advance alongside the legacy policy.' }

  # Repeating an activation should update the owned condition, never duplicate it.
  $merged | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $repeatPath -Encoding utf8
  Assert-RejectedPolicy -PolicyArguments @('-LatestVersion', '0.19.0+20', '-Platform', 'android', '-InputTemplatePath', $repeatPath) -Reason 'default-only Android update would be masked by the active legacy condition'
  $repeated = Read-PreparedTemplate -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $repeatPath))
  Assert-SameJson -Actual $repeated -Expected $merged -Reason 'Repeating the same merge was not idempotent.'

  $merged.conditions[0].expression = "device.os == 'ios'"
  $merged | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $repeatPath -Encoding utf8
  Assert-RejectedPolicy -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $repeatPath)) -Reason 'reserved condition has conflicting scope'
  $merged.conditions[0].expression = "app.id == '$androidAppId'"
  $merged.parameters.unrelated_feature.conditionalValues | Add-Member -MemberType NoteProperty -Name $conditionName -Value ([pscustomobject]@{value='conflict'})
  $merged | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $repeatPath -Encoding utf8
  Assert-RejectedPolicy -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $repeatPath)) -Reason 'reserved condition used by an unrelated feature'

  $fixture.conditions = @($fixture.conditions) + @($fixture.conditions[0])
  $fixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $repeatPath -Encoding utf8
  Assert-RejectedPolicy -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $repeatPath)) -Reason 'duplicate condition names'
  $fixture.conditions = @($fixture.conditions | Select-Object -First 2)
  $fixture.parameters | Add-Member -MemberType NoteProperty -Name update_latest_version_android -Value ([pscustomobject]@{defaultValue=[pscustomobject]@{value='0.18.8+18'}})
  $fixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $repeatPath -Encoding utf8
  Assert-RejectedPolicy -PolicyArguments ($legacyArguments + @('-InputTemplatePath', $repeatPath)) -Reason 'duplicate grouped parameter'
} finally {
  Remove-Item -LiteralPath $fixturePath -Force
  Remove-Item -LiteralPath $repeatPath -Force
}

foreach ($invalid in @(
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy'),
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy', '-DownloadUrl', 'https://github.com/marolam/prox/releases/download/v0.18.8+18/app-release.apk'),
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy', '-DownloadUrl', 'https://github.com/marolam/prox/releases/download/v1.0/app-release.apk'),
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy', '-DownloadUrl', 'https://example.com/releases/download/v0.19.0+19/app-release.apk'),
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy', '-DownloadUrl', $pinnedUrl, '-ProjectId', 'another-project'),
  @('-LatestVersion', '0.19.0+19', '-IncludeLegacyAndroidPolicy', '-Platform', 'both', '-DownloadUrl', $pinnedUrl, '-IosDownloadUrl', 'https://testflight.apple.com/join/release')
)) {
  Assert-RejectedPolicy -PolicyArguments $invalid -Reason 'legacy policy has an unpinned/mismatched URL, wrong Firebase project, or non-Android scope'
}

Write-Host 'Release policy regression checks passed: default Android isolation, paired parity, legacy Android enforcement, preserved iOS/defaults/conditions/groups, idempotent merges, conflict rejection, and pinned version URLs. All checks used PrepareOnly; no Firebase command ran.'
exit 0
