# Powered Belts Extended Integration Tests

This repository uses in-engine integration tests (headless Factorio simulation).

## Prerequisites

1. `Python 3.11+` on `PATH`.
2. Factorio 2.1 binary set via `FACTORIO_BIN`.

The CLI backend needs no third-party Python packages. Install the optional RCON dependency only when using that backend:

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


## Exact archive and persistence acceptance

The default source suite includes diagnostic transfer modes and deliberately broken
negative controls. A packaged release excludes `modules/tests.lua`; use the
production acceptance selection rather than silently relying on unavailable overrides:

```text
python -m tests.integration.python.run_integration --factorio-bin PATH_TO_2_1 --mod-zip PATH_TO_ZIP --mod-state enabled --scenario-filter suite:acceptance --run-timing-suite false
python -m tests.integration.python.run_integration --factorio-bin PATH_TO_2_1 --mod-zip PATH_TO_ZIP --mod-state enabled --scenario-filter planner_upgrade_outage_persistence --restart-at-tick 400 --run-timing-suite false
```

Archive bytes are staged unchanged. Reports record SHA-256 and actual engine version.
The acceptance subset covers ordinary item/property conservation, planner/ghost
behavior, scan recovery and applicable AAI cases. Main archive trials retain the
real default processing rate. The preset trials explicitly use 128 operations/tick
to separate threshold behavior from scheduler delay; Custom also sets isolated
50% + 10-point threshold and 20% hysteresis defaults (48%/72% band).

`--restart-at-tick` uses two separate localhost server processes, a real native
checkpoint and the resumed active harness state. It does not prove an old-version
upgrade. Keep RCON optional; Lua drives the actual scenario actions.

Benchmark execution runs ordinary scenarios without opening the game UI. Engine data paths and base-only mod selection are explicit.
No original saves, installed mods or Steam branch settings are modified.

The synthetic floating-belt prototype fixture verifies a valid nonstandard collision
mask and upgrade chain through PBE cloning and engine loading. It does not establish
full Dredgeworks compatibility or reproduce a reporter's 2.1 setup.

## Focused policy and performance checks

```text
lua tests/test_power_behavior.lua
lua tests/performance_power_thresholds.lua
```

The policy test checks threshold math and cache refresh on the next tick / changed
test overrides. Native Custom-mode tests separately cover actual LuaCustomTable
settings, both states inside the deadband, and transitions outside it. The CPU
microbenchmark uses 16 and 1024 checks/tick, a warmup and 1000 ticks per scale;
it isolates threshold reads and cannot predict complete update cost or native UPS.
Pass an exported earlier `modules/utils.lua` as its optional argument to compare
with the same read pattern. Do not use tiny timing differences as correctness gates.

See [bounded validation evidence](VALIDATION.md). Generated runs stay under ignored
`tests/artifacts/`; retain concise findings rather than committing complete run logs.

## Item Chain Scan / Disappearance Diagnosis

You can inject an item-chain scan action into a scenario.
The action type is `scan_item_locations` and supports:

- `debug_log` (`true/false`): print structured scan payload to Factorio logs.
- `output_file` (`string`): write JSON payload into `script-output/<name>`.
- `output_file_pattern` (`string`): template with `{tick}` and `{scenario}` placeholders.

You can also schedule a game pause at a scenario-relative tick:

- Action type: `pause_game` with `tick = <scenario_elapsed_tick>`.
- Remote call while a scenario is active: `remote.call("pbe_integration_harness","queue_pause_at_tick", 600)`.
- Setup-time option: `prepare_scenario_setup(..., { pause_at_tick = 600 })`.
- Default behavior is unchanged: no pause is auto-queued unless you request it.

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
