$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InfoPath = Join-Path $RepoRoot "info.json"
$Info = Get-Content -Raw -Path $InfoPath | ConvertFrom-Json
$ModName = "$($Info.name)_$($Info.version)"
$DistDir = Join-Path $RepoRoot "dist"
$ZipPath = Join-Path $DistDir "$ModName.zip"

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

Get-ChildItem -Force -Path $RepoRoot | ForEach-Object {
    $name = $_.Name
    if ($name -in @(".git", ".vscode", "tests", "dist")) {
        return
    }
    Copy-Item -Path $_.FullName -Destination (Join-Path $StagingModDir $name) -Recurse -Force
}

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Compress-Archive -Path (Join-Path $StagingRoot "$ModName\*") -DestinationPath $ZipPath
Write-Output "Packaged mod: $ZipPath"
