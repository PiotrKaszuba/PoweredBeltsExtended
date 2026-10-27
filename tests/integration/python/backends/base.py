from __future__ import annotations

import json
import re
import socket
import shutil
import subprocess
import tempfile
import zipfile
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
    build_order_mode: str = "normal"
    build_order_seed: int | None = None
    extra_mod_paths: tuple[Path, ...] = ()
    aai_mode_override: str | None = None
    pbe_energy_preset_override: str | None = None
    scenario_filter: str | None = None
    mod_zip: Path | None = None
    restart_at_tick: int | None = None


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
        ignored = {".git", ".vscode", ".idea", "__pycache__", ".pytest_cache", "releases", "dist"}
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



def _read_mod_name_from_info_json_bytes(payload: bytes) -> str | None:
    try:
        parsed = json.loads(payload.decode("utf-8-sig"))
    except Exception:
        return None
    if not isinstance(parsed, dict):
        return None
    name = parsed.get("name")
    if isinstance(name, str) and name.strip() != "":
        return name.strip()
    return None


def _read_mod_name_from_directory(mod_dir: Path) -> str | None:
    info_path = mod_dir / "info.json"
    if not info_path.exists():
        return None
    try:
        payload = info_path.read_bytes()
    except Exception:
        return None
    return _read_mod_name_from_info_json_bytes(payload)


def _read_mod_name_from_zip(mod_archive: Path) -> str | None:
    try:
        with zipfile.ZipFile(mod_archive, "r") as archive:
            candidates = [name for name in archive.namelist() if name.endswith("/info.json") or name == "info.json"]
            if not candidates:
                return None
            candidates.sort(key=len)
            payload = archive.read(candidates[0])
    except Exception:
        return None
    return _read_mod_name_from_info_json_bytes(payload)


def _infer_mod_name_from_path(mod_path: Path) -> str:
    stem = mod_path.stem if mod_path.is_file() else mod_path.name
    match = re.match(r"^(.+?)_\d+\.\d+.*$", stem)
    if match:
        return match.group(1)
    return stem


def _stage_external_mods(extra_mod_paths: tuple[Path, ...], mods_dir: Path) -> list[str]:
    staged_mod_names: list[str] = []
    seen_names: set[str] = set()

    for raw_path in extra_mod_paths:
        mod_path = Path(raw_path).expanduser().resolve()
        if not mod_path.exists():
            raise FileNotFoundError(f"Extra mod path does not exist: {mod_path}")

        if mod_path.is_dir():
            destination = mods_dir / mod_path.name
            if destination.exists():
                raise RuntimeError(f"Duplicate staged mod directory name: {destination.name}")
            shutil.copytree(mod_path, destination, dirs_exist_ok=False)
            mod_name = _read_mod_name_from_directory(mod_path)
        else:
            destination = mods_dir / mod_path.name
            if destination.exists():
                raise RuntimeError(f"Duplicate staged mod archive name: {destination.name}")
            shutil.copy2(mod_path, destination)
            mod_name = _read_mod_name_from_zip(mod_path)

        if mod_name is None:
            mod_name = _infer_mod_name_from_path(mod_path)

        if mod_name not in seen_names:
            staged_mod_names.append(mod_name)
            seen_names.add(mod_name)

    return staged_mod_names


def _stage_aai_mode_override_mod(mods_dir: Path, aai_mode_override: str | None) -> str | None:
    if aai_mode_override not in {"lubricated", "expensive"}:
        return None

    mod_name = "PBEAAILoadersModeOverride"
    mod_dir = mods_dir / f"{mod_name}_0.1.0"
    mod_dir.mkdir(parents=True, exist_ok=False)

    info = {
        "name": mod_name,
        "version": "0.1.0",
        "title": "PBE AAI Loaders Mode Override",
        "author": "PoweredBeltsExtended Tests",
        "factorio_version": "2.1",
        "dependencies": ["base", "? aai-loaders"],
    }
    (mod_dir / "info.json").write_text(json.dumps(info, indent=2), encoding="utf-8")

    settings_updates = (
        "local setting = data.raw[\"string-setting\"] and data.raw[\"string-setting\"][\"aai-loaders-mode\"]\n"
        "if setting then\n"
        f"  setting.default_value = {json.dumps(aai_mode_override)}\n"
        "end\n"
    )
    (mod_dir / "settings-updates.lua").write_text(settings_updates, encoding="utf-8")

    return mod_name


def _stage_pbe_energy_preset_override_mod(mods_dir: Path, pbe_energy_preset_override: str | None, acceptance: bool = False) -> str | None:
    if pbe_energy_preset_override not in {"default", "synchronized", "responsive", "custom"} and not acceptance:
        return None

    mod_name = "PBEEnergyPresetOverride"
    mod_dir = mods_dir / f"{mod_name}_0.1.0"
    mod_dir.mkdir(parents=True, exist_ok=False)

    info = {
        "name": mod_name,
        "version": "0.1.0",
        "title": "PBE Energy Preset Override",
        "author": "PoweredBeltsExtended Tests",
        "factorio_version": "2.1",
        "dependencies": ["base", "? PoweredBeltsExtended"],
    }
    (mod_dir / "info.json").write_text(json.dumps(info, indent=2), encoding="utf-8")

    settings_updates = (
        "local setting = data.raw[\"string-setting\"] and data.raw[\"string-setting\"][\"powered-belts-energy-behavior-preset\"]\n"
        "if setting then\n"
        f"  setting.default_value = {json.dumps(pbe_energy_preset_override or 'default')}\n"
        "end\n"
    )
    if acceptance and pbe_energy_preset_override is not None:
        # Runtime settings belong to PBE; the companion cannot write them at runtime.
        # Override prototype defaults in the isolated settings stage instead.
        settings_updates += '\nlocal ops = data.raw["int-setting"]["powered-belts-operations-per-tick"]; if ops then ops.default_value = 128 end\n'
    if pbe_energy_preset_override == "custom":
        for name, value in {"powered-belts-required-energy-percentage": 50,
                            "powered-belts-required-energy-percentage-flat": 10,
                            "powered-belts-required-energy-hysteresis-percentage": 20}.items():
            settings_updates += f'\nlocal s = data.raw["int-setting"][{json.dumps(name)}]; if s then s.default_value = {value} end\n'
    (mod_dir / "settings-updates.lua").write_text(settings_updates, encoding="utf-8")
    return mod_name

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
    (user_data_dir / "saves").mkdir(parents=True, exist_ok=True)

    if config.powered_belts_enabled:
        if config.mod_zip is not None:
            archive = config.mod_zip.resolve()
            with zipfile.ZipFile(archive) as candidate:
                names = candidate.namelist()
                if candidate.testzip() is not None or any("\\" in n or n.startswith("/") or ".." in Path(n).parts for n in names):
                    raise ValueError("Invalid/nonportable candidate ZIP paths or CRC")
                infos = [n for n in names if n.count("/") == 1 and n.endswith("/info.json")]
                if len(infos) != 1 or _read_mod_name_from_info_json_bytes(candidate.read(infos[0])) != "PoweredBeltsExtended":
                    raise ValueError("Candidate ZIP must contain one mod-root directory")
            shutil.copy2(archive, mods_dir / archive.name)
        else:
            mod_dest = mods_dir / "PoweredBeltsExtended"
            shutil.copytree(config.repo_root, mod_dest, ignore=_make_ignore_copy(artifacts_dir), dirs_exist_ok=False)

    harness_source = config.repo_root / "tests" / "integration" / "harness_mod"
    harness_dest = mods_dir / "PBEIntegrationHarness_0.1.0"
    shutil.copytree(harness_source, harness_dest, dirs_exist_ok=False)

    build_order_mode = config.build_order_mode if config.build_order_mode in {"normal", "reversed", "random"} else "normal"
    build_order_seed = config.build_order_seed if isinstance(config.build_order_seed, int) else None
    harness_build_order_config = (
        "local M = {}\n"
        f"M.default_mode = {json.dumps(build_order_mode)}\n"
        f"M.default_seed = {json.dumps(build_order_seed)}\n"
        f"M.scenario_filter = {json.dumps(config.scenario_filter)}\n"
        f"M.checkpoint_tick = {config.restart_at_tick or 0}\n"
        "return M\n"
    )
    (harness_dest / "lib" / "build_order_config.lua").write_text(harness_build_order_config, encoding="utf-8")    staged_external_mod_names = _stage_external_mods(config.extra_mod_paths, mods_dir)
    aai_mode_override_mod = _stage_aai_mode_override_mod(mods_dir, config.aai_mode_override)
    if aai_mode_override_mod is not None:
        staged_external_mod_names.append(aai_mode_override_mod)
    pbe_energy_preset_override_mod = _stage_pbe_energy_preset_override_mod(mods_dir, config.pbe_energy_preset_override, config.mod_zip is not None)
    if pbe_energy_preset_override_mod is not None:
        staged_external_mod_names.append(pbe_energy_preset_override_mod)

    mod_entries: list[dict[str, object]] = []
    enabled_mod_names: set[str] = set()

    def add_enabled_mod(name: str) -> None:
        if name in enabled_mod_names:
            return
        mod_entries.append({"name": name, "enabled": True})
        enabled_mod_names.add(name)

    add_enabled_mod("base")
    if config.powered_belts_enabled:
        add_enabled_mod("PoweredBeltsExtended")
    for mod_name in staged_external_mod_names:
        add_enabled_mod(mod_name)
    add_enabled_mod("PBEIntegrationHarness")

    # Unlisted bundled expansion modules otherwise default to enabled.
    for name in ("space-age", "quality", "elevated-rails"):
        if name not in enabled_mod_names:
            mod_entries.append({"name": name, "enabled": False})
    mod_list = {"mods": mod_entries}
    (mods_dir / "mod-list.json").write_text(json.dumps(mod_list, indent=2), encoding="utf-8")

    data_dir = config.factorio_bin.resolve().parents[2] / "data"
    config_path.write_text("[path]\nread-data=" + data_dir.as_posix() + "\nwrite-data=" + user_data_dir.as_posix() + "\n", encoding="utf-8")
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
