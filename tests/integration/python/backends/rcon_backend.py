from __future__ import annotations

import subprocess
import time
from pathlib import Path

from .base import RunConfig, RuntimePaths, find_free_port, run_factorio_command, stage_runtime


def _create_world(config: RunConfig, runtime: RuntimePaths) -> None:
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


def _send_rcon_probe(port: int, password: str) -> None:
    try:
        from factorio_rcon import RCONClient
    except Exception as exc:  # pragma: no cover - dependency/runtime environment variability
        raise RuntimeError("factorio-rcon-py is required for the RCON backend") from exc

    deadline = time.time() + 30
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with RCONClient("127.0.0.1", port, password) as client:
                client.send_command('/silent-command rcon.print("pbe-rcon-ready")')
                return
        except Exception as exc:  # pragma: no cover - runtime race handling
            last_error = exc
            time.sleep(0.5)
    raise RuntimeError(f"Could not connect over RCON: {last_error}")


def run(config: RunConfig) -> Path:
    runtime = stage_runtime(config)
    _create_world(config, runtime)

    game_port = find_free_port()
    rcon_port = find_free_port()
    rcon_password = "pbe-test-password"
    cmd = [
        str(config.factorio_bin),
        "--mod-directory",
        str(runtime.mods_dir),
        "--config",
        str(runtime.config_path),
        "--start-server",
        str(runtime.save_path),
        "--server-settings",
        str(runtime.server_settings_path),
        "--bind",
        "127.0.0.1",
        "--port",
        str(game_port),
        "--disable-audio",
        "--rcon-port",
        str(rcon_port),
        "--rcon-password",
        rcon_password,
        "--until-tick",
        str(config.until_tick),
    ]
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        _send_rcon_probe(rcon_port, rcon_password)
        stdout, stderr = process.communicate(timeout=config.timeout_seconds)
    except subprocess.TimeoutExpired as exc:
        process.kill()
        raise RuntimeError("Factorio RCON backend timed out") from exc

    if process.returncode != 0:
        raise RuntimeError(
            "Factorio RCON backend failed.\n"
            f"stdout:\n{stdout}\n"
            f"stderr:\n{stderr}"
        )
    if not runtime.result_file.exists():
        raise RuntimeError(f"Missing integration result file: {runtime.result_file}")
    return runtime.result_file
