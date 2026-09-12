Param(
  [string]$RepoPath = "",
  [string]$Repo = "marolam/prox-us",
  [switch]$SkipAnalyzer,
  [switch]$SkipRollbackVerification,
  [switch]$CheckLocalCanonicalApk,
  [switch]$CreateSnapshot,
  [switch]$StrictTrackedOnly,
  [string[]]$AnalyzePaths = @(
    "lib/home/home_shell.dart",
    "lib/home/home_root_shell.dart",
    "lib/home/business_shell.dart",
    "lib/screens/matches/match_inbox_screen.dart"
  )
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

function New-SourceSnapshot {
  Param([string]$Root)

  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $rollbackDir = Join-Path $Root "artifacts/rollback"
  if (-not (Test-Path $rollbackDir)) {
    New-Item -ItemType Directory -Force -Path $rollbackDir | Out-Null
  }

  $dest = Join-Path $rollbackDir "pre_update_source_$stamp.zip"
  $items = @(
    "lib",
    "test",
    "tools/scripts",
    "functions/src",
    "pubspec.yaml",
    "pubspec.lock",
    "firestore.rules",
    "firebase.json",
    ".vscode/tasks.json"
  )
  $existing = @($items | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ })
  if ($existing.Count -eq 0) {
    throw "No source paths found to snapshot."
  }

  $oldProgress = $ProgressPreference
  $ProgressPreference = "SilentlyContinue"
  try {
    Compress-Archive -Path $existing -DestinationPath $dest -Force
  } finally {
    $ProgressPreference = $oldProgress
  }

  return $dest
}

Assert-Tool "git"
if (-not $SkipAnalyzer) {
  Assert-Tool "flutter"
}

$repoRoot = Resolve-RepoRoot -InputPath $RepoPath
Set-Location $repoRoot

Write-Host "== Prox safe update gate ==" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot"

$unmerged = @(& git ls-files -u)
if ($unmerged.Count -gt 0) {
  Write-Host "Unmerged entries:" -ForegroundColor Red
  $unmerged | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
  throw "Git has unresolved merge/conflict entries. Resolve them before continuing."
}
Write-Host "Git conflict check PASS" -ForegroundColor Green

$status = @(& git status --short)
$conflictStatus = @($status | Where-Object { $_ -match '^(UU|DU|UD|AA|DD|AU|UA)\s' })
if ($conflictStatus.Count -gt 0) {
  $conflictStatus | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  throw "Git status still reports conflict-like paths."
}

if ($StrictTrackedOnly) {
  $dirtyTracked = @($status | Where-Object { $_ -notmatch '^\?\?' })
  if ($dirtyTracked.Count -gt 0) {
    Write-Host "Tracked changes are present:" -ForegroundColor Yellow
    $dirtyTracked | Select-Object -First 80 | ForEach-Object { Write-Host $_ }
    throw "StrictTrackedOnly is enabled. Commit/stash/review tracked changes before proceeding."
  }
} else {
  Write-Host "Tracked/untracked changes are allowed for update work; conflicts are not." -ForegroundColor DarkYellow
}

if ($CreateSnapshot) {
  $snapshot = New-SourceSnapshot -Root $repoRoot
  Write-Host "Snapshot created: $snapshot" -ForegroundColor Green
}

if (-not $SkipRollbackVerification) {
  $verifyScript = Join-Path $repoRoot "tools/scripts/verify_safe_rollback_release.ps1"
  if (-not (Test-Path $verifyScript)) {
    throw "Missing rollback verification script: $verifyScript"
  }

  if ($CheckLocalCanonicalApk) {
    & powershell -ExecutionPolicy Bypass -File $verifyScript -Repo $Repo -CheckLocalCanonicalApk
  } else {
    & powershell -ExecutionPolicy Bypass -File $verifyScript -Repo $Repo
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Safe rollback verification failed."
  }
}

if (-not $SkipAnalyzer) {
  $existingAnalyzePaths = @($AnalyzePaths | Where-Object { Test-Path (Join-Path $repoRoot $_) })
  if ($existingAnalyzePaths.Count -eq 0) {
    throw "No analyzer paths exist."
  }

  Write-Host "Running focused Flutter analyzer..." -ForegroundColor Cyan
  & flutter analyze @existingAnalyzePaths
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter analyzer failed."
  }
  Write-Host "Focused analyzer PASS" -ForegroundColor Green
}

Write-Host "Safe update gate PASS" -ForegroundColor Green
exit 0
