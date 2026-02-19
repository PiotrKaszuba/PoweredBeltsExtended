from __future__ import annotations

from pathlib import Path

from .base import RunConfig, RuntimePaths, run_factorio_command, stage_runtime


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


def _run_headless_suite(config: RunConfig, runtime: RuntimePaths) -> None:
    result = run_factorio_command(
        config.factorio_bin,
        [
            "--mod-directory",
            str(runtime.mods_dir),
            "--config",
            str(runtime.config_path),
            "--load-game",
            str(runtime.save_path),
            "--disable-audio",
            "--until-tick",
            str(config.until_tick),
        ],
        timeout_seconds=config.timeout_seconds,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Factorio headless suite failed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def run(config: RunConfig) -> Path:
    runtime = stage_runtime(config)
    _create_world(config, runtime)
    _run_headless_suite(config, runtime)
    if not runtime.result_file.exists():
        raise RuntimeError(f"Missing integration result file: {runtime.result_file}")
    return runtime.result_file
