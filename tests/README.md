# Powered Belts Extended Integration Tests

This repository uses in-engine integration tests (headless Factorio simulation).

## Prerequisites

1. `Python 3.11+` on `PATH`.
2. Factorio 2.0 binary set via `FACTORIO_BIN`.

Install Python dependencies:

```bash
python -m pip install -r tests/integration/python/requirements.txt
```

## Run Integration Tests

PowerShell:

```powershell
./scripts/test-integration.ps1
# or explicit mode:
python -m tests.integration.python.run_integration --mod-state both
# keep runtime dirs for inspection:
python -m tests.integration.python.run_integration --mod-state both --remove-runtime-dir-on-exit false
```

POSIX shell:

```bash
./scripts/test-integration.sh
# or explicit mode:
python -m tests.integration.python.run_integration --mod-state both
# keep runtime dirs for inspection:
python -m tests.integration.python.run_integration --mod-state both --remove-runtime-dir-on-exit false
```

Run-mode strategy and troubleshooting notes:

1. `tests/integration/RUN_MODES.md`


## Item Chain Scan / Disappearance Diagnosis

You can inject an item-chain scan action into a scenario.
The action type is `scan_item_locations` and supports:

- `debug_log` (`true/false`): print structured scan payload to Factorio logs.
- `output_file` (`string`): write JSON payload into `script-output/<name>`.
- `output_file_pattern` (`string`): template with `{tick}` and `{scenario}` placeholders.

A dedicated diagnosis runner can execute a single scenario, inject scans at 0%, 10%..100%, and iteratively bisect loss intervals:

```bash
python -m tests.integration.python.run_single_disappearance_diagnosis <scenario_id>
```

Outputs:

- `tests/artifacts/item-disappearance-analysis-<scenario_id>.json`
- `tests/artifacts/item-disappearance-analysis-<scenario_id>.txt`

The JSON includes per-run sampled ticks, loss intervals, exact disappearance ticks (when identified), per-location loss deltas, and nearby non-scan test actions.

## Run Debug Server (GUI Connect)

PowerShell:

```powershell
./scripts/run-debug-server.ps1
```

POSIX shell:

```bash
./scripts/run-debug-server.sh
```

The command starts a localhost server without `--until-tick`, prints the connection address, and pauses/reset harness state on startup.
By default it uses `allow_commands=true` so GUI `/c` commands work in debug sessions.
By default it removes the staged runtime directory on exit (`--remove-runtime-dir-on-exit true`).

Example with explicit setting:

```powershell
./scripts/run-debug-server.ps1 --allow-commands true
# keep runtime dir after exit:
./scripts/run-debug-server.ps1 --allow-commands true --remove-runtime-dir-on-exit false
```

Use a stable runtime directory (so paths stay constant between runs):

```powershell
./scripts/run-debug-server.ps1 --runtime-dirname debug-local --allow-commands true
```

To launch GUI client with the exact same staged mods and auto-connect:

```powershell
./scripts/run-debug-client.ps1 -RuntimeRoot "<path printed by run-debug-server>" -Port <server-port>
```

## Layout Fixtures

Layouts are maintained directly as Lua modules in:

1. `tests/integration/harness_mod/layouts_generated/*.lua`
2. `tests/integration/harness_mod/layouts_generated/index.lua`

## Notes

1. Core runtime placement does not use `LuaSurface.create_entities_from_blueprint_string`.
2. Integration artifacts are written to `tests/artifacts/`.
