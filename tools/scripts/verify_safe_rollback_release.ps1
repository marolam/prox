Param(
  [string]$RepoPath = "",
  [string]$Repo = "marolam/prox-us",
  [string]$Tag = "v1.0",
  [string]$ExpectedAsset = "app-release.apk",
  [string]$ExpectedSha256 = "ac7c2a184cbdf73bca9681a042efcbf92d0a414a7ca8948bb36df5b37d10c023",
  [int64]$ExpectedSize = 82739811,
  [switch]$CheckLocalCanonicalApk
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  Param([string]$InputPath)

  if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
    return (Resolve-Path $InputPath -ErrorAction Stop).Path
  }

  if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    return (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
  }

  return (Get-Location).Path
}

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' was not found in PATH."
  }
}

function Get-Sha256Text {
  Param([string]$Value)
  return (($Value.Trim() -replace '^sha256:', '')).ToLowerInvariant()
}

Assert-Tool "gh"

$repoRoot = Resolve-RepoRoot -InputPath $RepoPath
$expectedHash = Get-Sha256Text -Value $ExpectedSha256

Write-Host "== Safe rollback release verification ==" -ForegroundColor Cyan
Write-Host "Repo root: $repoRoot"
Write-Host "GitHub:   $Repo"
Write-Host "Tag:      $Tag"
Write-Host "Asset:    $ExpectedAsset"
Write-Host "Expected: sha256:$expectedHash"

$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  # Use the documented Contents-read REST endpoint directly. Keep failure
  # details in memory; print only the HTTP status, never credentials or bodies.
  $endpoint = "repos/$Repo/releases/tags/$([Uri]::EscapeDataString($Tag))"
  $releaseJson = (& gh api $endpoint 2>&1 | Out-String).Trim()
  $readExitCode = $LASTEXITCODE
} finally { $ErrorActionPreference = $previousErrorPreference }
if ($readExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($releaseJson)) {
  $httpStatus = if ($releaseJson -match 'HTTP ([0-9]{3})') { $Matches[1] } else { 'unknown' }
  $detail = switch ($httpStatus) {
    '401' { 'GitHub rejected the token. Replace the secret with the full, unexpired generated token value.' }
    '403' { 'GitHub denied release access. Check token approval and Contents: read permission.' }
    '404' { "GitHub could not expose the private release. Check that the token selects $Repo and has Contents: read permission." }
    default { 'Check GitHub availability and the configured rollback credential.' }
  }
  throw "Rollback release read failed (HTTP $httpStatus) for $Repo@$Tag. $detail"
}

$release = $releaseJson | ConvertFrom-Json
$asset = @($release.assets | Where-Object { $_.name -eq $ExpectedAsset } | Select-Object -First 1)
if (-not $asset) {
  throw "Release $Tag does not contain expected asset '$ExpectedAsset'."
}

$actualDigest = Get-Sha256Text -Value ([string]$asset.digest)
if ($actualDigest -ne $expectedHash) {
  throw "Rollback asset digest mismatch. Expected sha256:$expectedHash but GitHub has sha256:$actualDigest."
}

if ([int64]$asset.size -ne $ExpectedSize) {
  throw "Rollback asset size mismatch. Expected $ExpectedSize but GitHub has $($asset.size)."
}

Write-Host "GitHub rollback release PASS" -ForegroundColor Green
Write-Host "Rollback tag integrity verified. Latest release may differ from $Tag." -ForegroundColor DarkGray

if ($CheckLocalCanonicalApk) {
  $localApk = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-release.apk"
  if (-not (Test-Path $localApk)) {
    throw "Local canonical APK is missing: $localApk"
  }

  $localHash = (Get-FileHash -Algorithm SHA256 -Path $localApk).Hash.ToLowerInvariant()
  if ($localHash -ne $expectedHash) {
    throw "Local canonical APK hash mismatch. Expected sha256:$expectedHash but found sha256:$localHash at $localApk."
  }

  $localSize = (Get-Item $localApk).Length
  if ($localSize -ne $ExpectedSize) {
    throw "Local canonical APK size mismatch. Expected $ExpectedSize but found $localSize."
  }

  Write-Host "Local canonical APK PASS" -ForegroundColor Green
}

Write-Host "Safe rollback verification PASS" -ForegroundColor Green
exit 0
