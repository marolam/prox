Param(
  [Parameter(Mandatory = $true)]
  [string]$Url,

  [Parameter(Mandatory = $true)]
  [ValidateSet("public", "restricted")]
  [string]$ExpectedAccess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Request {
  Param(
    [string]$Method,
    [string]$RequestUrl
  )

  try {
    return Invoke-WebRequest -Uri $RequestUrl -Method $Method -MaximumRedirection 10 -UseBasicParsing -ErrorAction Stop
  }
  catch {
    $responseProp = $_.Exception.PSObject.Properties["Response"]
    if ($null -ne $responseProp -and $null -ne $responseProp.Value) {
      return $responseProp.Value
    }
    throw
  }
}

function Get-HeaderValue {
  Param(
    $Response,
    [string]$HeaderName
  )

  try {
    if ($Response.Headers[$HeaderName]) {
      return [string]$Response.Headers[$HeaderName]
    }
  }
  catch {
    # fall through
  }

  return ""
}

Write-Host "== APK endpoint gate ==" -ForegroundColor Cyan
Write-Host "URL:      $Url"
Write-Host "Expected: $ExpectedAccess"

$response = Invoke-Request -Method "Head" -RequestUrl $Url
$status = [int]$response.StatusCode
$contentType = (Get-HeaderValue -Response $response -HeaderName "Content-Type").ToLowerInvariant()
$location = Get-HeaderValue -Response $response -HeaderName "Location"
$finalUrl = ""
try {
  $finalUrl = [string]$response.BaseResponse.ResponseUri.AbsoluteUri
}
catch {
  $finalUrl = ""
}

if ($status -eq 405 -or $status -eq 501) {
  Write-Host "HEAD not supported by endpoint. Falling back to GET..." -ForegroundColor Yellow
  $response = Invoke-Request -Method "Get" -RequestUrl $Url
  $status = [int]$response.StatusCode
  $contentType = (Get-HeaderValue -Response $response -HeaderName "Content-Type").ToLowerInvariant()
  $location = Get-HeaderValue -Response $response -HeaderName "Location"
  try {
    $finalUrl = [string]$response.BaseResponse.ResponseUri.AbsoluteUri
  }
  catch {
    $finalUrl = ""
  }
}

Write-Host "Status:       $status"
if (-not [string]::IsNullOrWhiteSpace($contentType)) {
  Write-Host "Content-Type: $contentType"
}
if (-not [string]::IsNullOrWhiteSpace($location)) {
  Write-Host "Location:     $location"
}
if (-not [string]::IsNullOrWhiteSpace($finalUrl)) {
  Write-Host "Final URL:    $finalUrl"
}

$isApkType = $contentType.Contains("application/vnd.android.package-archive") -or $contentType.Contains("application/octet-stream")
$redirectHints = "$location $finalUrl".ToLowerInvariant()
$looksLikeLoginRedirect = $redirectHints.Contains("login") -or $redirectHints.Contains("signin")

if ($ExpectedAccess -eq "public") {
  if ($status -ne 200) {
    Write-Error "Public endpoint gate FAILED: expected HTTP 200, got $status"
    exit 1
  }

  if (-not $isApkType) {
    Write-Error "Public endpoint gate FAILED: unexpected Content-Type '$contentType'"
    exit 1
  }

  if ($looksLikeLoginRedirect) {
    Write-Error "Public endpoint gate FAILED: endpoint redirects to login/signin"
    exit 1
  }

  Write-Host "Public endpoint gate PASS" -ForegroundColor Green
  exit 0
}

# restricted
if ($status -in @(401, 403)) {
  Write-Host "Restricted endpoint gate PASS" -ForegroundColor Green
  exit 0
}

if ($status -in @(301, 302, 307, 308) -and $looksLikeLoginRedirect) {
  Write-Host "Restricted endpoint gate PASS (login redirect)" -ForegroundColor Green
  exit 0
}

if ($status -eq 200 -and $isApkType) {
  Write-Error "Restricted endpoint gate FAILED: endpoint is publicly downloadable (HTTP 200 APK response)"
  exit 1
}

Write-Error "Restricted endpoint gate FAILED: unexpected status $status"
exit 1