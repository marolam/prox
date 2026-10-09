Param(
  [string]$ReferralDownloadUrl = "https://us-central1-prox-42bef.cloudfunctions.net/referralApkDownload",
  [string]$PublicApkUrl = "",
  [string]$Code = "",
  [string]$ReferrerUid = "release_signoff",
  [switch]$AllowNonLatestGithubPath,
  [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Web

function Fail {
  Param([string]$Message)
  Write-Error $Message
  exit 1
}

function Test-ApkDownloadUrl {
  Param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $false }
  try {
    $uri = [Uri]$Raw
  } catch {
    return $false
  }
  if ($uri.Scheme -ne "https") { return $false }
  return $uri.AbsolutePath.ToLowerInvariant().EndsWith(".apk")
}

if (-not [string]::IsNullOrWhiteSpace($Code)) {
  if ([string]::IsNullOrWhiteSpace($ReferralDownloadUrl)) {
    Fail "Referral download URL is required when -Code is provided."
  }

  $builder = New-Object System.UriBuilder($ReferralDownloadUrl)
  $params = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
  $params["code"] = $Code
  $params["ref"] = $ReferrerUid
  $params["platform"] = "android"
  $builder.Query = $params.ToString()
  $queryUrl = $builder.Uri.AbsoluteUri
  Write-Host "Checking referral QR URL: $queryUrl" -ForegroundColor Cyan

  $response = $null
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $queryUrl -Method Head -MaximumRedirection 0 -TimeoutSec $TimeoutSeconds -ErrorAction Stop
  } catch {
    $webResp = $_.Exception.Response
    if (-not $webResp) {
      Fail "Request failed before receiving HTTP response: $($_.Exception.Message)"
    }
    $response = $webResp
  }

  $statusCode = [int]$response.StatusCode
  if ($statusCode -ne 302) {
    Fail "Referral function must return HTTP 302, received HTTP $statusCode"
  }

  $location = [string]$response.Headers["Location"]
  if ([string]::IsNullOrWhiteSpace($location)) {
    Fail "Referral function did not return a Location header."
  }

  Write-Host "Redirect location: $location"

  if (-not (Test-ApkDownloadUrl -Raw $location)) {
    Fail "Redirect target is not a valid HTTPS APK URL."
  }

  $targetUrl = $location
  # HEAD probes deliberately create no lead and carry no attribution query.
} else {
  $targetUrl = $PublicApkUrl
  if ([string]::IsNullOrWhiteSpace($targetUrl)) {
    $targetUrl = "https://github.com/marolam/prox/releases/latest/download/app-release.apk"
  }
  Write-Host "No live referral code provided; validating configured APK target only: $targetUrl" -ForegroundColor Yellow
  if (-not (Test-ApkDownloadUrl -Raw $targetUrl)) {
    Fail "Configured APK target is not a valid HTTPS APK URL."
  }
}

$targetUri = [Uri]$targetUrl
if (-not [string]::IsNullOrWhiteSpace($PublicApkUrl)) {
  $expectedUri = [Uri]$PublicApkUrl
  if ($targetUri.GetLeftPart([UriPartial]::Path) -cne $expectedUri.GetLeftPart([UriPartial]::Path)) {
    Fail "Referral destination differs from the updater APK: expected $PublicApkUrl, received $targetUrl"
  }
}
$path = $targetUri.AbsolutePath.ToLowerInvariant()
$isGithubLatest = $targetUri.Host.ToLowerInvariant() -eq "github.com" -and $path -match "/releases/latest/download/app-release\.apk$"

if (-not $AllowNonLatestGithubPath -and -not $isGithubLatest) {
  Fail "Redirect target is not GitHub latest canonical APK path. Use -AllowNonLatestGithubPath to bypass."
}

Write-Host "Confirming APK is publicly downloadable..." -ForegroundColor Cyan
$httpClient = $null
$responseMessage = $null
$responseStream = $null
try {
  Add-Type -AssemblyName System.Net.Http
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect = $true
  $handler.MaxAutomaticRedirections = 10
  $httpClient = New-Object System.Net.Http.HttpClient($handler)
  $httpClient.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
  $requestMessage = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $targetUrl)
  $requestMessage.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue(0, 3)
  $responseMessage = $httpClient.SendAsync(
    $requestMessage,
    [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
  ).GetAwaiter().GetResult()
  $downloadStatus = [int]$responseMessage.StatusCode
  if ($downloadStatus -ne 200 -and $downloadStatus -ne 206) {
    Fail "APK download returned unexpected HTTP $downloadStatus"
  }

  $responseStream = $responseMessage.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
  $bytes = New-Object byte[] 4
  $bytesRead = $responseStream.Read($bytes, 0, 4)
  if ($bytesRead -lt 2 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
    Fail "Download target did not return an APK/ZIP payload."
  }
} catch {
  Fail "APK download verification failed: $($_.Exception.Message)"
}
finally {
  if ($null -ne $responseStream) { $responseStream.Dispose() }
  if ($null -ne $responseMessage) { $responseMessage.Dispose() }
  if ($null -ne $httpClient) { $httpClient.Dispose() }
}

if ($Code) {
  Write-Host "PASS: referral routing matches the updater and returns an APK payload." -ForegroundColor Green
} else {
  Write-Host "PASS: updater APK URL is live. Referral routing was not checked without -Code." -ForegroundColor Yellow
}
exit 0
