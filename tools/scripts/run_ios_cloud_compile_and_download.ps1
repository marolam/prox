param(
    [string]$Branch = "ios-cloud-compile-20260730",
    [string]$Workflow = "ios_cloud_compile.yml",
    [string]$ArtifactName = "Runner-no-codesign",
    [string]$OutputRoot = ".\\artifacts\\ios_cloud_compile",
    [switch]$ExtractZip
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is not installed or not on PATH."
}

$workspace = (Get-Location).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runOutputDir = Join-Path $OutputRoot ("run_" + $timestamp)
New-Item -ItemType Directory -Force -Path $runOutputDir | Out-Null

Write-Host "Dispatching workflow '$Workflow' on branch '$Branch'..."
$dispatch = & gh workflow run $Workflow --ref $Branch 2>&1 | Out-String
Write-Host $dispatch.Trim()

$runId = $null
if ($dispatch -match "actions/runs/(\d+)") {
    $runId = $Matches[1]
}

if (-not $runId) {
    throw "Could not parse run ID from gh workflow run output."
}

Write-Host "Watching run $runId until completion..."
& gh run watch $runId --exit-status

$resultJson = & gh run view $runId --json status,conclusion,url,headSha,headBranch,displayTitle --jq "."
$result = $resultJson | ConvertFrom-Json

Write-Host "Run URL: $($result.url)"
Write-Host "Run status: $($result.status)"
Write-Host "Run conclusion: $($result.conclusion)"

if ($result.conclusion -ne "success") {
    throw "Workflow run $runId finished with conclusion '$($result.conclusion)'."
}

Write-Host "Downloading artifact '$ArtifactName' to '$runOutputDir'..."
& gh run download $runId --name $ArtifactName --dir $runOutputDir

$downloaded = Get-ChildItem -Path $runOutputDir -Recurse | Where-Object { -not $_.PSIsContainer }
if (-not $downloaded) {
    throw "No files were downloaded for artifact '$ArtifactName'."
}

if ($ExtractZip) {
    $zips = Get-ChildItem -Path $runOutputDir -Recurse -Filter "*.zip"
    foreach ($zip in $zips) {
        $extractDir = Join-Path $zip.DirectoryName "extracted"
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        Expand-Archive -Path $zip.FullName -DestinationPath $extractDir -Force
        Write-Host "Extracted: $($zip.FullName) -> $extractDir"
    }
}

Write-Host "Done. Downloaded files:"
foreach ($file in $downloaded) {
    Write-Host (" - " + $file.FullName)
}

Write-Host "Run summary:"
Write-Host (" - Run ID: " + $runId)
Write-Host (" - Branch: " + $result.headBranch)
Write-Host (" - Commit: " + $result.headSha)
Write-Host (" - Output: " + (Resolve-Path $runOutputDir).Path)