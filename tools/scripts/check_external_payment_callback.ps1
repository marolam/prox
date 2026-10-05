Param(
  [Parameter(Mandatory = $true)]
  [string]$Url,

  [Parameter(Mandatory = $true)]
  [string]$Uid,

  [Parameter(Mandatory = $true)]
  [string]$SessionId,

  [Parameter(Mandatory = $true)]
  [string]$CallbackSecret,

  [int]$TimeoutSec = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Url)) {
  Write-Error "Url is required."
  exit 1
}

try {
  $uri = [Uri]$Url
  if ($uri.Scheme -ne "https") {
    Write-Error "Callback URL must use https."
    exit 1
  }
} catch {
  Write-Error "Callback URL is invalid."
  exit 1
}

$payload = @{
  uid = $Uid
  sessionId = $SessionId
  source = "release_signoff_smoke"
  timestamp = [DateTimeOffset]::UtcNow.ToString("o")
} | ConvertTo-Json -Depth 4

$headers = @{
  "content-type" = "application/json"
  "x-prox-callback-secret" = $CallbackSecret
}

Write-Host "== External payment callback smoke ==" -ForegroundColor Cyan
Write-Host "URL: $Url"
Write-Host "UID: $Uid"
Write-Host "Session: $SessionId"

try {
  $response = Invoke-WebRequest -Uri $Url -Method Post -Body $payload -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
  $statusCode = [int]$response.StatusCode
  $body = [string]$response.Content
} catch {
  $statusCode = 0
  $body = ""
  $responseProp = $_.Exception.PSObject.Properties["Response"]
  if ($null -ne $responseProp -and $null -ne $responseProp.Value) {
    $resObj = $responseProp.Value
    try {
      $statusCode = [int]$resObj.StatusCode
    } catch {
      $statusCode = 0
    }
    try {
      $stream = $resObj.GetResponseStream()
      if ($null -ne $stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
      }
    } catch {
      $body = ""
    }
  }
}

Write-Host "Status: $statusCode"
if (-not [string]::IsNullOrWhiteSpace($body)) {
  $preview = $body
  if ($preview.Length -gt 500) {
    $preview = $preview.Substring(0, 500)
  }
  Write-Host "Body: $preview"
}

$parsed = $null
if (-not [string]::IsNullOrWhiteSpace($body)) {
  try {
    $parsed = $body | ConvertFrom-Json
  } catch {
    $parsed = $null
  }
}

if ($statusCode -eq 410) {
  Write-Host "External callback smoke PASS (expected legacy endpoint hard-disabled)." -ForegroundColor Green
  exit 0
}

if ($statusCode -eq 200 -and $null -ne $parsed) {
  Write-Host "External callback smoke PASS" -ForegroundColor Green
  exit 0
}

Write-Error "External callback smoke FAILED: unexpected response from callback endpoint."
exit 1
