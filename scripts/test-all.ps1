param(
    [string]$AaiModPath = $env:PBE_AAI_MOD_PATH,
    [switch]$SkipAai,
    [switch]$SkipSyntax,
    [switch]$SkipCompile,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$IntegrationArgs
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Name (exit code $LASTEXITCODE)"
    }
}

Push-Location $RepoRoot
try {
    if (-not $SkipSyntax) {
        Invoke-Step "Lua syntax checks" {
            lua -e "assert(loadfile('control.lua')); assert(loadfile('modules/compatibility.lua')); assert(loadfile('modules/undergrounds.lua')); assert(loadfile('tests/integration/harness_mod/lib/runtime.lua')); assert(loadfile('tests/integration/harness_mod/lib/assertions.lua')); assert(loadfile('tests/integration/harness_mod/lib/world.lua')); assert(loadfile('tests/integration/harness_mod/scenarios.lua')); print('lua syntax ok')"
        }
    }

    if (-not $SkipCompile) {
        Invoke-Step "Python compile checks" {
            python -m compileall tests/integration/python
        }
    }

    Invoke-Step "Integration suite (baseline: no AAI extra mod)" {
        python -m tests.integration.python.run_integration @IntegrationArgs
    }

    if (-not $SkipAai) {
        if ([string]::IsNullOrWhiteSpace($AaiModPath)) {
            Write-Warning "Skipping AAI integration runs: no AAI mod path provided. Set PBE_AAI_MOD_PATH or pass -AaiModPath."
        }
        elseif (-not (Test-Path $AaiModPath)) {
            throw "AAI mod path does not exist: $AaiModPath"
        }
        else {
            Invoke-Step "Integration suite (AAI lubricated mode)" {
                python -m tests.integration.python.run_integration --mod-state enabled --extra-mod-path $AaiModPath --aai-mode lubricated @IntegrationArgs
            }

            Invoke-Step "Integration suite (AAI expensive mode)" {
                python -m tests.integration.python.run_integration --mod-state enabled --extra-mod-path $AaiModPath --aai-mode expensive @IntegrationArgs
            }
        }
    }
}
finally {
    Pop-Location
}