from __future__ import annotations

import argparse
from dataclasses import replace
import json
import os
import sys
from pathlib import Path
from typing import Any

from .backends import cli_backend, rcon_backend
from .backends.base import RunConfig, cleanup_runtime_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Powered Belts Extended integration suite.")
    default_extra_mod_paths = [
        value.strip()
        for value in os.environ.get("PBE_TEST_EXTRA_MOD_PATHS", "").split(",")
        if value.strip()
    ]
    parser.add_argument("--backend", choices=("cli", "rcon"), default=os.environ.get("PBE_TEST_BACKEND", "cli"))
    parser.add_argument(
        "--mod-state",
        choices=("enabled", "disabled", "both"),
        default=os.environ.get("PBE_TEST_MOD_STATE", "both"),
        help="Run with PoweredBeltsExtended enabled, disabled, or both.",
    )
    parser.add_argument("--factorio-bin", type=Path, default=None, help="Path to factorio executable.")
    parser.add_argument("--artifacts-dir", type=Path, default=None, help="Artifacts output directory.")
    parser.add_argument("--until-tick", type=int, default=int(os.environ.get("PBE_TEST_UNTIL_TICK", "50000")))
    parser.add_argument("--timeout-seconds", type=int, default=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "100")))
    parser.add_argument(
        "--build-order-modes",
        default=os.environ.get("PBE_TEST_BUILD_ORDER_MODES", "normal,reversed"),
        help="Comma-separated build order modes for PoweredBeltsExtended-enabled runs: normal,reversed,random.",
    )
    parser.add_argument(
        "--build-order-random-seeds",
        default=os.environ.get("PBE_TEST_BUILD_ORDER_RANDOM_SEEDS", ""),
        help="Comma-separated seeds used when random build order mode is requested.",
    )
    parser.add_argument(
        "--remove-runtime-dir-on-exit",
        choices=("true", "false"),
        default=os.environ.get("PBE_TEST_REMOVE_RUNTIME_DIR_ON_EXIT", "true"),
        help="Remove temporary staged runtime directory after each run (default: true).",
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
        default=os.environ.get("PBE_TEST_AAI_MODE", "default"),
        help="Optional AAI Loaders startup mode override for staged runs.",
    )
    parser.add_argument(
        "--run-timing-suite",
        choices=("true", "false"),
        default=os.environ.get("PBE_TEST_RUN_TIMING_SUITE", "true"),
        help="Run isolated timing scenarios after the main suite (default: true).",
    )
    parser.add_argument(
        "--timing-presets",
        default=os.environ.get("PBE_TEST_TIMING_PRESETS", "default,synchronized,responsive"),
        help="Comma-separated preset list for timing runs: default,synchronized,responsive.",
    )
    parser.add_argument(
        "--timing-build-order-modes",
        default=os.environ.get("PBE_TEST_TIMING_BUILD_ORDER_MODES", "normal,reversed"),
        help="Comma-separated build order modes for timing runs: normal,reversed.",
    )
    return parser.parse_args()


def _parse_bool_option(name: str, value: str) -> bool:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise ValueError(f"Invalid value for {name}: {value!r}. Expected 'true' or 'false'.")


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


def _suite_summary(result: dict[str, Any]) -> dict[str, int]:
    summary = result.get("summary")
    if not isinstance(summary, dict):
        summary = {}
    scenarios = result.get("scenarios")
    if not isinstance(scenarios, list):
        scenarios = []

    def _to_int(value: Any, default: int = 0) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    total = _to_int(summary.get("total"), len(scenarios))
    passed = _to_int(summary.get("passed"), 0)
    failed = _to_int(summary.get("failed"), 0)
    return {
        "total": total,
        "passed": passed,
        "failed": failed,
    }


def summarize_suite(result: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append("PBE Integration Suite")
    lines.append(f"Started tick: {result.get('run_started_tick')}")
    lines.append(f"Finished tick: {result.get('run_finished_tick')}")
    summary = _suite_summary(result)
    lines.append(
        "Summary: "
        f"total={summary['total']}, "
        f"passed={summary['passed']}, "
        f"failed={summary['failed']}"
    )
    if summary["failed"] == 0:
        lines.append("ALL PASS")

    scenarios = result.get("scenarios")
    if not isinstance(scenarios, list):
        scenarios = []
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        assertions = scenario.get("assertions")
        if not isinstance(assertions, list):
            assertions = []
        failed_assertions = [assertion for assertion in assertions if isinstance(assertion, dict) and not assertion.get("passed", False)]
        failed_count = scenario.get("failed_count")
        if not isinstance(failed_count, int):
            failed_count = len(failed_assertions)
        expected_failed_assertions = scenario.get("expected_failed_assertions")
        if not isinstance(expected_failed_assertions, int):
            expected_failed_assertions = 0
        status = "PASS" if scenario.get("passed", False) else "FAIL"
        counts_text = f"failed_assertions={failed_count}"
        if expected_failed_assertions > 0:
            counts_text += f", expected_failed_assertions={expected_failed_assertions}"
        lines.append(
            f"- {scenario.get('id')}: {status} "
            f"({counts_text})"
        )
        for assertion in failed_assertions:
            lines.append(
                f"  - tick={assertion.get('checkpoint_tick')} "
                f"type={assertion.get('type')} "
                f"message={assertion.get('message', '')}"
            )
    return "\n".join(lines) + "\n"


def write_summary(result: dict[str, Any], summary_path: Path) -> None:
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(summarize_suite(result), encoding="utf-8")


def run_suite(config: RunConfig, backend_name: str) -> dict[str, Any]:
    if backend_name == "rcon":
        run_result = rcon_backend.run(config)
    else:
        run_result = cli_backend.run(config)
    try:
        raw = run_result.result_file.read_text(encoding="utf-8")
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise RuntimeError(f"Integration result payload must be a JSON object: {run_result.result_file}")
        return parsed
    finally:
        if config.remove_runtime_dir_on_exit:
            try:
                cleanup_runtime_dir(run_result.runtime_root)
            except Exception as exc:
                print(f"Warning: failed to remove runtime directory {run_result.runtime_root}: {exc}", file=sys.stderr)


def _format_mode_title(mode: str) -> str:
    return f"=== PoweredBeltsExtended {mode.upper()} ==="


def _parse_build_order_modes(raw: str) -> list[str]:
    modes: list[str] = []
    seen: set[str] = set()
    for part in raw.split(","):
        normalized = part.strip().lower()
        if normalized == "":
            continue
        if normalized == "reverse":
            normalized = "reversed"
        if normalized not in {"normal", "reversed", "random"}:
            raise ValueError(f"Invalid build order mode: {part!r}")
        if normalized in seen:
            continue
        seen.add(normalized)
        modes.append(normalized)
    if not modes:
        raise ValueError("At least one build order mode is required")
    return modes


def _parse_build_order_random_seeds(raw: str) -> list[int]:
    seeds: list[int] = []
    for part in raw.split(","):
        trimmed = part.strip()
        if trimmed == "":
            continue
        seeds.append(int(trimmed))
    return seeds


def _parse_timing_presets(raw: str) -> list[str]:
    presets: list[str] = []
    seen: set[str] = set()
    for part in raw.split(","):
        preset = part.strip().lower()
        if preset == "":
            continue
        if preset not in {"default", "synchronized", "responsive"}:
            raise ValueError(f"Invalid timing preset: {part!r}")
        if preset in seen:
            continue
        seen.add(preset)
        presets.append(preset)
    if not presets:
        raise ValueError("At least one timing preset is required when timing suite is enabled")
    return presets


def _parse_timing_build_order_modes(raw: str) -> list[str]:
    modes: list[str] = []
    seen: set[str] = set()
    for part in raw.split(","):
        mode = part.strip().lower()
        if mode == "":
            continue
        if mode == "reverse":
            mode = "reversed"
        if mode not in {"normal", "reversed"}:
            raise ValueError(f"Invalid timing build order mode: {part!r}")
        if mode in seen:
            continue
        seen.add(mode)
        modes.append(mode)
    if not modes:
        raise ValueError("At least one timing build order mode is required when timing suite is enabled")
    return modes


def _build_enabled_variants(modes: list[str], random_seeds: list[int]) -> list[tuple[str, str, int | None]]:
    variants: list[tuple[str, str, int | None]] = []
    for mode in modes:
        if mode == "random":
            if random_seeds:
                for seed in random_seeds:
                    variants.append((f"enabled-random-seed-{seed}", mode, seed))
            else:
                variants.append(("enabled-random", mode, None))
            continue
        variants.append((f"enabled-{mode}", mode, None))
    return variants


def _print_partial_result(run_label: str, result: dict[str, Any]) -> None:
    summary = _suite_summary(result)
    print(
        f"[partial] {run_label}: total={summary['total']} "
        f"passed={summary['passed']} failed={summary['failed']}",
        flush=True,
    )
    print(_format_mode_title(run_label), flush=True)
    print(summarize_suite(result), end="", flush=True)


def _run_modes(
    base_config: RunConfig,
    backend_name: str,
    mod_state: str,
    build_order_modes: list[str],
    build_order_random_seeds: list[int],
) -> list[tuple[str, dict[str, Any]]]:
    modes: list[tuple[str, bool, str, int | None]]
    if mod_state == "enabled":
        modes = [(label, True, mode, seed) for label, mode, seed in _build_enabled_variants(build_order_modes, build_order_random_seeds)]
    elif mod_state == "disabled":
        modes = [("disabled", False, "normal", None)]
    else:
        enabled_variants = [(label, True, mode, seed) for label, mode, seed in _build_enabled_variants(build_order_modes, build_order_random_seeds)]
        modes = [*enabled_variants, ("disabled", False, "normal", None)]

    results: list[tuple[str, dict[str, Any]]] = []
    for run_label, enabled, build_order_mode, build_order_seed in modes:
        mode_config = replace(
            base_config,
            powered_belts_enabled=enabled,
            build_order_mode=build_order_mode,
            build_order_seed=build_order_seed,
        )
        result = run_suite(mode_config, backend_name=backend_name)
        results.append((run_label, result))
        _print_partial_result(run_label, result)
    return results


def _extract_timing_telemetry(run_label: str, result: dict[str, Any]) -> dict[str, Any]:
    scenarios = result.get("scenarios")
    if not isinstance(scenarios, list):
        scenarios = []

    telemetry_scenarios: list[dict[str, Any]] = []
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        timing_report = scenario.get("timing_probe_report")
        if not isinstance(timing_report, dict):
            continue
        phases = timing_report.get("phases")
        if not isinstance(phases, dict):
            phases = {}
        down_phase = phases.get("down") if isinstance(phases.get("down"), dict) else {}
        up_phase = phases.get("up") if isinstance(phases.get("up"), dict) else {}
        telemetry_scenarios.append(
            {
                "id": scenario.get("id"),
                "passed": scenario.get("passed"),
                "down_ticks": timing_report.get("down_ticks"),
                "up_ticks": timing_report.get("up_ticks"),
                "down_spread": down_phase.get("spread"),
                "up_spread": up_phase.get("spread"),
                "down_deltas": down_phase.get("deltas"),
                "up_deltas": up_phase.get("deltas"),
            }
        )

    return {
        "run_label": run_label,
        "summary": _suite_summary(result),
        "scenarios": telemetry_scenarios,
    }


def _run_timing_modes(
    base_config: RunConfig,
    backend_name: str,
    timing_presets: list[str],
    timing_build_order_modes: list[str],
    artifacts_dir: Path,
) -> list[tuple[str, dict[str, Any]]]:
    timing_results: list[tuple[str, dict[str, Any]]] = []
    combined_telemetry: dict[str, Any] = {}

    for preset in timing_presets:
        for build_order_mode in timing_build_order_modes:
            run_label = f"timing-{preset}-{build_order_mode}"
            mode_config = replace(
                base_config,
                powered_belts_enabled=True,
                build_order_mode=build_order_mode,
                build_order_seed=None,
                pbe_energy_preset_override=preset,
                scenario_filter=f"timing_preset_{preset}",
            )
            result = run_suite(mode_config, backend_name=backend_name)
            timing_results.append((run_label, result))
            _print_partial_result(run_label, result)
            telemetry = _extract_timing_telemetry(run_label, result)
            combined_telemetry[run_label] = telemetry
            (artifacts_dir / f"timing-telemetry-{run_label}.json").write_text(json.dumps(telemetry, indent=2), encoding="utf-8")

    (artifacts_dir / "timing-telemetry.json").write_text(json.dumps(combined_telemetry, indent=2), encoding="utf-8")
    return timing_results


def main() -> int:
    args = parse_args()
    try:
        remove_runtime_dir_on_exit = _parse_bool_option("--remove-runtime-dir-on-exit", args.remove_runtime_dir_on_exit)
        run_timing_suite = _parse_bool_option("--run-timing-suite", args.run_timing_suite)
        build_order_modes = _parse_build_order_modes(args.build_order_modes)
        build_order_random_seeds = _parse_build_order_random_seeds(args.build_order_random_seeds)
        extra_mod_paths = _parse_extra_mod_paths(args.extra_mod_path)
        aai_mode_override = None if args.aai_mode == "default" else args.aai_mode
        timing_presets = _parse_timing_presets(args.timing_presets) if run_timing_suite else []
        timing_build_order_modes = _parse_timing_build_order_modes(args.timing_build_order_modes) if run_timing_suite else []
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    repo_root = Path(__file__).resolve().parents[3]
    factorio_bin = args.factorio_bin or (Path(os.environ["FACTORIO_BIN"]) if "FACTORIO_BIN" in os.environ else None)
    if factorio_bin is None:
        print("Missing Factorio binary. Set FACTORIO_BIN or pass --factorio-bin.", file=sys.stderr)
        return 2
    if not factorio_bin.exists():
        print(f"Factorio binary does not exist: {factorio_bin}", file=sys.stderr)
        return 2

    artifacts_dir = args.artifacts_dir or (repo_root / "tests" / "artifacts")
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    config = RunConfig(
        factorio_bin=factorio_bin,
        repo_root=repo_root,
        artifacts_dir=artifacts_dir,
        timeout_seconds=args.timeout_seconds,
        until_tick=args.until_tick,
        remove_runtime_dir_on_exit=remove_runtime_dir_on_exit,
        extra_mod_paths=extra_mod_paths,
        aai_mode_override=aai_mode_override,
    )

    try:
        main_results = _run_modes(
            config,
            backend_name=args.backend,
            mod_state=args.mod_state,
            build_order_modes=build_order_modes,
            build_order_random_seeds=build_order_random_seeds,
        )
        timing_results: list[tuple[str, dict[str, Any]]] = []
        if run_timing_suite and args.mod_state != "disabled":
            timing_results = _run_timing_modes(
                config,
                backend_name=args.backend,
                timing_presets=timing_presets,
                timing_build_order_modes=timing_build_order_modes,
                artifacts_dir=artifacts_dir,
            )
        suite_results = [*main_results, *timing_results]
    except Exception as exc:
        print(f"Integration run failed: {exc}", file=sys.stderr)
        return 3

    results_json_path = artifacts_dir / "integration-results.json"
    summary_path = artifacts_dir / "integration-summary.txt"

    if len(suite_results) == 1:
        only_result = suite_results[0][1]
        results_json_path.write_text(json.dumps(only_result, indent=2), encoding="utf-8")
        write_summary(only_result, summary_path)
        failed_total = _suite_summary(only_result)["failed"]
        return 1 if failed_total > 0 else 0

    results_json_path.write_text(json.dumps({label: result for label, result in suite_results}, indent=2), encoding="utf-8")

    summary_sections: list[str] = []
    failed_total = 0
    for run_label, result in suite_results:
        mode_summary_path = artifacts_dir / f"integration-summary-{run_label}.txt"
        mode_results_path = artifacts_dir / f"integration-results-{run_label}.json"
        mode_results_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        write_summary(result, mode_summary_path)
        summary_sections.append(_format_mode_title(run_label))
        summary_sections.append(summarize_suite(result).rstrip("\n"))
        failed_total += _suite_summary(result)["failed"]

    combined_summary = "\n\n".join(summary_sections) + "\n"
    summary_path.write_text(combined_summary, encoding="utf-8")

    return 1 if failed_total > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
