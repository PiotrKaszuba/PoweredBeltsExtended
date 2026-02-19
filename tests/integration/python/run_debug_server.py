from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

from .backends.base import RunConfig, find_free_port, run_factorio_command, stage_runtime


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Start a local debug Factorio server for harness inspection.")
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
    return parser.parse_args()


def _resolve_factorio_bin(arg_value: Path | None) -> Path:
    factorio_bin = arg_value or (Path(os.environ["FACTORIO_BIN"]) if "FACTORIO_BIN" in os.environ else None)
    if factorio_bin is None:
        raise RuntimeError("Missing Factorio binary. Set FACTORIO_BIN or pass --factorio-bin.")
    if not factorio_bin.exists():
        raise RuntimeError(f"Factorio binary does not exist: {factorio_bin}")
    return factorio_bin


def _prepare_world(config: RunConfig, allow_commands: str) -> tuple[Path, Path, Path, Path, Path]:
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
    return runtime.runtime_root, runtime.mods_dir, runtime.config_path, runtime.save_path, runtime.server_settings_path


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
    )

    try:
        runtime_root, mods_dir, config_path, save_path, server_settings_path = _prepare_world(
            config,
            allow_commands=args.allow_commands,
        )
    except Exception as exc:
        print(f"Debug server setup failed: {exc}", file=sys.stderr)
        return 3

    game_port = args.port if args.port > 0 else find_free_port()
    rcon_port = args.rcon_port if args.rcon_port > 0 else find_free_port()
    rcon_password = "pbe-debug-rcon-password"

    console_log_path = Path(args.console_log) if args.console_log else (runtime_root / "debug-server.log")

    cmd = [
        str(factorio_bin),
        "--mod-directory",
        str(mods_dir),
        "--config",
        str(config_path),
        "--start-server",
        str(save_path),
        "--server-settings",
        str(server_settings_path),
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

    print(f"Debug runtime root: {runtime_root}")
    print(f"Connect from GUI to: {args.host}:{game_port}")
    print(f"RCON port: {rcon_port}")
    print(f"PoweredBeltsExtended: {args.mod_state}")
    print(f"allow_commands: {args.allow_commands}")
    print(f"Console log: {console_log_path}")
    print("Press Ctrl+C to stop the server.")

    process = subprocess.Popen(cmd)
    try:
        if not args.no_initial_reset:
            _rcon_send_startup_reset(rcon_port, rcon_password, process)
            print("Harness reset complete and game paused at startup.")
            print(
                "To snapshot setup state from GUI console:\n"
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_straight_name_only_basic","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_straight_name_only_mixed","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_outage_restore_name_only","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_outage_restore_preserve","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_stateful_preserve","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_stateful_name_only_canary","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","transfer_underground_disabled_canary","pbe-setup-straight")'
                '\n/c remote.call("pbe_integration_harness","capture_scenario_setup","scan_recovery_smoke","pbe-setup-straight")'
            )
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
