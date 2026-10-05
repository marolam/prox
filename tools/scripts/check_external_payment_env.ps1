Param(
  [switch]$RequireSquareSecrets,
  [switch]$RequireStableWebhookDomain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-Env {
  Param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ""
  }
  return $value.Trim()
}

function Test-HttpsUrl {
  Param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  try {
    $u = [Uri]$Value
    return $u.Scheme -eq "https"
  } catch {
    return $false
  }
}

function Test-StableWebhookHost {
  Param([string]$Url)
  if (-not (Test-HttpsUrl -Value $Url)) { return $false }
  $uri = [Uri]$Url
  $hostName = $uri.Host.ToLowerInvariant()
  if ($hostName -eq "localhost" -or $hostName -eq "127.0.0.1") { return $false }
  if ($hostName.EndsWith(".ngrok.io") -or $hostName.EndsWith(".ngrok-free.app")) { return $false }
  if ($hostName.EndsWith(".trycloudflare.com")) { return $false }
  if ($hostName.EndsWith(".local")) { return $false }
  return $true
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$requiredHttps = @(
  "PROX_CHECKOUT_SUCCESS_URL"
)
$recommendedHttps = @(
  "PROX_CHECKOUT_CANCEL_URL",
  "EXTERNAL_PAYMENT_CHECKOUT_BASE_URL"
)

foreach ($key in $requiredHttps) {
  $value = Read-Env -Name $key
  if (-not (Test-HttpsUrl -Value $value)) {
    $errors.Add("$key must be a valid https URL.")
  }
}

foreach ($key in $recommendedHttps) {
  $value = Read-Env -Name $key
  if ([string]::IsNullOrWhiteSpace($value)) {
    $warnings.Add("$key is not set (recommended).")
    continue
  }
  if (-not (Test-HttpsUrl -Value $value)) {
    $warnings.Add("$key is set but is not a valid https URL.")
  }
}

if ($RequireSquareSecrets) {
  foreach ($key in @("SQUARE_ACCESS_TOKEN", "SQUARE_LOCATION_ID", "SQUARE_WEBHOOK_SIGNATURE_KEY")) {
    if ([string]::IsNullOrWhiteSpace((Read-Env -Name $key))) {
      $errors.Add("$key is required when -RequireSquareSecrets is enabled.")
    }
  }
}

if ($RequireStableWebhookDomain) {
  $webhookUrl = Read-Env -Name "SQUARE_WEBHOOK_ENDPOINT_URL"
  if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
    $errors.Add("SQUARE_WEBHOOK_ENDPOINT_URL is required when -RequireStableWebhookDomain is enabled.")
  } elseif (-not (Test-StableWebhookHost -Url $webhookUrl)) {
    $errors.Add("SQUARE_WEBHOOK_ENDPOINT_URL must be a stable public https endpoint (not localhost/ngrok/local tunnel).")
  }
}

if ([string]::IsNullOrWhiteSpace((Read-Env -Name "PROX_PAYMENT_CALLBACK_SECRET"))) {
  $warnings.Add("PROX_PAYMENT_CALLBACK_SECRET is not set.")
}

Write-Host "== External payment env gate =="
Write-Host "Require square secrets: $RequireSquareSecrets"
Write-Host "Require stable webhook: $RequireStableWebhookDomain"

if ($warnings.Count -gt 0) {
  foreach ($w in $warnings) {
    Write-Warning $w
  }
}

if ($errors.Count -gt 0) {
  foreach ($e in $errors) {
    Write-Error $e
  }
  exit 1
}

Write-Host "External payment env gate PASS" -ForegroundColor Green
exit 0
