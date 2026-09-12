Param(
  [string]$RepoPath = "",
  [string]$Repo = "",
  [string]$Tag = "",
  [string]$Title = "",
  [string]$Notes = "",
  [string]$ApkPath = "",
  [string]$ApkAssetName = "app-release.apk",
  [string]$IpaPath = "",
  [string]$IpaAssetName = "app-release.ipa",
  [string]$TargetCommit = "",
  [string[]]$AdditionalAssets = @(),
  [switch]$RequireExistingTag,
  [switch]$ValidateOnly,
  [switch]$BuildBeforePublish,
  [switch]$Prerelease,
  [switch]$Draft,
  [switch]$SetLatest = $true,
  [switch]$AllowOverwriteSafeRollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  Param([string]$InputPath)

  $repoPathInput = $InputPath
  if ([string]::IsNullOrWhiteSpace($repoPathInput)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
      $repoPathInput = Join-Path $PSScriptRoot "../.."
    } else {
      $repoPathInput = (Get-Location).Path
    }
  }

  return (Resolve-Path $repoPathInput -ErrorAction Stop).Path
}

function Assert-Tool {
  Param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH."
  }
}

function Resolve-GhExe {
  $cmd = Get-Command gh -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    return $cmd.Source
  }

  $candidates = @(
    "$env:ProgramFiles\GitHub CLI\gh.exe",
    "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
  )

  foreach ($path in $candidates) {
    if (Test-Path $path) {
      return $path
    }
  }

  throw "GitHub CLI not found. Install gh or add it to PATH."
}

function Get-PubspecVersion {
  Param([string]$Root)

  $pubspecPath = Join-Path $Root "pubspec.yaml"
  if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
  }

  $versionLine = Get-Content -Path $pubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($versionLine)) {
    throw "Could not parse version from pubspec.yaml"
  }

  return ($versionLine -replace "^version:\s*", "").Trim()
}

function Resolve-GitHubRepoSlug {
  Param([string]$Root)

  $remoteUrl = (& git -C $Root config --get remote.origin.url 2>$null | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    throw "Could not read git remote origin url. Pass -Repo owner/name."
  }

  if ($remoteUrl -match "github\.com[:/](?<owner>[^/]+)/(?<name>[^/.]+)(\.git)?$") {
    return "$($Matches['owner'])/$($Matches['name'])"
  }

  throw "Could not parse GitHub repo slug from remote origin url: $remoteUrl"
}

function Resolve-ApkPath {
  Param([string]$Root, [string]$HintPath)

  if (-not [string]::IsNullOrWhiteSpace($HintPath)) {
    $full = Resolve-Path $HintPath -ErrorAction Stop
    return (Get-Item $full -ErrorAction Stop).FullName
  }

  $candidates = @(
    (Join-Path $Root "build/app/outputs/flutter-apk/app-release.apk"),
    (Join-Path $Root "android/app/build/outputs/flutter-apk/app-release.apk")
  )

  $versioned = Get-ChildItem -Path (Join-Path $Root "build/app/outputs/flutter-apk") -Filter "app-v*-release.apk" -ErrorAction SilentlyContinue
  if ($versioned) {
    foreach ($f in $versioned) {
      $candidates += $f.FullName
    }
  }

  $existing = @($candidates | Where-Object { Test-Path $_ })
  if ($existing.Count -eq 0) {
    throw "No APK found. Build first or pass -ApkPath."
  }

  return ($existing |
    ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1).FullName
}

function Resolve-IpaPath {
  Param([string]$Root, [string]$HintPath)

  if (-not [string]::IsNullOrWhiteSpace($HintPath)) {
    $full = Resolve-Path $HintPath -ErrorAction Stop
    return (Get-Item $full -ErrorAction Stop).FullName
  }

  $candidates = @(
    (Join-Path $Root "build/ios/ipa/*.ipa"),
    (Join-Path $Root "build/ios/Runner.ipa"),
    (Join-Path $Root "build/ios/archive/*.ipa")
  )

  $existing = Get-ChildItem -Path $Root -Recurse -Include "*.ipa" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*build/ios*" }
  if ($candidates) {
    foreach ($pattern in $candidates) {
      $existing += Get-ChildItem -Path (Split-Path $pattern) -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue
    }
  }
  $existing = $existing | Where-Object { $_ -and $_.Exists }
  if ($existing.Count -eq 0) {
    throw "No IPA found. Build first or pass -IpaPath."
  }

  return ($existing |
    ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1).FullName
}

function Ensure-GhAuth {
  Param([string]$GhExe)

  $token = [string]::IsNullOrWhiteSpace($env:GH_TOKEN) -and [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)
  if ($token) {
    $status = & $GhExe auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "GitHub auth missing. Set GH_TOKEN/GITHUB_TOKEN or run 'gh auth login'."
    }
  }
}

function Protect-SafeRollbackRelease {
  Param(
    [string]$Tag,
    [string]$SourceApk,
    [switch]$AllowOverwrite
  )

  $safeRollbackTag = "v1.0"
  $safeRollbackSha256 = "ac7c2a184cbdf73bca9681a042efcbf92d0a414a7ca8948bb36df5b37d10c023"

  if ($Tag -ne $safeRollbackTag) {
    return
  }

  $sourceHash = (Get-FileHash -Algorithm SHA256 -Path $SourceApk).Hash.ToLowerInvariant()
  if ($sourceHash -eq $safeRollbackSha256) {
    return
  }

  if (-not $AllowOverwrite) {
    throw "Refusing to overwrite safe rollback release $safeRollbackTag. Source APK hash is sha256:$sourceHash, expected sha256:$safeRollbackSha256. Pass -AllowOverwriteSafeRollback only for an intentional rollback replacement."
  }

  Write-Warning "Overwriting safe rollback release $safeRollbackTag because -AllowOverwriteSafeRollback was provided."
}

Assert-Tool "git"
if ($BuildBeforePublish) { Assert-Tool "flutter" }

$ghExe = Resolve-GhExe

$root = Resolve-RepoRoot -InputPath $RepoPath
Set-Location $root

$conflicts = @(& git -C $root ls-files -u)
if ($LASTEXITCODE -ne 0 -or $conflicts.Count -gt 0) {
  throw 'Release publication requires a Git checkout without unresolved conflicts.'
}

if ($BuildBeforePublish -and -not $ValidateOnly) {
  Write-Host "Building release APK..." -ForegroundColor Cyan
  $publishVersion = Get-PubspecVersion -Root $root
  $publishShortVersion = ($publishVersion -split "\+", 2)[0]
  & flutter build apk --release `
    "--dart-define=PROX_APP_VERSION=$publishVersion" `
    "--dart-define=PROX_APP_VERSION_SHORT=$publishShortVersion"
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build apk --release failed with code $LASTEXITCODE"
  }
}

$version = Get-PubspecVersion -Root $root
if ([string]::IsNullOrWhiteSpace($Tag)) {
  $Tag = "v$version"
}
if ([string]::IsNullOrWhiteSpace($Title)) {
  $Title = "Prox $version"
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $Notes = "Automated tester APK release for $version."
}
if ([string]::IsNullOrWhiteSpace($Repo)) {
  $Repo = Resolve-GitHubRepoSlug -Root $root
}

if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
    $Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+(?:-(tester|staging))?$') {
  throw 'Use a repository slug and a version tag matching pubspec, optionally suffixed -tester or -staging.'
}
$expectedTag = "v$version"
if ($Prerelease) {
  if ($Tag -notin @("$expectedTag-tester", "$expectedTag-staging")) { throw 'Prerelease tag does not match the package version/channel.' }
} elseif ($Tag -cne $expectedTag) { throw 'Production tag does not match pubspec.yaml.' }
$headCommit = (& git -C $root rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve checkout commit.' }
if (-not $TargetCommit) { $TargetCommit = $headCommit }
if ($TargetCommit -notmatch '^[0-9a-f]{40}$' -or $TargetCommit -cne $headCommit) {
  throw 'TargetCommit must be the full commit SHA of the build checkout.'
}

Ensure-GhAuth -GhExe $ghExe

function Read-GitHubJson {
  Param([string]$Endpoint, [switch]$AllowMissing)
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lines = @(& $ghExe api $Endpoint 2>&1)
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previous }
  $response = $lines | Out-String
  if ($code -ne 0) {
    if ($AllowMissing -and $response -match 'HTTP 404') { return $null }
    throw "GitHub read failed for $Endpoint (exit $code); publication stopped."
  }
  return ($response | ConvertFrom-Json)
}

$encodedTag = [Uri]::EscapeDataString($Tag)
$existingRelease = Read-GitHubJson -Endpoint "repos/$Repo/releases/tags/$encodedTag" -AllowMissing
if ($existingRelease -and -not $existingRelease.draft) {
  throw "Release $Tag is already published. Increase the build number; published assets cannot be replaced."
}
$tagRef = Read-GitHubJson -Endpoint "repos/$Repo/git/ref/tags/$encodedTag" -AllowMissing
if ($tagRef) {
  $tagObject = $tagRef.object
  for ($depth = 0; $tagObject.type -eq 'tag' -and $depth -lt 10; $depth++) {
    $tagObject = (Read-GitHubJson -Endpoint "repos/$Repo/git/tags/$($tagObject.sha)").object
  }
  if ($tagObject.type -ne 'commit' -or $tagObject.sha -cne $TargetCommit) {
    throw 'The remote release tag does not point to the build checkout.'
  }
} elseif ($RequireExistingTag) { throw "Push $Tag to $Repo before publishing." }
else {
  $null = Read-GitHubJson -Endpoint "repos/$Repo/commits/$TargetCommit"
  if ($existingRelease -and $existingRelease.target_commitish -cne $TargetCommit) {
    throw 'Existing draft is not bound to this build commit.'
  }
}
if (-not $Prerelease) {
  $latest = Read-GitHubJson -Endpoint "repos/$Repo/releases/latest" -AllowMissing
  if ($latest -and $latest.tag_name -match '^v(?<sem>[0-9]+\.[0-9]+\.[0-9]+)\+(?<build>[0-9]+)$') {
    $latestSem = [version]$Matches.sem
    $latestBuild = [long]$Matches.build
    $parts = $version -split '\+'
    if ([version]$parts[0] -lt $latestSem -or [long]$parts[1] -le $latestBuild) {
      throw 'Production version cannot go backwards and the Android build number must increase beyond latest.'
    }
  }
}
if ($ValidateOnly) {
  Write-Host "Release preflight PASS: $Tag at $TargetCommit in $Repo"
  exit 0
}
foreach ($assetPath in $AdditionalAssets) {
  if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) { throw "Missing additional release asset: $assetPath" }
}

$sourceApk = Resolve-ApkPath -Root $root -HintPath $ApkPath
$sourceItem = Get-Item $sourceApk -ErrorAction Stop
$canonicalApk = Join-Path $sourceItem.DirectoryName $ApkAssetName

$sourceIpa = $null
$sourceIpaItem = $null
$canonicalIpa = ""
if (-not [string]::IsNullOrWhiteSpace($IpaPath)) {
  $sourceIpa = Resolve-IpaPath -Root $root -HintPath $IpaPath
  $sourceIpaItem = Get-Item $sourceIpa -ErrorAction Stop
  $canonicalIpa = Join-Path $sourceIpaItem.DirectoryName $IpaAssetName
}

Protect-SafeRollbackRelease -Tag $Tag -SourceApk $sourceItem.FullName -AllowOverwrite:$AllowOverwriteSafeRollback

if ($sourceItem.FullName -ne $canonicalApk) {
  Copy-Item -Path $sourceItem.FullName -Destination $canonicalApk -Force
}

Ensure-GhAuth -GhExe $ghExe

$rollbackVerifier = Join-Path $root 'tools/scripts/verify_safe_rollback_release.ps1'
function Verify-Rollback {
  $publicationToken = $env:GH_TOKEN
  try {
    if ($env:ROLLBACK_GITHUB_TOKEN) { $env:GH_TOKEN = $env:ROLLBACK_GITHUB_TOKEN }
    & $rollbackVerifier -RepoPath $root
    if ($LASTEXITCODE -ne 0) { throw 'Protected rollback verification failed.' }
  } finally { $env:GH_TOKEN = $publicationToken }
}
Verify-Rollback
if ($LASTEXITCODE -ne 0) { throw 'Protected rollback verification failed; no release was published.' }

Write-Host "Repo:     $Repo"
Write-Host "Tag:      $Tag"
Write-Host "Title:    $Title"
Write-Host "Source:   $($sourceItem.FullName)"
Write-Host "Canonical:$canonicalApk"
if ($sourceIpaItem) {
  Write-Host "IPA:      $($sourceIpaItem.FullName)"
  Write-Host "IPAName:  $canonicalIpa"
}

$exists = $null -ne $existingRelease

if (-not $exists) {
  # Keep an incomplete pair invisible until all assets have uploaded.
  $notesFile = [IO.Path]::GetTempFileName()
  Set-Content -LiteralPath $notesFile -Value $Notes -Encoding utf8
  $createArgs = @("release", "create", $Tag, "-R", $Repo, "--title", $Title, "--notes-file", $notesFile, "--draft")
  # The existing remote tag was already resolved to the exact build commit.
  # Passing an old --target unnecessarily requires workflow-write permission
  # when main's workflow files advance during the build. Never recreate that tag.
  if ($tagRef) { $createArgs += '--verify-tag' }
  else { $createArgs += @('--target', $TargetCommit) }
  if ($Prerelease) { $createArgs += "--prerelease" }

  Write-Host "Creating release $Tag..." -ForegroundColor Cyan
  try {
    & $ghExe @createArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to create release $Tag" }
  } finally {
    Remove-Item -LiteralPath $notesFile -Force
  }
} else {
  Write-Host "Resuming unpublished draft $Tag..." -ForegroundColor Yellow
}

# Always upload canonical asset so latest-download link remains stable.
& $ghExe release upload $Tag $canonicalApk -R $Repo --clobber
if ($LASTEXITCODE -ne 0) {
  throw "Failed to upload canonical APK"
}

# Also upload the source asset if it has a different file name for traceability.
if ($sourceItem.FullName -ne $canonicalApk) {
  & $ghExe release upload $Tag $sourceItem.FullName -R $Repo --clobber
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload source APK asset"
  }
}

if ($sourceIpaItem) {
  if ($sourceIpaItem.FullName -ne $canonicalIpa) {
    Copy-Item -Path $sourceIpaItem.FullName -Destination $canonicalIpa -Force
  }

  & $ghExe release upload $Tag $canonicalIpa -R $Repo --clobber
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload canonical app-release IPA"
  }

  if ($sourceIpaItem.FullName -ne $canonicalIpa) {
    & $ghExe release upload $Tag $sourceIpaItem.FullName -R $Repo --clobber
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to upload source IPA asset"
    }
  }
}

# Advance the public release only after every requested platform asset exists.
foreach ($assetPath in $AdditionalAssets) {
  & $ghExe release upload $Tag $assetPath -R $Repo --clobber
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload release metadata: $assetPath" }
}
if (-not $Draft) {
  $editArgs = @('release', 'edit', $Tag, '-R', $Repo, '--draft=false')
  if ($SetLatest -and -not $Prerelease) { $editArgs += '--latest' }
  else { $editArgs += '--latest=false' }
  & $ghExe @editArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to mark release $Tag as latest"
  }
}

Verify-Rollback
if ($LASTEXITCODE -ne 0) { throw 'Post-publication rollback verification failed.' }

$releaseUrl = (& $ghExe release view $Tag -R $Repo --json url --jq ".url" 2>$null | Out-String).Trim()
$latestCanonical = "https://github.com/$Repo/releases/latest/download/$ApkAssetName"

Write-Host ""
Write-Host "Release URL: $releaseUrl" -ForegroundColor Green
Write-Host "Latest APK : $latestCanonical" -ForegroundColor Green
if ($sourceIpaItem) {
  Write-Host "Latest IPA : https://github.com/$Repo/releases/latest/download/$IpaAssetName" -ForegroundColor Green
}

exit 0
