param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,

  [switch]$RegeneratePdf
)

$ErrorActionPreference = "Stop"

$playbookDir = Join-Path $RepoRoot "docs\tester-playbook"
$screenshotsDir = Join-Path $playbookDir "screenshots"
$backupDir = Join-Path $playbookDir "screenshots-compressed-backup"
$htmlPath = Join-Path $playbookDir "prox-founding-tester-playbook.html"
$pdfPath = Join-Path $RepoRoot "Prox Tester Guide.pdf"

$canonicalNames = @(
  "01-quick-setup-storage-warning.jpg",
  "02-quick-setup-finish.jpg",
  "03-nearby-update-required.jpg",
  "04-filter-settings.jpg",
  "05-support-feedback-form.jpg",
  "06-nearby-up-to-date.jpg",
  "07-nearby-active-mode.jpg",
  "08-match-settings.jpg",
  "09-nearby-candidates.jpg",
  "10-chat-thread.jpg",
  "11-meetup-location-confirm.jpg",
  "12-signal-color-picker.jpg",
  "13-red-signal-live.jpg",
  "14-meetup-code-entry.jpg",
  "15-meetup-arrival-confirmed.jpg",
  "16-rate-meetup.jpg",
  "17-live-meetup-completed.jpg",
  "18-meetups-history.jpg",
  "19-party-keywords.jpg",
  "20-profile-progress.jpg",
  "21-referrals-qr.jpg",
  "22-support-hub.jpg",
  "23-settings-modes.jpg"
)

if (-not (Test-Path $SourceDir)) {
  throw "SourceDir does not exist: $SourceDir"
}

if (-not (Test-Path $htmlPath)) {
  throw "Playbook HTML not found: $htmlPath"
}

$allowedExtensions = @(".jpg", ".jpeg", ".png", ".webp")
$sourceFiles = Get-ChildItem $SourceDir -File |
  Where-Object { $allowedExtensions -contains $_.Extension.ToLowerInvariant() } |
  Sort-Object Name
if ($sourceFiles.Count -lt $canonicalNames.Count) {
  throw "Need at least $($canonicalNames.Count) source screenshots, found $($sourceFiles.Count) in $SourceDir"
}

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
New-Item -ItemType Directory -Force -Path $screenshotsDir | Out-Null

Get-ChildItem $screenshotsDir -File | Copy-Item -Destination $backupDir -Force

for ($i = 0; $i -lt $canonicalNames.Count; $i++) {
  $source = $sourceFiles[$i]
  $target = Join-Path $screenshotsDir $canonicalNames[$i]
  Copy-Item $source.FullName $target -Force
}

Write-Host "Imported $($canonicalNames.Count) screenshots from $SourceDir"
Write-Host "Compressed originals backed up to $backupDir"

if ($RegeneratePdf) {
  $chromeCandidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
  )
  $browser = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $browser) {
    throw "Chrome or Edge was not found. Import succeeded, but PDF was not regenerated."
  }

  $tempProfile = Join-Path $env:TEMP ("prox-pdf-profile-" + [guid]::NewGuid().ToString("N"))
  $tempPdf = Join-Path $RepoRoot "ProxTesterGuide.tmp.pdf"
  New-Item -ItemType Directory -Force -Path $tempProfile | Out-Null
  Remove-Item $tempPdf,$pdfPath -Force -ErrorAction SilentlyContinue
  $htmlUri = (New-Object System.Uri($htmlPath)).AbsoluteUri
  $args = @(
    "--headless",
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--user-data-dir=$tempProfile",
    "--no-pdf-header-footer",
    "--print-to-pdf=$tempPdf",
    $htmlUri
  )
  & $browser @args

  if (-not (Test-Path $tempPdf)) {
    throw "PDF was not created at $tempPdf"
  }

  Move-Item $tempPdf $pdfPath -Force
  Remove-Item $tempProfile -Recurse -Force -ErrorAction SilentlyContinue

  Get-Item $pdfPath | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
}
