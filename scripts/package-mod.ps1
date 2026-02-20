# Release script for PoweredBeltsExtended
# Creates a distributable mod package for Factorio mod portal

param(
    [switch]$NoZip,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Get script and project directories
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

# Read version from info.json
$InfoJson = Get-Content -Path (Join-Path $ProjectDir "info.json") -Raw | ConvertFrom-Json
$ModName = $InfoJson.name
$Version = $InfoJson.version

Write-Host "Building release for $ModName v$Version" -ForegroundColor Cyan

# Define output paths
$ReleasesDir = Join-Path $ProjectDir "releases"
$OutputDir = Join-Path $ReleasesDir "${ModName}_${Version}"
$ZipPath = Join-Path $ReleasesDir "${ModName}_${Version}.zip"

# Clean previous release if requested or if it exists
if ($Clean -or (Test-Path $OutputDir)) {
    if (Test-Path $OutputDir) {
        Write-Host "Removing existing release directory..." -ForegroundColor Yellow
        Remove-Item -Path $OutputDir -Recurse -Force
    }
    if (Test-Path $ZipPath) {
        Write-Host "Removing existing zip file..." -ForegroundColor Yellow
        Remove-Item -Path $ZipPath -Force
    }
}

# Create output directory
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Files to include (relative to project root)
$FilesToInclude = @(
    "info.json",
    "control.lua",
    "data-final-fixes.lua",
    "settings.lua",
    "changelog.txt",
    "thumbnail.png",
    "LICENSE"
)

# Directories to include
$DirsToInclude = @(
    "locale",
    "prototypes"
)

# Copy individual files
Write-Host "`nCopying files:" -ForegroundColor Green
foreach ($file in $FilesToInclude) {
    $sourcePath = Join-Path $ProjectDir $file
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $OutputDir
        Write-Host "  + $file" -ForegroundColor Gray
    } else {
        Write-Host "  - $file (not found, skipping)" -ForegroundColor Yellow
    }
}

# Copy directories
Write-Host "`nCopying directories:" -ForegroundColor Green
foreach ($dir in $DirsToInclude) {
    $sourcePath = Join-Path $ProjectDir $dir
    if (Test-Path $sourcePath) {
        $destPath = Join-Path $OutputDir $dir
        Copy-Item -Path $sourcePath -Destination $destPath -Recurse

        # Remove Thumbs.db files from copied directories
        Get-ChildItem -Path $destPath -Filter "Thumbs.db" -Recurse | Remove-Item -Force

        $fileCount = (Get-ChildItem -Path $destPath -File -Recurse).Count
        Write-Host "  + $dir/ ($fileCount files)" -ForegroundColor Gray
    } else {
        Write-Host "  - $dir/ (not found, skipping)" -ForegroundColor Yellow
    }
}

# Create zip file
if (-not $NoZip) {
    Write-Host "`nCreating zip archive..." -ForegroundColor Green

    # Compress using .NET to ensure proper zip structure
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path $ZipPath) {
        Remove-Item -Path $ZipPath -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory($OutputDir, $ZipPath)

    $zipSize = (Get-Item $ZipPath).Length / 1KB
    Write-Host "  Created: $ZipPath ($([math]::Round($zipSize, 2)) KB)" -ForegroundColor Gray
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Release build complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Output directory: $OutputDir"
if (-not $NoZip) {
    Write-Host "Zip file: $ZipPath"
}

# List final contents
Write-Host "`nRelease contents:" -ForegroundColor Cyan
Get-ChildItem -Path $OutputDir -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($OutputDir.Length + 1)
    if ($_.PSIsContainer) {
        Write-Host "  [DIR]  $relativePath/" -ForegroundColor Blue
    } else {
        Write-Host "  [FILE] $relativePath" -ForegroundColor Gray
    }
}
