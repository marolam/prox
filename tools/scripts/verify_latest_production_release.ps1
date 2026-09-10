param(
  [string]$Repo = "marolam/prox-us",
  [string]$PubspecPath = "pubspec.yaml",
  [string]$AssetName = "app-release.apk"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required."
}
if (-not (Test-Path -LiteralPath $PubspecPath)) {
  throw "pubspec file not found: $PubspecPath"
}

$versionLine = Select-String -LiteralPath $PubspecPath -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
if (-not $versionLine) {
  throw "No version entry found in $PubspecPath"
}

$expectedVersion = $versionLine.Matches[0].Groups[1].Value
$expectedTag = "v$expectedVersion"
$release = gh release view --repo $Repo --json tagName,isDraft,isPrerelease,assets,url | ConvertFrom-Json

if ($release.isDraft -or $release.isPrerelease) {
  throw "Latest release is not stable: $($release.url)"
}
if ($release.tagName -ne $expectedTag) {
  throw "Latest release '$($release.tagName)' does not match pubspec '$expectedTag'."
}

$asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
if (-not $asset) {
  throw "Release $expectedTag does not contain $AssetName."
}
if ([int64]$asset.size -le 0) {
  throw "Release asset $AssetName is empty."
}
if ([string]::IsNullOrWhiteSpace([string]$asset.digest) -or -not ([string]$asset.digest).StartsWith("sha256:")) {
  throw "Release asset $AssetName has no GitHub SHA-256 digest."
}

Write-Host "Production release verified: $Repo $expectedTag $AssetName ($($asset.size) bytes, $($asset.digest))"
