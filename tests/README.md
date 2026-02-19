# Powered Belts Extended Test Suite

This repository contains two automated suites:

1. Lua unit tests (fast logic checks).
2. In-engine integration tests (headless Factorio simulation).

## Prerequisites

1. `Lua 5.2+` on `PATH`.
2. `Python 3.11+` on `PATH`.
3. Factorio 2.0 binary set via `FACTORIO_BIN`.
4. LuaUnit installed (for example `luarocks install luaunit`).

Install Python dependencies:

```bash
python -m pip install -r tests/integration/python/requirements.txt
```

## Run Unit Tests

PowerShell:

```powershell
./scripts/test-unit.ps1
```

POSIX shell:

```bash
./scripts/test-unit.sh
```

## Run Integration Tests

PowerShell:

```powershell
./scripts/test-integration.ps1
# or explicit mode:
python -m tests.integration.python.run_integration --mod-state both
```

POSIX shell:

```bash
./scripts/test-integration.sh
# or explicit mode:
python -m tests.integration.python.run_integration --mod-state both
```

Run-mode strategy and troubleshooting notes:

1. `tests/integration/RUN_MODES.md`

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

Example with explicit setting:

```powershell
./scripts/run-debug-server.ps1 --allow-commands true
```

Use a stable runtime directory (so paths stay constant between runs):

```powershell
./scripts/run-debug-server.ps1 --runtime-dirname debug-local --allow-commands true
```

To launch GUI client with the exact same staged mods and auto-connect:

```powershell
./scripts/run-debug-client.ps1 -RuntimeRoot "<path printed by run-debug-server>" -Port <server-port>
```

## Fixture Pipeline

Blueprint fixture sources live in `tests/fixtures/blueprints/*.txt`.
Run the preprocessor to generate normalized layouts:

```bash
python tests/integration/python/preprocess_blueprints.py
```

Generated outputs:

1. `tests/fixtures/layouts/*.json` (normalized layout data).
2. `tests/integration/harness_mod/layouts_generated/*.lua` (runtime layout modules).

## Notes

1. Core runtime placement does not use `LuaSurface.create_entities_from_blueprint_string`.
2. Integration artifacts are written to `tests/artifacts/`.
3. `disabled` underground mode scenarios are canary-only (non-blocking by default).
