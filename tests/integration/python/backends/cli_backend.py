from __future__ import annotations

from .base import BackendRunResult, RunConfig, RuntimePaths, cleanup_runtime_dir, run_factorio_command, stage_runtime


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
    # Benchmark executes deterministic Lua on both headless and installed clients,
    # without opening a game window or changing the player's profile.
    launch = ["--benchmark", str(runtime.save_path), "--benchmark-ticks", str(config.until_tick),
              "--benchmark-runs", "1", "--disable-audio"]
    result = run_factorio_command(config.factorio_bin,
        ["--mod-directory", str(runtime.mods_dir), "--config", str(runtime.config_path), *launch],
        timeout_seconds=config.timeout_seconds)
    if result.returncode != 0:
        raise RuntimeError("Factorio headless suite failed.\n" + result.stdout + "\n" + result.stderr)


def run(config: RunConfig) -> BackendRunResult:
    runtime = stage_runtime(config)
    try:
        if config.upgrade_save is not None:
            if config.restart_at_tick is not None:
                raise ValueError("Use a saved upgrade checkpoint or a new restart trial, not both")
            import shutil
            shutil.copy2(config.upgrade_save, runtime.save_path)
        else:
            _create_world(config, runtime)
        if config.restart_at_tick is not None:
            if not 0 < config.restart_at_tick < config.until_tick:
                raise ValueError("Restart tick must lie inside the trial")
            from .base import find_free_port
            import subprocess, time, zipfile
            save = runtime.save_path
            for phase in (1, 2):
                log_path = runtime.runtime_root / f"restart-phase-{phase}.log"
                with log_path.open("w", encoding="utf-8") as log:
                    process = subprocess.Popen([str(config.factorio_bin),
                        "--mod-directory", str(runtime.mods_dir), "--config", str(runtime.config_path),
                        "--start-server", str(save), "--server-settings", str(runtime.server_settings_path),
                        "--bind", "127.0.0.1", "--port", str(find_free_port())], stdout=log, stderr=subprocess.STDOUT)
                    try:
                        deadline = time.monotonic() + config.timeout_seconds
                        while time.monotonic() < deadline:
                            checkpoints = list((runtime.user_data_dir / "saves").glob("*pbe-acceptance-checkpoint*.zip"))
                            if phase == 1 and len(checkpoints) == 1 and zipfile.is_zipfile(checkpoints[0]):
                                save = checkpoints[0]
                                break
                            if phase == 2 and runtime.result_file.exists():
                                break
                            if process.poll() is not None:
                                raise RuntimeError("Server exited before checkpoint/result; " + log_path.read_text()[-4000:])
                            time.sleep(0.1)
                        else:
                            raise RuntimeError("Save/restart timed out; " + log_path.read_text()[-4000:])
                    finally:
                        if process.poll() is None:
                            process.terminate()
                            try:
                                process.wait(timeout=10)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait()

        else:
            _run_headless_suite(config, runtime)
        if not runtime.result_file.exists():
            raise RuntimeError(f"Missing integration result file: {runtime.result_file}")
        return BackendRunResult(result_file=runtime.result_file, runtime_root=runtime.runtime_root)
    except Exception:
        if config.remove_runtime_dir_on_exit:
            try:
                cleanup_runtime_dir(runtime.runtime_root)
            except Exception:
                pass
        raise
