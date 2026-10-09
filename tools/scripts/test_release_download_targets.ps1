Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$engine = (Get-Process -Id $PID).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ("prox_download_targets_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $root "tools\scripts") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root "functions") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root "web") -Force | Out-Null
$script = Join-Path $root "tools\scripts\sync_release_download_targets.ps1"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "sync_release_download_targets.ps1") -Destination $script
$envPath = Join-Path $root "functions\.env.fixture"
$stable = "https://github.com/marolam/prox/releases/latest/download/app-release.apk"
$pinned = "https://github.com/marolam/prox/releases/download/v0.19.0%2B26/app-release.apk"
Set-Content -LiteralPath (Join-Path $root "web\tester-guide-release.json") -Value (@{ publicApkUrl = $stable } | ConvertTo-Json)

function Invoke-Sync {
  Param([string[]]$Arguments)
  & $engine -NoProfile -ExecutionPolicy Bypass -File $script -EnvFilePath $envPath -SkipDeploy -SkipGate @Arguments | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Download target preparation failed." }
}

function Assert-EnvValue {
  Param([string]$Key, [string]$Expected)
  $matches = @(Get-Content -LiteralPath $envPath | Where-Object { $_ -match "^$Key=" })
  if ($matches.Count -ne 1 -or $matches[0] -cne "$Key=$Expected") {
    throw "Unexpected environment value for $Key."
  }
}

try {
  Set-Content -LiteralPath $envPath -Value @(
    "PROX_REFERRAL_ANDROID_URL=https://github.com/marolam/prox/releases/download/vold/app-release.apk",
    "PROX_REFERRAL_IOS_URL=https://testflight.apple.com/join/existing",
    "PROX_IOS_UPDATE_URL=https://testflight.apple.com/join/existing",
    "PROX_GROWTH_ANDROID_URL=https://github.com/marolam/prox/releases/download/vpilot-staging/app-release-staging.apk",
    "UNRELATED_SETTING=preserved"
  )
  Invoke-Sync -Arguments @("-Platform", "android", "-PublicApkUrl", $pinned)
  foreach ($key in @("PROX_REFERRAL_ANDROID_URL", "PROX_PUBLIC_APK_URL", "PROX_PUBLIC_APK_FALLBACK_URL")) {
    Assert-EnvValue -Key $key -Expected $pinned
  }
  Assert-EnvValue -Key "PROX_REFERRAL_IOS_URL" -Expected "https://testflight.apple.com/join/existing"
  Assert-EnvValue -Key "PROX_GROWTH_ANDROID_URL" -Expected "https://github.com/marolam/prox/releases/download/vpilot-staging/app-release-staging.apk"
  Assert-EnvValue -Key "UNRELATED_SETTING" -Expected "preserved"

  $ios = "https://testflight.apple.com/join/newbuild"
  Invoke-Sync -Arguments @("-Platform", "ios", "-IosUpdateUrl", $ios)
  foreach ($key in @("PROX_REFERRAL_IOS_URL", "PROX_IOS_UPDATE_URL", "PROX_IOS_UPDATE_FALLBACK_URL", "PROX_IOS_FALLBACK_URL")) {
    Assert-EnvValue -Key $key -Expected $ios
  }
  Assert-EnvValue -Key "PROX_PUBLIC_APK_URL" -Expected $pinned
  Invoke-Sync -Arguments @("-Platform", "both", "-PublicApkUrl", $stable, "-IosUpdateUrl", $ios)
  Assert-EnvValue -Key "PROX_REFERRAL_ANDROID_URL" -Expected $stable

  $before = Get-Content -LiteralPath $envPath -Raw
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $engine -NoProfile -ExecutionPolicy Bypass -File $script -EnvFilePath $envPath -SkipDeploy -SkipGate -PublicApkUrl "https://evil.example/app-release.apk" *> $null
    if ($LASTEXITCODE -eq 0) { throw "An invalid APK target was accepted." }
  } finally { $ErrorActionPreference = $previous }
  if ((Get-Content -LiteralPath $envPath -Raw) -cne $before) { throw "Invalid input changed the environment." }

  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $engine -NoProfile -ExecutionPolicy Bypass -File $script -EnvFilePath $envPath -SkipGate -Platform android *> $null
    if ($LASTEXITCODE -eq 0) { throw "An incomplete Functions tree reported successful deployment." }
  } finally { $ErrorActionPreference = $previous }

  $gate = Join-Path $root "tools\scripts\check_referral_qr_release_link.ps1"
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "check_referral_qr_release_link.ps1") -Destination $gate
  $probe = Join-Path $root "probe.txt"
  $fixture = Join-Path $root "probe_fixture.ps1"
  Set-Content -LiteralPath $fixture -Value @'
param([string]$Gate, [string]$Probe, [string]$Expected)
function Invoke-WebRequest {
  param($Uri, $Method, $MaximumRedirection, $TimeoutSec, [switch]$UseBasicParsing, $ErrorAction)
  Set-Content -LiteralPath $Probe -Value "$Method $Uri"
  return [pscustomobject]@{
    StatusCode = 302
    Headers = @{ Location = "https://github.com/marolam/prox/releases/latest/download/app-release.apk" }
  }
}
& $Gate -ReferralDownloadUrl "https://example.invalid/referral?existing=1" -Code "INV123" -PublicApkUrl $Expected
'@
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $engine -NoProfile -ExecutionPolicy Bypass -File $fixture -Gate $gate -Probe $probe -Expected $pinned *> $null
    if ($LASTEXITCODE -eq 0) { throw "A mismatched referral target passed the release gate." }
  } finally { $ErrorActionPreference = $previous }
  $request = Get-Content -LiteralPath $probe -Raw
  if ($request -notmatch '^Head https:' -or $request -notmatch 'existing=1' -or
      $request -notmatch 'platform=android' -or $request -notmatch 'code=INV123') {
    throw "The referral gate did not issue a non-consuming Android probe with preserved query parameters."
  }
  Write-Host "Release download target tests PASS" -ForegroundColor Green
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
