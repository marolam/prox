Param(
  [string]$Repo = "marolam/prox",
  [string]$ProjectId = "prox-42bef",
  [string]$PublicApkUrl = "",
  [string]$ReferralDownloadUrl = "https://us-central1-prox-42bef.cloudfunctions.net/referralApkDownload",
  [string]$ReferralCode = "",
  [string]$EnvFilePath = "",
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
    [string]$RepoRoot,
    [string]$ExpectedLatestUrl
  )

  $searchRoots = @(
    (Join-Path $RepoRoot "web"),
    $RepoRoot
  ) | Where-Object { Test-Path $_ }

  $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  foreach ($root in $searchRoots) {
    $items = Get-ChildItem -Path $root -Recurse -File -Include *.html,*.json -ErrorAction SilentlyContinue |
      Where-Object {
        $_.FullName -notmatch "\\\\.backups\\\\" -and
        $_.FullName -notmatch "\\\\build\\\\" -and
        $_.FullName -notmatch "\\\\artifacts\\\\" -and
        $_.FullName -notmatch "\\\\functions\\\\lib\\\\"
      }
    foreach ($item in $items) {
      $files.Add($item)
    }
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
    if ($metadataRaw -notmatch [regex]::Escape($ExpectedLatestUrl)) {
      throw "Website APK link guard failed: web/tester-guide-release.json must use $ExpectedLatestUrl"
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
Write-Host "Referral endpoint:  $ReferralDownloadUrl"
Write-Host "Functions env file: $EnvFilePath"

Test-WebsiteApkLinks -RepoRoot $repoRoot -ExpectedLatestUrl $PublicApkUrl
Write-Host "Website APK link guard PASS" -ForegroundColor Green

$envDir = Split-Path -Parent $EnvFilePath
if (-not (Test-Path $envDir)) {
  New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

Set-DotEnvValue -Path $EnvFilePath -Key "PROX_PUBLIC_APK_URL" -Value $PublicApkUrl
Set-DotEnvValue -Path $EnvFilePath -Key "PROX_PUBLIC_APK_FALLBACK_URL" -Value $PublicApkUrl
Set-DotEnvValue -Path $EnvFilePath -Key "PROX_REFERRAL_DOWNLOAD_URL" -Value $ReferralDownloadUrl
Write-Host "Updated referral download env keys." -ForegroundColor Green

if (-not $SkipDeploy) {
  $sourceCheck = Test-FunctionsSourceComplete -FunctionsDir $functionsDir
  if (-not $sourceCheck.Complete) {
    Write-Warning "Functions source is incomplete in this workspace. Skipping deploy to avoid blocking release sync."
    Write-Warning "Missing modules: $($sourceCheck.Missing -join ', ')"
    $SkipDeploy = $true
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

if (-not $SkipGate) {
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
  Write-Host "Skipped referral QR gate by request." -ForegroundColor Yellow
}

Write-Host "Release download targets are synced." -ForegroundColor Green
exit 0