# Integration Run Modes

This document captures practical run-mode choices for the headless integration suite.

## Goals

1. Keep a fast CI mode that finishes as quickly as possible.
2. Support a controllable-speed debug mode for local investigation.
3. Keep one scenario/harness model and vary only orchestration.

## Key Facts

1. `--until-tick` mode is effectively "run-to-target-tick as fast as possible" in headless runs.
2. In that mode, changing `game.speed` is not a reliable wall-time throttle.
3. `game.speed` still affects the runtime state value, but real elapsed time is mostly CPU-bound.
4. In server mode, `auto_pause` must be disabled for unattended ticking.

## Recommended Modes

### 1) Fast Mode (CI Default)

Use when throughput is most important.

1. Launch with `--load-game <save>` (or `--start-server`) and `--until-tick N`.
2. Keep `N` close to expected suite completion (avoid excessive slack).
3. Treat this mode as CPU-bound fast-forward, not real-time pacing.

Properties:

1. Fastest wall time for CI.
2. `game.speed` is not the main control lever.
3. Best for blocking pass/fail checks.

### 2) Controlled Debug Mode (No `--until-tick`)

Use when you want visual/interactive debugging or predictable slow runs.

1. Launch as server without `--until-tick`.
2. Set `auto_pause=false`.
3. Set `game.speed` from harness (for example `0.1`, `1`, `2`).
4. Stop run when harness reports completion (or manual stop).

Properties:

1. Real speed control is practical.
2. You can connect from GUI client and observe live behavior.
3. Slower than fast mode by design.

## CLI-Only vs RCON

Both are valid for controlled mode.

### CLI-Only

1. Start server from subprocess.
2. Poll for harness result file.
3. Stop process externally when done.

Pros:

1. Simpler dependencies.

Cons:

1. Less graceful process control.
2. Harder to issue live commands.

### RCON-Enabled

1. Start server with RCON.
2. Poll harness state or result file.
3. Stop gracefully via command when done.

Pros:

1. Better lifecycle control.
2. Easier runtime inspection and control.

Cons:

1. Extra dependency and port management.

## Live Spectator Workflow

For local debugging:

1. Start controlled server mode (`--start-server`, no `--until-tick`, `auto_pause=false`).
2. Use low `game.speed` for readability (for example `0.1`).
3. Connect from normal GUI client to `127.0.0.1:<port>`.

## Practical Guidance

1. Keep Fast Mode as default for CI and routine runs.
2. Use Controlled Debug Mode only when investigating behavior, race conditions, or visual correctness.
3. Prefer RCON when robust automated stop/control is needed.
4. Keep harness heartbeat logs enabled while tuning run behavior.

## Mod State Matrix

The Python runner supports:

1. `--mod-state enabled`
2. `--mod-state disabled`
3. `--mod-state both`

Use `both` to run each scenario set twice: once with PoweredBeltsExtended enabled and once disabled.
