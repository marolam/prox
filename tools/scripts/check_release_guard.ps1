Param(
  [ValidateSet("tester", "staging", "prod")]
  [string]$ReleaseChannel = "tester",
  [string]$RepoPath = "",
  [string]$BranchName = ""
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

$repoRoot = Resolve-RepoRoot -InputPath $RepoPath
$branch = $BranchName.Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
  $branch = $env:GITHUB_REF_NAME
}
if ([string]::IsNullOrWhiteSpace($branch)) {
  $branch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
}

Write-Host "== Release guard ==" -ForegroundColor Cyan
Write-Host "Repo:    $repoRoot"
Write-Host "Channel: $ReleaseChannel"
Write-Host "Branch:  $branch"

$releaseFlagsPath = Join-Path $repoRoot "lib/release/release_flags.dart"
if (-not (Test-Path $releaseFlagsPath)) {
  throw "Missing release flags file: $releaseFlagsPath"
}

$flagsRaw = Get-Content -Path $releaseFlagsPath -Raw
if ($flagsRaw -match "businessModeEnabled\s*=\s*true") {
  throw "Unsafe release flags: businessModeEnabled appears hardcoded true."
}

if ($flagsRaw -notmatch 'PROX_ENABLE_BUSINESS_MODE"\s*,\s*defaultValue:\s*false') {
  throw "Unsafe release flags: PROX_ENABLE_BUSINESS_MODE defaultValue must be false."
}

if ($flagsRaw -notmatch 'if \(ReleaseChannel\.isProduction\) return false;') {
  throw "Unsafe release flags: production channel must force Business Mode off."
}

if ($ReleaseChannel -eq "prod") {
  if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Unable to determine branch name for prod guard."
  }

  if ($branch -ne "main") {
    throw "Prod builds are only allowed from main branch."
  }
}

Write-Host "Release guard PASS" -ForegroundColor Green
exit 0
