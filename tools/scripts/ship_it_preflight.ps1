Param(
  [string]$RepoPath = "",
  [switch]$SkipSafetyGate,
  [switch]$SkipAnalyze,
  [switch]$SkipTests,
  [switch]$QuickTestsOnly,
  [switch]$SkipSnapshot,
  [switch]$CheckLocalRollbackApk,
  [switch]$SkipRollbackCanonicalCheck
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
    throw "Required tool '$Name' not found in PATH."
  }
}

$repoRoot = Resolve-RepoRoot -InputPath $RepoPath
Set-Location $repoRoot

Write-Host "== Ship It preflight checks ==" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot"

Assert-Tool "powershell"
if (-not $SkipAnalyze -or -not $SkipTests) {
  Assert-Tool "flutter"
}

if (-not $SkipSafetyGate) {
  $safeGateScript = Join-Path $repoRoot "tools/scripts/safe_update_gate.ps1"
  if (-not (Test-Path $safeGateScript)) {
    throw "Missing safe update gate script: $safeGateScript"
  }

  Write-Host "Running safety gate..." -ForegroundColor Cyan
  $safeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $safeGateScript
  )
  if (-not $SkipSnapshot) {
    $safeArgs += "-CreateSnapshot"
  }
  # The current build output normally changes on every ship. Only compare it
  # with the fixed rollback APK during an explicit rollback-recovery check.
  # Remote v1.0 digest verification still runs on every normal preflight.
  if ($CheckLocalRollbackApk -and -not $SkipRollbackCanonicalCheck) {
    $safeArgs += "-CheckLocalCanonicalApk"
  }

  & powershell @safeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Safety gate failed with exit code $LASTEXITCODE"
  }
}

if (-not $SkipAnalyze) {
  Write-Host "Running flutter analyze..." -ForegroundColor Cyan
  & flutter analyze
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter analyze failed with exit code $LASTEXITCODE"
  }
}

if (-not $SkipTests) {
  if ($QuickTestsOnly) {
    $criticalTests = @(
      "test/business_lead_inbox_policy_test.dart",
      "test/pro_apex_policy_test.dart",
      "test/pro_mode_foundation_test.dart",
      "test/widgets/chat_gate_banner_test.dart"
    )
    Write-Host "Running critical Flutter test suite..." -ForegroundColor Cyan
    & flutter test @criticalTests
    if ($LASTEXITCODE -ne 0) {
      throw "Critical Flutter tests failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Host "Running full flutter test suite..." -ForegroundColor Cyan
    & flutter test
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter test suite failed with exit code $LASTEXITCODE"
    }
  }
}

Write-Host "Ship It preflight PASS" -ForegroundColor Green
exit 0
