from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

from .backends.base import RunConfig, RuntimePaths, cleanup_runtime_dir, find_free_port, run_factorio_command, stage_runtime


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Start a local debug Factorio server for harness inspection.")
    default_extra_mod_paths = [
        value.strip()
        for value in os.environ.get("PBE_DEBUG_EXTRA_MOD_PATHS", "").split(",")
        if value.strip()
    ]
    parser.add_argument("--factorio-bin", type=Path, default=None, help="Path to factorio executable.")
    parser.add_argument("--artifacts-dir", type=Path, default=None, help="Artifacts output directory.")
    parser.add_argument(
        "--runtime-dirname",
        default=os.environ.get("PBE_DEBUG_RUNTIME_DIRNAME", ""),
        help="Optional fixed runtime directory name under artifacts dir; random temp dir is used when omitted.",
    )
    parser.add_argument("--host", default=os.environ.get("PBE_DEBUG_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PBE_DEBUG_PORT", "0")))
    parser.add_argument("--rcon-port", type=int, default=int(os.environ.get("PBE_DEBUG_RCON_PORT", "0")))
    parser.add_argument(
        "--mod-state",
        choices=("enabled", "disabled"),
        default=os.environ.get("PBE_DEBUG_MOD_STATE", "enabled"),
        help="Run with PoweredBeltsExtended enabled or disabled.",
    )
    parser.add_argument(
        "--allow-commands",
        choices=("true", "false", "admins-only"),
        default=os.environ.get("PBE_DEBUG_ALLOW_COMMANDS", "true"),
        help="Server allow_commands setting for local debug sessions.",
    )
    parser.add_argument("--no-initial-reset", action="store_true", help="Do not reset/pause harness state on startup.")
    parser.add_argument("--console-log", default="", help="Optional path for Factorio --console-log output.")
    parser.add_argument(
        "--remove-runtime-dir-on-exit",
        choices=("true", "false"),
        default=os.environ.get("PBE_DEBUG_REMOVE_RUNTIME_DIR_ON_EXIT", "true"),
        help="Remove staged debug runtime directory on exit (default: true).",
    )
    parser.add_argument(
        "--build-order-mode",
        choices=("normal", "reversed", "random"),
        default=os.environ.get("PBE_DEBUG_BUILD_ORDER_MODE", "normal"),
        help="Default build order mode for scenario setup/run after startup.",
    )
    parser.add_argument(
        "--build-order-seed",
        type=int,
        default=(int(os.environ["PBE_DEBUG_BUILD_ORDER_SEED"]) if "PBE_DEBUG_BUILD_ORDER_SEED" in os.environ else None),
        help="Optional seed for random build order mode.",
    )
    parser.add_argument(
        "--extra-mod-path",
        action="append",
        default=default_extra_mod_paths,
        help="Additional mod directory/archive path to stage (repeatable).",
    )
    parser.add_argument(
        "--aai-mode",
        choices=("default", "lubricated", "expensive"),
        default=os.environ.get("PBE_DEBUG_AAI_MODE", "default"),
        help="Optional AAI Loaders startup mode override for staged debug runs.",
    )
    return parser.parse_args()


def _parse_bool_option(name: str, value: str) -> bool:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise RuntimeError(f"Invalid value for {name}: {value!r}. Expected 'true' or 'false'.")


def _parse_extra_mod_paths(values: list[str] | None) -> tuple[Path, ...]:
    if not values:
        return ()
    paths: list[Path] = []
    for raw in values:
        for part in str(raw).split(","):
            trimmed = part.strip()
            if trimmed == "":
                continue
            paths.append(Path(trimmed))
    return tuple(paths)


def _resolve_factorio_bin(arg_value: Path | None) -> Path:
    factorio_bin = arg_value or (Path(os.environ["FACTORIO_BIN"]) if "FACTORIO_BIN" in os.environ else None)
    if factorio_bin is None:
        raise RuntimeError("Missing Factorio binary. Set FACTORIO_BIN or pass --factorio-bin.")
    if not factorio_bin.exists():
        raise RuntimeError(f"Factorio binary does not exist: {factorio_bin}")
    return factorio_bin


def _prepare_world(config: RunConfig, allow_commands: str) -> RuntimePaths:
    runtime = stage_runtime(config)
    result = run_factorio_command(
        config.factorio_bin,
        [
            "--mod-directory",
            str(runtime.mods_dir),
            "--config",
            str(runtime.config_path),
            "--create",
            str(runtime.save_path),
        ],
        timeout_seconds=config.timeout_seconds,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Factorio create step failed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    settings = json.loads(runtime.server_settings_path.read_text(encoding="utf-8"))
    visibility = settings.get("visibility")
    if not isinstance(visibility, dict):
        visibility = {}
    visibility["lan"] = True
    visibility["public"] = False
    if "steam" in visibility:
        visibility["steam"] = False
    settings["visibility"] = visibility
    settings["name"] = "PBE Debug Harness"
    settings["auto_pause"] = False
    if allow_commands == "true":
        settings["allow_commands"] = "true"
    elif allow_commands == "false":
        settings["allow_commands"] = "false"
    else:
        settings["allow_commands"] = "admins-only"
    runtime.server_settings_path.write_text(json.dumps(settings, indent=2), encoding="utf-8")
    return runtime


def _wait_for_tcp_listener(port: int, process: subprocess.Popen[object], timeout_seconds: int = 90) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        code = process.poll()
        if code is not None:
            raise RuntimeError(f"Debug server process exited before port {port} became ready (exit={code})")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for localhost:{port} listener")


def _rcon_send_startup_reset(rcon_port: int, password: str, process: subprocess.Popen[object]) -> None:
    try:
        from factorio_rcon import RCONClient
    except Exception as exc:
        raise RuntimeError("factorio-rcon-py is required for debug startup reset") from exc

    _wait_for_tcp_listener(rcon_port, process, timeout_seconds=90)

    deadline = time.time() + 90
    last_error: Exception | None = None
    while time.time() < deadline:
        code = process.poll()
        if code is not None:
            raise RuntimeError(f"Debug server process exited before RCON became ready (exit={code})")
        try:
            with RCONClient("127.0.0.1", rcon_port, password) as client:
                cmd = (
                    '/silent-command '
                    'local ok, err = pcall(function() '
                    'remote.call("pbe_integration_harness","reset_world"); '
                    "game.tick_paused=true; "
                    'end); '
                    'if ok then rcon.print("pbe-debug-reset-ok") else rcon.print("pbe-debug-reset-fail:"..tostring(err)) end'
                )
                # On fresh saves, the first Lua console command is often rejected with
                # "repeat the command to disable achievements"; retry once in-session.
                response = client.send_command(cmd)
                if isinstance(response, str) and "pbe-debug-reset-ok" in response:
                    return
                response = client.send_command(cmd)
                if isinstance(response, str) and "pbe-debug-reset-ok" in response:
                    return
                last_error = RuntimeError(f"Unexpected RCON startup reset response: {response!r}")
                time.sleep(0.5)
        except Exception as exc:
            last_error = exc
            time.sleep(0.5)

    raise RuntimeError(
        f"Could not initialize debug server over RCON: {last_error}. "
        "Use --no-initial-reset to skip RCON startup reset if needed."
    )


def main() -> int:
    args = parse_args()
    try:
        remove_runtime_dir_on_exit = _parse_bool_option("--remove-runtime-dir-on-exit", args.remove_runtime_dir_on_exit)
        extra_mod_paths = _parse_extra_mod_paths(args.extra_mod_path)
        aai_mode_override = None if args.aai_mode == "default" else args.aai_mode
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parents[3]
    artifacts_dir = args.artifacts_dir or (repo_root / "tests" / "artifacts")
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    try:
        factorio_bin = _resolve_factorio_bin(args.factorio_bin)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    runtime_dirname = args.runtime_dirname.strip() if args.runtime_dirname else ""
    if runtime_dirname and ("/" in runtime_dirname or "\\" in runtime_dirname):
        print("Invalid --runtime-dirname: use a directory name, not a path.", file=sys.stderr)
        return 2

    config = RunConfig(
        factorio_bin=factorio_bin,
        repo_root=repo_root,
        artifacts_dir=artifacts_dir,
        timeout_seconds=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "600")),
        until_tick=0,
        powered_belts_enabled=args.mod_state == "enabled",
        runtime_dirname=runtime_dirname or None,
        remove_runtime_dir_on_exit=remove_runtime_dir_on_exit,
        build_order_mode=args.build_order_mode,
        build_order_seed=args.build_order_seed,
        extra_mod_paths=extra_mod_paths,
        aai_mode_override=aai_mode_override,
    )

    runtime: RuntimePaths | None = None
    try:
        runtime = _prepare_world(
            config,
            allow_commands=args.allow_commands,
        )
    except Exception as exc:
        print(f"Debug server setup failed: {exc}", file=sys.stderr)
        return 3

    game_port = args.port if args.port > 0 else find_free_port()
    rcon_port = args.rcon_port if args.rcon_port > 0 else find_free_port()
    rcon_password = "pbe-debug-rcon-password"

    console_log_path = Path(args.console_log) if args.console_log else (runtime.runtime_root / "debug-server.log")

    cmd = [
        str(factorio_bin),
        "--mod-directory",
        str(runtime.mods_dir),
        "--config",
        str(runtime.config_path),
        "--start-server",
        str(runtime.save_path),
        "--server-settings",
        str(runtime.server_settings_path),
        "--bind",
        args.host,
        "--port",
        str(game_port),
        "--rcon-bind",
        f"127.0.0.1:{rcon_port}",
        "--rcon-password",
        rcon_password,
        "--disable-audio",
        "--console-log",
        str(console_log_path),
    ]

    print(f"Debug runtime root: {runtime.runtime_root}")
    print(f"Connect from GUI to: {args.host}:{game_port}")
    print(f"RCON port: {rcon_port}")
    print(f"PoweredBeltsExtended: {args.mod_state}")
    print(f"allow_commands: {args.allow_commands}")
    print(f"remove_runtime_dir_on_exit: {args.remove_runtime_dir_on_exit}")
    print(f"build_order_mode: {args.build_order_mode}")
    print(f"build_order_seed: {args.build_order_seed}")
    print(f"aai_mode: {args.aai_mode}")
    print(f"extra_mod_paths: {args.extra_mod_path if args.extra_mod_path else []}")
    print(f"Console log: {console_log_path}")
    print("Press Ctrl+C to stop the server.")

    # not using PIPE because it blocks RCON from connecting
    process = subprocess.Popen(cmd)
    try:
        if not args.no_initial_reset:
            _rcon_send_startup_reset(rcon_port, rcon_password, process)
            print("Harness reset complete and game paused at startup.")
            print(
                "Suggested GUI console commands:\n"
                '\n-- Snapshot setup only (auto-save name defaults to pbe-setup-<scenario-id>)'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_straight_name_only_basic")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_straight_name_only_mixed")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_outage_restore_name_only")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_outage_restore_preserve")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_multi_io_outage_restore_disabled_negative")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_multi_io_outage_restore_name_only")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_multi_io_outage_restore_preserve")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_stateful_preserve")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_stateful_name_only_negative")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_disabled_negative")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","planner_deconstruction_outage_persistence")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","planner_upgrade_outage_persistence")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","planner_blueprint_build_and_force_build")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","planner_blueprint_build_and_force_build_multi_io_flicker")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","scan_recovery_smoke")'
                '\n\n-- Setup and keep scenario active so timed actions/checkpoints continue after unpausing'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","transfer_underground_multi_io_outage_restore_preserve")'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","transfer_underground_multi_io_outage_restore_preserve","random",123)'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","planner_blueprint_build_and_force_build")'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","planner_blueprint_build_and_force_build_multi_io_flicker")'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","transfer_underground_multi_io_outage_restore_preserve",nil,{pause_at_tick=600})'
                '\n/c remote.call("pbe_integration_harness","queue_pause_at_tick",600)'

                '\n/c game.tick_paused = false'
                '\n\n-- Change default build order for subsequent setup/run commands'
                '\n/c remote.call("pbe_integration_harness","set_build_order","reversed")'
                '\n/c remote.call("pbe_integration_harness","set_build_order","random",123)'
                '\n/c game.print(helpers.table_to_json(remote.call("pbe_integration_harness","get_build_order")))'
                '\n\n-- Run scenario from scratch (no setup snapshot)'
                '\n/c remote.call("pbe_integration_harness","run_scenario","transfer_underground_multi_io_outage_restore_preserve")'
                '\n/c remote.call("pbe_integration_harness","run_scenario","planner_blueprint_build_and_force_build")'
                '\n/c game.tick_paused = false'
                '\n\n-- Optional: setup with explicit researched technologies override'
                '\n/c remote.call("pbe_integration_harness","prepare_scenario_setup","transfer_straight_name_only_basic",nil,{researched_technologies={"inserter-capacity-bonus-1"}})'
                '\n\n-- Inspect current results'
                '\n/c game.print(helpers.table_to_json(remote.call("pbe_integration_harness","get_results")) )'
            )
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        return 130
    finally:
        if remove_runtime_dir_on_exit and runtime is not None:
            try:
                cleanup_runtime_dir(runtime.runtime_root)
            except Exception as exc:
                print(f"Warning: failed to remove runtime directory {runtime.runtime_root}: {exc}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
