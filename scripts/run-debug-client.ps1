param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRoot,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [string]$ServerHost = "127.0.0.1",
    [string]$FactorioBin = $env:FACTORIO_BIN,
    [string]$ClientProfile = "client"
)

$ErrorActionPreference = "Stop"

if (-not $FactorioBin) {
    throw "Missing Factorio binary. Set FACTORIO_BIN or pass -FactorioBin."
}
if (-not (Test-Path $FactorioBin)) {
    throw "Factorio binary does not exist: $FactorioBin"
}

$runtimeResolved = (Resolve-Path $RuntimeRoot).Path
$modsDir = Join-Path $runtimeResolved "mods"
if (-not (Test-Path $modsDir)) {
    throw "Runtime mods directory not found: $modsDir"
}

$clientWriteData = Join-Path $runtimeResolved ("user-data-" + $ClientProfile)
New-Item -ItemType Directory -Force -Path $clientWriteData | Out-Null

$clientConfigPath = Join-Path $runtimeResolved ("client-config-" + $ClientProfile + ".ini")
$writeDataForwardSlashes = $clientWriteData -replace "\\", "/"
$configContent = "[path]`nwrite-data=$writeDataForwardSlashes`n"
Set-Content -Path $clientConfigPath -Value $configContent -Encoding UTF8

$connectAddress = "$ServerHost`:$Port"
Write-Host "Launching client with runtime mods from: $modsDir"
Write-Host "Using client write-data: $clientWriteData"
Write-Host "Connecting to: $connectAddress"

& $FactorioBin --mod-directory $modsDir --config $clientConfigPath --mp-connect $connectAddress
exit $LASTEXITCODE
