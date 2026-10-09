Param(
  [string]$Repo = "marolam/prox",
  [string]$ProjectId = "prox-42bef",
  [string]$PublicApkUrl = "",
  [string]$IosUpdateUrl = "https://www.prox-us.com/tester-portal.html",
  [string]$ReferralDownloadUrl = "https://us-central1-prox-42bef.cloudfunctions.net/referralApkDownload",
  [string]$ReferralCode = "",
  [string]$EnvFilePath = "",
  [ValidateSet("android", "ios", "both")]
  [string]$Platform = "both",
  [switch]$SkipDeploy,
  [switch]$SkipGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH."
  }
}

function Set-DotEnvValue {
  Param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )

  $lines = New-Object System.Collections.Generic.List[string]
  if (Test-Path $Path) {
    foreach ($line in Get-Content -Path $Path) {
      $lines.Add($line)
    }
  }

  $updated = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*$([regex]::Escape($Key))=") {
      $lines[$i] = "$Key=$Value"
      $updated = $true
    }
  }

  if (-not $updated) {
    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
      $lines.Add("")
    }
    $lines.Add("$Key=$Value")
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($Path, [string[]]$lines, $utf8NoBom)
}

function Test-FunctionsSourceComplete {
  Param([string]$FunctionsDir)

  $srcDir = Join-Path $FunctionsDir "src"
  $entry = Join-Path $srcDir "index.ts"
  if (-not (Test-Path $entry)) {
    return [PSCustomObject]@{ Complete = $false; Missing = @("src/index.ts") }
  }

  $missing = New-Object System.Collections.Generic.List[string]
  $lines = Get-Content -Path $entry
  foreach ($line in $lines) {
    if ($line -match 'from\s+"\./([^"]+)"') {
      $moduleRel = $Matches[1]
      $moduleTs = Join-Path $srcDir ($moduleRel + ".ts")
      $moduleIndexTs = Join-Path (Join-Path $srcDir $moduleRel) "index.ts"
      if (-not (Test-Path $moduleTs) -and -not (Test-Path $moduleIndexTs)) {
        $missing.Add("src/$moduleRel")
      }
    }
  }

  return [PSCustomObject]@{ Complete = ($missing.Count -eq 0); Missing = @($missing) }
}

function Test-WebsiteApkLinks {
  Param(
    [string]$RepoRoot
  )

  $files = @(Get-ChildItem -LiteralPath $RepoRoot -File |
    Where-Object { $_.Extension -in @(".html", ".json") })
  $webRoot = Join-Path $RepoRoot "web"
  if (Test-Path $webRoot) {
    $files += @(Get-ChildItem -LiteralPath $webRoot -Recurse -File |
      Where-Object { $_.Extension -in @(".html", ".json") })
  }

  $failures = New-Object System.Collections.Generic.List[string]
  $stalePatterns = @(
    "https://github.com/marolam/prox-us/releases/latest/download/app-release.apk",
    "https://github.com/marolam/prox-us/releases/download/"
  )

  foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    foreach ($pattern in $stalePatterns) {
      if ($content.Contains($pattern)) {
        $rel = $file.FullName.Replace($RepoRoot + "\\", "")
        $failures.Add("$rel contains stale APK URL pattern: $pattern")
      }
    }
  }

  if ($failures.Count -gt 0) {
    throw "Website APK link guard failed:`n - $($failures -join "`n - ")"
  }

  $metadataFile = Join-Path $RepoRoot "web/tester-guide-release.json"
  if (Test-Path $metadataFile) {
    $metadataRaw = Get-Content -Path $metadataFile -Raw
    if ($metadataRaw -match '"publicApkUrl"\s*:\s*""') {
      throw "Website APK link guard failed: web/tester-guide-release.json has an empty publicApkUrl."
    }
    $metadata = $metadataRaw | ConvertFrom-Json
    $stableUrl = "https://github.com/$Repo/releases/latest/download/app-release.apk"
    if ($metadata.publicApkUrl -cne $stableUrl) {
      throw "Website APK link guard failed: web/tester-guide-release.json must use $stableUrl"
    }
  }
}

$repoRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction Stop).Path
} else {
  (Get-Location).Path
}
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($PublicApkUrl)) {
  $PublicApkUrl = "https://github.com/$Repo/releases/latest/download/app-release.apk"
}

if ([string]::IsNullOrWhiteSpace($EnvFilePath)) {
  $EnvFilePath = Join-Path $repoRoot "functions/.env.$ProjectId"
}

$functionsDir = Join-Path $repoRoot "functions"
if (-not (Test-Path $functionsDir)) {
  throw "Missing functions directory: $functionsDir"
}

Write-Host "== Sync release download targets ==" -ForegroundColor Cyan
Write-Host "Repo:               $Repo"
Write-Host "Project:            $ProjectId"
Write-Host "Public APK URL:     $PublicApkUrl"
Write-Host "iOS update URL:     $IosUpdateUrl"
Write-Host "Referral endpoint:  $ReferralDownloadUrl"
Write-Host "Functions env file: $EnvFilePath"

if ($Platform -in @("android", "both")) {
  $apkUri = $null
  if (-not [Uri]::TryCreate($PublicApkUrl, [UriKind]::Absolute, [ref]$apkUri) -or
      $apkUri.Scheme -ne "https" -or $apkUri.Host -ne "github.com" -or
      $apkUri.UserInfo -or $apkUri.Query -or $apkUri.Fragment -or
      $apkUri.AbsolutePath -notlike "/$Repo/releases/*/app-release.apk") {
    throw "PublicApkUrl must be the canonical HTTPS GitHub release APK in $Repo."
  }
}
if ($Platform -in @("ios", "both")) {
  $iosUri = $null
  if (-not [Uri]::TryCreate($IosUpdateUrl, [UriKind]::Absolute, [ref]$iosUri) -or
      $iosUri.Scheme -ne "https" -or $iosUri.UserInfo -or
      [Uri]::UnescapeDataString($iosUri.AbsolutePath) -match '[<>]' -or
      $iosUri.Host -notin @("apps.apple.com", "testflight.apple.com", "prox-us.com", "www.prox-us.com")) {
    throw "IosUpdateUrl must be an allowlisted HTTPS iOS install destination."
  }
}
Test-WebsiteApkLinks -RepoRoot $repoRoot
Write-Host "Website APK link guard PASS" -ForegroundColor Green

$envDir = Split-Path -Parent $EnvFilePath
if (-not (Test-Path $envDir)) {
  New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

if ($Platform -in @("android", "both")) {
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_REFERRAL_ANDROID_URL" -Value $PublicApkUrl
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_PUBLIC_APK_URL" -Value $PublicApkUrl
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_PUBLIC_APK_FALLBACK_URL" -Value $PublicApkUrl
}
if ($Platform -in @("ios", "both")) {
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_REFERRAL_IOS_URL" -Value $IosUpdateUrl
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_IOS_UPDATE_URL" -Value $IosUpdateUrl
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_IOS_UPDATE_FALLBACK_URL" -Value $IosUpdateUrl
  Set-DotEnvValue -Path $EnvFilePath -Key "PROX_IOS_FALLBACK_URL" -Value $IosUpdateUrl
}
Set-DotEnvValue -Path $EnvFilePath -Key "PROX_REFERRAL_DOWNLOAD_URL" -Value $ReferralDownloadUrl
Write-Host "Updated referral download env keys." -ForegroundColor Green

if (-not $SkipDeploy) {
  $sourceCheck = Test-FunctionsSourceComplete -FunctionsDir $functionsDir
  if (-not $sourceCheck.Complete) {
    throw "Functions source is incomplete. Download target deployment stopped. Missing modules: $($sourceCheck.Missing -join ', ')"
  }
}

if (-not $SkipDeploy) {
  Assert-Tool "npm"
  Assert-Tool "firebase"

  Write-Host "Building Functions TypeScript..." -ForegroundColor Cyan
  & npm --prefix $functionsDir run build
  if ($LASTEXITCODE -ne 0) {
    throw "Functions build failed with exit code $LASTEXITCODE"
  }

  Write-Host "Deploying referral download functions..." -ForegroundColor Cyan
  & firebase deploy --project $ProjectId --only "functions:referralApkDownload,functions:createReferralSingleUseToken,functions:finalizeReferralSingleUseToken"
  if ($LASTEXITCODE -ne 0) {
    throw "Firebase deploy failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host "Skipped Firebase deploy by request." -ForegroundColor Yellow
}

if (-not $SkipGate -and $Platform -in @("android", "both")) {
  $gateScript = Join-Path $repoRoot "tools/scripts/check_referral_qr_release_link.ps1"
  if (-not (Test-Path $gateScript)) {
    throw "Missing referral QR gate script: $gateScript"
  }

  $gateArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $gateScript,
    "-ReferralDownloadUrl", $ReferralDownloadUrl,
    "-PublicApkUrl", $PublicApkUrl
  )
  if ($PublicApkUrl -ne "https://github.com/$Repo/releases/latest/download/app-release.apk") {
    $gateArgs += "-AllowNonLatestGithubPath"
  }
  if (-not [string]::IsNullOrWhiteSpace($ReferralCode)) {
    $gateArgs += "-Code"
    $gateArgs += $ReferralCode
  }

  Write-Host "Running referral QR release gate..." -ForegroundColor Cyan
  & powershell @gateArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Referral QR release gate failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host "Android QR gate skipped (SkipGate or iOS-only target sync)." -ForegroundColor Yellow
}

if ($SkipDeploy) {
  Write-Host "Local download targets prepared only; deployed referral routing is unchanged." -ForegroundColor Yellow
} else {
  Write-Host "Release download targets deployed for $Platform." -ForegroundColor Green
}
exit 0