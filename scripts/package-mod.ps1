$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InfoPath = Join-Path $RepoRoot "info.json"
$Info = Get-Content -Raw -Path $InfoPath | ConvertFrom-Json
$ModName = "$($Info.name)_$($Info.version)"
$DistDir = Join-Path $RepoRoot "dist"
$ZipPath = Join-Path $DistDir "$ModName.zip"
$IncludeFiles = @(
    "control.lua",
    "settings.lua",
    "data-final-fixes.lua",
    "info.json",
    "changelog.txt",
    "thumbnail.png"
)
$IncludeDirs = @(
    "locale",
    "prototypes"
)

if (!(Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

$StagingRoot = Join-Path $env:TEMP "$ModName-package"
if (Test-Path $StagingRoot) {
    Remove-Item -Recurse -Force $StagingRoot
}
New-Item -ItemType Directory -Path $StagingRoot | Out-Null

$StagingModDir = Join-Path $StagingRoot $ModName
New-Item -ItemType Directory -Path $StagingModDir | Out-Null

foreach ($name in $IncludeFiles) {
    $source = Join-Path $RepoRoot $name
    if (!(Test-Path $source -PathType Leaf)) {
        throw "Missing required file for packaging: $name"
    }
    Copy-Item -Path $source -Destination (Join-Path $StagingModDir $name) -Force
}

foreach ($name in $IncludeDirs) {
    $source = Join-Path $RepoRoot $name
    if (!(Test-Path $source -PathType Container)) {
        throw "Missing required directory for packaging: $name"
    }
    Copy-Item -Path $source -Destination (Join-Path $StagingModDir $name) -Recurse -Force
}

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Compress-Archive -Path (Join-Path $StagingRoot "$ModName\*") -DestinationPath $ZipPath
Write-Output "Packaged mod: $ZipPath"
