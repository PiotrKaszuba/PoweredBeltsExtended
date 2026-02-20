from __future__ import annotations

import json
import socket
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


@dataclass(frozen=True)
class RunConfig:
    factorio_bin: Path
    repo_root: Path
    artifacts_dir: Path
    timeout_seconds: int
    until_tick: int
    powered_belts_enabled: bool = True
    runtime_dirname: str | None = None
    remove_runtime_dir_on_exit: bool = True


@dataclass(frozen=True)
class BackendRunResult:
    result_file: Path
    runtime_root: Path


@dataclass(frozen=True)
class RuntimePaths:
    runtime_root: Path
    mods_dir: Path
    user_data_dir: Path
    config_path: Path
    server_settings_path: Path
    save_path: Path
    script_output_dir: Path
    result_file: Path


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _make_ignore_copy(artifacts_dir: Path):
    artifacts_dir_resolved = artifacts_dir.resolve()

    def _ignore_copy(path: str, names: list[str]) -> set[str]:
        ignored = {".git", ".vscode", "__pycache__", ".pytest_cache"}
        current = Path(path).resolve()

        # Never recurse into the configured artifacts branch while copying repo sources.
        if _is_relative_to(artifacts_dir_resolved, current):
            relative = artifacts_dir_resolved.relative_to(current)
            if len(relative.parts) > 0:
                ignored.add(relative.parts[0])

        return {name for name in names if name in ignored}

    return _ignore_copy


def _fallback_server_settings() -> dict[str, object]:
    return {
        "name": "PBE Integration Harness",
        "description": "Headless integration test server",
        "tags": ["integration", "pbe"],
        "max_players": 0,
        "visibility": {"public": False, "lan": False, "steam": False},
        "username": "",
        "password": "",
        "token": "",
        "game_password": "",
        "require_user_verification": True,
        "max_upload_in_kilobytes_per_second": 0,
        "max_upload_slots": 5,
        "minimum_latency_in_ticks": 0,
        "ignore_player_limit_for_returning_players": False,
        "allow_commands": "admins-only",
        "autosave_interval": 10,
        "autosave_slots": 3,
        "afk_autokick_interval": 0,
        "auto_pause": False,
        "only_admins_can_pause_the_game": True,
        "autosave_only_on_server": True,
        "non_blocking_saving": False,
        "minimum_segment_size": 25,
        "minimum_segment_size_peer_count": 20,
        "maximum_segment_size": 100,
    }


def _load_server_settings_example(factorio_bin: Path) -> dict[str, object]:
    factorio_bin = factorio_bin.resolve()
    search_roots = [
        factorio_bin.parent,
        factorio_bin.parent.parent,
        factorio_bin.parent.parent.parent,
    ]
    for root in search_roots:
        candidate = root / "data" / "server-settings.example.json"
        if not candidate.exists():
            continue
        try:
            loaded = json.loads(candidate.read_text(encoding="utf-8-sig"))
            if isinstance(loaded, dict):
                return loaded
        except Exception:
            continue
    return _fallback_server_settings()


def _build_test_server_settings(factorio_bin: Path) -> dict[str, object]:
    settings = _load_server_settings_example(factorio_bin)
    settings["auto_pause"] = False
    settings["name"] = "PBE Integration Harness"
    settings["max_players"] = 0

    visibility = settings.get("visibility")
    if not isinstance(visibility, dict):
        visibility = {}
    visibility["public"] = False
    visibility["lan"] = False
    if "steam" in visibility:
        visibility["steam"] = False
    settings["visibility"] = visibility

    return settings


def stage_runtime(config: RunConfig) -> RuntimePaths:
    repo_root = config.repo_root.resolve()
    artifacts_dir = config.artifacts_dir.resolve()

    runtime_root: Path
    if config.runtime_dirname:
        runtime_parent = artifacts_dir
        runtime_parent.mkdir(parents=True, exist_ok=True)
        runtime_root = runtime_parent / config.runtime_dirname
        if runtime_root.exists():
            shutil.rmtree(runtime_root)
        runtime_root.mkdir(parents=True, exist_ok=True)
    else:
        # If artifacts are inside the repo, stage runtime in system temp to avoid copytree recursion.
        runtime_parent: Path | None = artifacts_dir
        if _is_relative_to(artifacts_dir, repo_root):
            runtime_parent = None
        else:
            runtime_parent.mkdir(parents=True, exist_ok=True)
        runtime_root = Path(tempfile.mkdtemp(prefix="pbe-tests-", dir=None if runtime_parent is None else str(runtime_parent)))
    mods_dir = runtime_root / "mods"
    user_data_dir = runtime_root / "user-data"
    config_path = runtime_root / "factorio-config.ini"
    server_settings_path = runtime_root / "server-settings.json"
    script_output_dir = user_data_dir / "script-output"
    save_path = runtime_root / "scenario-save.zip"
    mods_dir.mkdir(parents=True, exist_ok=True)
    script_output_dir.mkdir(parents=True, exist_ok=True)
    (user_data_dir / "mods").mkdir(parents=True, exist_ok=True)

    if config.powered_belts_enabled:
        mod_dest = mods_dir / config.repo_root.name
        shutil.copytree(config.repo_root, mod_dest, ignore=_make_ignore_copy(artifacts_dir), dirs_exist_ok=False)

    harness_source = config.repo_root / "tests" / "integration" / "harness_mod"
    harness_dest = mods_dir / "PBEIntegrationHarness_0.1.0"
    shutil.copytree(harness_source, harness_dest, dirs_exist_ok=False)

    mod_entries = [
        {"name": "base", "enabled": True},
        {"name": "PBEIntegrationHarness", "enabled": True},
    ]
    if config.powered_belts_enabled:
        mod_entries.insert(1, {"name": "PoweredBeltsExtended", "enabled": True})

    mod_list = {"mods": mod_entries}
    (user_data_dir / "mods" / "mod-list.json").write_text(json.dumps(mod_list, indent=2), encoding="utf-8")

    config_path.write_text("[path]\nwrite-data=" + str(user_data_dir).replace("\\", "/") + "\n", encoding="utf-8")
    server_settings = _build_test_server_settings(config.factorio_bin)
    server_settings_path.write_text(json.dumps(server_settings, indent=2), encoding="utf-8")

    return RuntimePaths(
        runtime_root=runtime_root,
        mods_dir=mods_dir,
        user_data_dir=user_data_dir,
        config_path=config_path,
        server_settings_path=server_settings_path,
        save_path=save_path,
        script_output_dir=script_output_dir,
        result_file=script_output_dir / "pbe-integration-results.json",
    )


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def run_factorio_command(
    factorio_bin: Path,
    args: Sequence[str],
    timeout_seconds: int,
) -> subprocess.CompletedProcess[str]:
    cmd = [str(factorio_bin), *args]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )


def cleanup_runtime_dir(runtime_root: Path) -> None:
    if runtime_root.exists():
        shutil.rmtree(runtime_root)
