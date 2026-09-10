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

  $queryUrl = "${ReferralDownloadUrl}?code=$Code&ref=$ReferrerUid"
  Write-Host "Checking referral QR URL: $queryUrl" -ForegroundColor Cyan

  $response = $null
  try {
    $response = Invoke-WebRequest -Uri $queryUrl -Method Get -MaximumRedirection 0 -TimeoutSec $TimeoutSeconds -ErrorAction Stop
  } catch {
    $webResp = $_.Exception.Response
    if (-not $webResp) {
      Fail "Request failed before receiving HTTP response: $($_.Exception.Message)"
    }
    $response = $webResp
  }

  $statusCode = [int]$response.StatusCode
  if ($statusCode -lt 300 -or $statusCode -gt 399) {
    if ($statusCode -ge 400) {
      Fail "Referral function returned error HTTP $statusCode"
    }
  }

  $location = [string]$response.Headers["Location"]
  if ([string]::IsNullOrWhiteSpace($location)) {
    Fail "Referral function did not return a Location header."
  }

  Write-Host "Redirect location: $location"

  if (-not (Test-ApkDownloadUrl -Raw $location)) {
    Fail "Redirect target is not a valid HTTPS APK URL."
  }

  $redirectUri = [Uri]$location
  $query = [System.Web.HttpUtility]::ParseQueryString($redirectUri.Query)
  $redirectCode = [string]$query["code"]
  $redirectRef = [string]$query["ref"]

  if ($redirectCode -ne $Code) {
    Fail "Redirect query is missing or mismatched 'code' parameter."
  }
  if ([string]::IsNullOrWhiteSpace($redirectRef)) {
    Fail "Redirect query is missing 'ref' parameter."
  }

  $targetUrl = $location
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

Write-Host "PASS: updater APK URL is live and returns an APK payload." -ForegroundColor Green
exit 0
