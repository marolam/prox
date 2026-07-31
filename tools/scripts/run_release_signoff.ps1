Param(
  [string]$RepoPath = "",
  [switch]$SkipBuild,
  [switch]$SkipExternalPaymentEnvGate,
  [switch]$RequireSquareSecrets,
  [switch]$RequireStableWebhookDomain,
  [switch]$SkipExternalCallbackSmoke,
  [string]$ExternalCallbackUrl = "",
  [string]$ExternalCallbackUid = "",
  [string]$ExternalCallbackSessionId = "",
  [string]$ExternalCallbackSecret = "",
  [string]$PublicApkUrl = "",
  [string]$RestrictedApkUrl = "",
  [string]$PreviousApkUrl = "",
  [string]$SmokeResultsPath = "",
  [ValidateSet("PASS", "FAIL", "PENDING")]
  [string]$FatalLogGate = "PENDING",
  [ValidateSet("PASS", "FAIL", "PENDING", "NOT-RUN")]
  [string]$PermissionDeniedGate = "PENDING",
  [string]$Version = "",
  [string]$BuildNumber = "",
  [string]$CommitSha = "",
  [string]$TesterGuideUrl = "https://prox-us.com/tester-guide",
  [string]$TesterSupportUrl = "https://prox-us.com/tester-support",
  [string[]]$BlockerTests = @("T2", "T7", "T8", "T10", "T11")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  Param([string]$InputPath)

  $repoPathInput = $InputPath
  if ([string]::IsNullOrWhiteSpace($repoPathInput)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
      $repoPathInput = Join-Path $PSScriptRoot "../.."
    }
    else {
      $repoPathInput = (Get-Location).Path
    }
  }

  return (Resolve-Path $repoPathInput -ErrorAction Stop).Path
}

function Resolve-ApkPath {
  Param([string]$RepoRoot)

  $apkCandidates = @(
    (Join-Path $RepoRoot "build/app/outputs/flutter-apk/app-release.apk"),
    (Join-Path $RepoRoot "android/app/build/outputs/flutter-apk/app-release.apk")
  )

  $existing = @($apkCandidates | Where-Object { Test-Path $_ })
  if ($existing.Count -eq 0) {
    throw "Release APK not found. Checked: $($apkCandidates -join ', ')"
  }

  return ($existing |
    ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1).FullName
}

function Get-PubspecVersionInfo {
  Param([string]$RepoRoot)

  $pubspecPath = Join-Path $RepoRoot "pubspec.yaml"
  if (-not (Test-Path $pubspecPath)) {
    return [PSCustomObject]@{ SemVer = ""; Build = "" }
  }

  $versionLine = Get-Content -Path $pubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($versionLine)) {
    return [PSCustomObject]@{ SemVer = ""; Build = "" }
  }

  $v = ($versionLine -replace "^version:\s*", "").Trim()
  if ($v -match "^(?<sem>[^+]+)\+(?<build>.+)$") {
    return [PSCustomObject]@{ SemVer = $Matches["sem"]; Build = $Matches["build"] }
  }

  return [PSCustomObject]@{ SemVer = $v; Build = "" }
}

function Get-SmokeResults {
  Param([string]$Path)

  $results = @{}
  for ($i = 1; $i -le 11; $i++) {
    $results["T$i"] = "PENDING"
  }

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $results
  }

  if (-not (Test-Path $Path)) {
    Write-Warning "Smoke results file not found: $Path"
    return $results
  }

  $lines = Get-Content -Path $Path
  foreach ($line in $lines) {
    if ($line -match "^(T(?<id>\d+))\s+(?<status>PASS|FAIL)(:.*)?$") {
      $testId = "T$($Matches['id'])"
      if ($results.ContainsKey($testId)) {
        $results[$testId] = $Matches["status"]
      }
    }
  }

  return $results
}

function Invoke-EndpointGate {
  Param(
    [string]$RepoRoot,
    [string]$Url,
    [string]$ExpectedAccess
  )

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return "NOT-RUN"
  }

  $scriptPath = Join-Path $RepoRoot "tools/scripts/check_apk_download_endpoint.ps1"
  if (-not (Test-Path $scriptPath)) {
    throw "Missing endpoint gate script: $scriptPath"
  }

  $gateOutput = & powershell -ExecutionPolicy Bypass -File $scriptPath -Url $Url -ExpectedAccess $ExpectedAccess 2>&1
  foreach ($line in $gateOutput) {
    Write-Host $line
  }
  if ($LASTEXITCODE -eq 0) {
    return "PASS"
  }
  return "FAIL"
}

function Invoke-ExternalPaymentEnvGate {
  Param(
    [string]$RepoRoot,
    [switch]$Skip,
    [switch]$RequireSecrets,
    [switch]$RequireStableDomain
  )

  if ($Skip) {
    return "NOT-RUN"
  }

  $scriptPath = Join-Path $RepoRoot "tools/scripts/check_external_payment_env.ps1"
  if (-not (Test-Path $scriptPath)) {
    throw "Missing external payment env gate script: $scriptPath"
  }

  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
  )
  if ($RequireSecrets) {
    $args += "-RequireSquareSecrets"
  }
  if ($RequireStableDomain) {
    $args += "-RequireStableWebhookDomain"
  }

  $gateOutput = & powershell @args 2>&1
  foreach ($line in $gateOutput) {
    Write-Host $line
  }
  if ($LASTEXITCODE -eq 0) {
    return "PASS"
  }
  return "FAIL"
}

function Invoke-ExternalCallbackSmokeGate {
  Param(
    [string]$RepoRoot,
    [switch]$Skip,
    [string]$Url,
    [string]$Uid,
    [string]$SessionId,
    [string]$Secret
  )

  if ($Skip) {
    return "NOT-RUN"
  }

  if ([string]::IsNullOrWhiteSpace($Url) -or
      [string]::IsNullOrWhiteSpace($Uid) -or
      [string]::IsNullOrWhiteSpace($SessionId) -or
      [string]::IsNullOrWhiteSpace($Secret)) {
    Write-Warning "Skipping external callback smoke gate: Url/Uid/SessionId/Secret not fully provided."
    return "NOT-RUN"
  }

  $scriptPath = Join-Path $RepoRoot "tools/scripts/check_external_payment_callback.ps1"
  if (-not (Test-Path $scriptPath)) {
    throw "Missing external callback smoke script: $scriptPath"
  }

  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-Url", $Url,
    "-Uid", $Uid,
    "-SessionId", $SessionId,
    "-CallbackSecret", $Secret
  )

  $gateOutput = & powershell @args 2>&1
  foreach ($line in $gateOutput) {
    Write-Host $line
  }
  if ($LASTEXITCODE -eq 0) {
    return "PASS"
  }
  return "FAIL"
}

$repoRoot = Resolve-RepoRoot -InputPath $RepoPath
Set-Location $repoRoot

$envLoader = Join-Path $repoRoot "tools/scripts/import_env_file.ps1"
if (Test-Path $envLoader) {
  . $envLoader -EnvFilePath (Join-Path $repoRoot "tools/.env/payment.local.env")
}

Write-Host "== Prox release signoff runner ==" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot"

if (-not $SkipBuild) {
  $buildScript = Join-Path $repoRoot "tools/scripts/build_release_apk.ps1"
  if (-not (Test-Path $buildScript)) {
    throw "Missing build script: $buildScript"
  }

  Write-Host "Running release build..." -ForegroundColor Cyan
  & powershell -ExecutionPolicy Bypass -File $buildScript -TesterGuideUrl $TesterGuideUrl -TesterSupportUrl $TesterSupportUrl
  if ($LASTEXITCODE -ne 0) {
    throw "Release build step failed with exit code $LASTEXITCODE"
  }
}

$apkPath = Resolve-ApkPath -RepoRoot $repoRoot
$apkItem = Get-Item $apkPath
$hash = (Get-FileHash -Algorithm SHA256 -Path $apkPath).Hash.ToLowerInvariant()
$apkSizeMb = [math]::Round(($apkItem.Length / 1MB), 2)

$pubspecVersion = Get-PubspecVersionInfo -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = $pubspecVersion.SemVer
}
if ([string]::IsNullOrWhiteSpace($BuildNumber)) {
  $BuildNumber = $pubspecVersion.Build
}
if ([string]::IsNullOrWhiteSpace($CommitSha)) {
  $shaOut = (& git rev-parse --short HEAD 2>$null | Out-String).Trim()
  if (-not [string]::IsNullOrWhiteSpace($shaOut)) {
    $CommitSha = $shaOut
  }
}

Write-Host "Running endpoint gate checks..." -ForegroundColor Cyan
$publicGate = Invoke-EndpointGate -RepoRoot $repoRoot -Url $PublicApkUrl -ExpectedAccess "public"
$restrictedGate = Invoke-EndpointGate -RepoRoot $repoRoot -Url $RestrictedApkUrl -ExpectedAccess "restricted"

Write-Host "Running external payment env gate..." -ForegroundColor Cyan
$externalPaymentEnvGate = Invoke-ExternalPaymentEnvGate `
  -RepoRoot $repoRoot `
  -Skip:$SkipExternalPaymentEnvGate `
  -RequireSecrets:$RequireSquareSecrets `
  -RequireStableDomain:$RequireStableWebhookDomain

Write-Host "Running external callback smoke gate..." -ForegroundColor Cyan
$externalCallbackSmokeGate = Invoke-ExternalCallbackSmokeGate `
  -RepoRoot $repoRoot `
  -Skip:$SkipExternalCallbackSmoke `
  -Url $ExternalCallbackUrl `
  -Uid $ExternalCallbackUid `
  -SessionId $ExternalCallbackSessionId `
  -Secret $ExternalCallbackSecret

$smoke = Get-SmokeResults -Path $SmokeResultsPath

$blockerFailures = New-Object System.Collections.Generic.List[string]
foreach ($test in $BlockerTests) {
  $state = $smoke[$test]
  if ($state -ne "PASS") {
    $blockerFailures.Add("$test=$state")
  }
}

$endpointPass = ($publicGate -eq "PASS") -and ($restrictedGate -eq "PASS")
$fatalPass = $FatalLogGate -eq "PASS"
$permissionPass = $PermissionDeniedGate -eq "PASS"
$externalPaymentEnvPass = ($externalPaymentEnvGate -eq "PASS") -or ($externalPaymentEnvGate -eq "NOT-RUN")
$externalCallbackSmokePass = ($externalCallbackSmokeGate -eq "PASS") -or ($externalCallbackSmokeGate -eq "NOT-RUN")
$go = ($blockerFailures.Count -eq 0) -and $endpointPass -and $fatalPass -and $permissionPass -and $externalPaymentEnvPass -and $externalCallbackSmokePass

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = Join-Path $repoRoot "logs/release_reports"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$reportPath = Join-Path $reportDir "release_one_page_$timestamp.md"

$report = @(
  "# Release One-Page Report",
  "",
  "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "Release version: $Version",
  "Build number: $BuildNumber",
  "Commit SHA: $CommitSha",
  "Release owner:",
  "",
  "## Artifact",
  "",
  "- APK path: $apkPath",
  "- APK SHA-256: $hash",
  "- APK size (MB): $apkSizeMb",
  "- Previous APK fallback URL: $PreviousApkUrl",
  "- Current public APK URL: $PublicApkUrl",
  "- Current restricted APK URL: $RestrictedApkUrl",
  "- Tester guide URL: $TesterGuideUrl",
  "- Tester support URL: $TesterSupportUrl",
  "",
  "## Endpoint checks",
  "",
  "- Public endpoint check: $publicGate",
  "- Restricted endpoint check: $restrictedGate",
  "- Content-Type validated: $(if ($publicGate -eq 'PASS') { 'PASS' } else { 'FAIL/PENDING' })",
  "- No login redirect on public endpoint: $(if ($publicGate -eq 'PASS') { 'PASS' } else { 'FAIL/PENDING' })",
  "- External payment env gate: $externalPaymentEnvGate",
  "- External callback smoke gate: $externalCallbackSmokeGate",
  "",
  "## Test gates",
  "",
  "- T1: $($smoke['T1'])",
  "- T2: $($smoke['T2'])",
  "- T3: $($smoke['T3'])",
  "- T4: $($smoke['T4'])",
  "- T5: $($smoke['T5'])",
  "- T6: $($smoke['T6'])",
  "- T7: $($smoke['T7'])",
  "- T8: $($smoke['T8'])",
  "- T9: $($smoke['T9'])",
  "- T10: $($smoke['T10'])",
  "- T11: $($smoke['T11'])",
  "",
  "## Blocker policy",
  "",
  "- Required PASS tests: $($BlockerTests -join ', ')",
  "- Label freeze: YES",
  "- Device matrix baseline: API 29, API 31, API 34/35",
  "",
  "## Crash/log gate",
  "",
  "- Fatal exception scan: $FatalLogGate",
  "- Permission denied regressions: $PermissionDeniedGate",
  "- Notes:",
  "",
  "## Go/No-Go",
  "",
  "- Verdict: $(if ($go) { 'GO' } else { 'NO-GO' })",
  "- Blocker failures: $(if ($blockerFailures.Count -eq 0) { 'none' } else { $blockerFailures -join '; ' })",
  "- If NO-GO, immediate action: hold release and fix blockers",
  "- Rollback action: point download to previous APK link"
)

$report | Out-File -FilePath $reportPath -Encoding utf8

Write-Host "Report generated: $reportPath" -ForegroundColor Green
if ($go) {
  Write-Host "Final verdict: GO" -ForegroundColor Green
  exit 0
}

Write-Host "Final verdict: NO-GO" -ForegroundColor Yellow
exit 2
