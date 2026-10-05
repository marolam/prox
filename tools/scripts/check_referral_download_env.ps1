Param(
  [string]$DefaultPublicApkUrl = "https://github.com/marolam/prox/releases/latest/download/app-release.apk"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-FirstNonEmpty {
  Param([string[]]$Values)
  foreach ($v in $Values) {
    if (-not [string]::IsNullOrWhiteSpace($v)) {
      return $v.Trim()
    }
  }
  return ""
}

function Test-AllowedAndroidUrl {
  Param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
  try {
    $uri = [Uri]$Url
  } catch {
    return $false
  }
  if ($uri.Scheme -ne "https") { return $false }
  if ($uri.Host -ne "github.com") { return $false }
  $path = $uri.AbsolutePath.ToLowerInvariant()
  return $path.StartsWith("/marolam/prox/releases/") -and $path.EndsWith(".apk")
}

function Test-AllowedIosUrl {
  Param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
  try {
    $uri = [Uri]$Url
  } catch {
    return $false
  }
  if ($uri.Scheme -ne "https") { return $false }
  $allowed = @("apps.apple.com", "testflight.apple.com", "prox-us.com", "www.prox-us.com")
  return $allowed -contains $uri.Host.ToLowerInvariant()
}

$androidPrimary = Read-FirstNonEmpty @(
  $env:PROX_REFERRAL_ANDROID_URL,
  $env:PROX_PUBLIC_APK_URL
)
$androidFallback = Read-FirstNonEmpty @(
  $env:PROX_PUBLIC_APK_FALLBACK_URL,
  $DefaultPublicApkUrl
)
$androidChosen = if (-not [string]::IsNullOrWhiteSpace($androidPrimary)) { $androidPrimary } else { $androidFallback }

$iosPrimary = Read-FirstNonEmpty @(
  $env:PROX_REFERRAL_IOS_URL,
  $env:PROX_IOS_UPDATE_URL
)
$iosFallback = Read-FirstNonEmpty @(
  $env:PROX_IOS_UPDATE_FALLBACK_URL,
  $env:PROX_IOS_FALLBACK_URL
)
$iosChosen = if (-not [string]::IsNullOrWhiteSpace($iosPrimary)) { $iosPrimary } else { $iosFallback }

$androidOk = Test-AllowedAndroidUrl -Url $androidChosen
$iosOk = Test-AllowedIosUrl -Url $iosChosen

Write-Host "== Referral download env gate =="
Write-Host "Android URL: $androidChosen"
Write-Host "iOS URL:     $iosChosen"

if (-not $androidOk) {
  Write-Error "Android referral target is missing/invalid. Set PROX_REFERRAL_ANDROID_URL or PROX_PUBLIC_APK_URL to a valid https://github.com/marolam/prox/releases/... .apk URL."
  exit 1
}

if (-not $iosOk) {
  Write-Error "iOS referral target is missing/invalid. Set PROX_REFERRAL_IOS_URL or PROX_IOS_UPDATE_URL (or fallback keys) to an allowlisted HTTPS host (apps.apple.com/testflight.apple.com/prox-us.com)."
  exit 1
}

Write-Host "Referral download env gate PASS" -ForegroundColor Green
exit 0
