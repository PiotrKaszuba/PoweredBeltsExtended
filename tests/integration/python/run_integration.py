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
    parser.add_argument("--backend", choices=("cli", "rcon"), default=os.environ.get("PBE_TEST_BACKEND", "cli"))
    parser.add_argument(
        "--mod-state",
        choices=("enabled", "disabled", "both"),
        default=os.environ.get("PBE_TEST_MOD_STATE", "both"),
        help="Run with PoweredBeltsExtended enabled, disabled, or both.",
    )
    parser.add_argument("--factorio-bin", type=Path, default=None, help="Path to factorio executable.")
    parser.add_argument("--artifacts-dir", type=Path, default=None, help="Artifacts output directory.")
    parser.add_argument("--until-tick", type=int, default=int(os.environ.get("PBE_TEST_UNTIL_TICK", "20000")))
    parser.add_argument("--timeout-seconds", type=int, default=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "60")))
    parser.add_argument(
        "--remove-runtime-dir-on-exit",
        choices=("true", "false"),
        default=os.environ.get("PBE_TEST_REMOVE_RUNTIME_DIR_ON_EXIT", "true"),
        help="Remove temporary staged runtime directory after each run (default: true).",
    )
    return parser.parse_args()


def _parse_bool_option(name: str, value: str) -> bool:
    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise ValueError(f"Invalid value for {name}: {value!r}. Expected 'true' or 'false'.")


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


def _run_modes(base_config: RunConfig, backend_name: str, mod_state: str) -> dict[str, dict[str, Any]]:
    modes: list[tuple[str, bool]]
    if mod_state == "enabled":
        modes = [("enabled", True)]
    elif mod_state == "disabled":
        modes = [("disabled", False)]
    else:
        modes = [("enabled", True), ("disabled", False)]

    results: dict[str, dict[str, Any]] = {}
    for mode_name, enabled in modes:
        mode_config = replace(base_config, powered_belts_enabled=enabled)
        results[mode_name] = run_suite(mode_config, backend_name=backend_name)
    return results


def main() -> int:
    args = parse_args()
    try:
        remove_runtime_dir_on_exit = _parse_bool_option("--remove-runtime-dir-on-exit", args.remove_runtime_dir_on_exit)
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
    )

    try:
        suite_results = _run_modes(config, backend_name=args.backend, mod_state=args.mod_state)
    except Exception as exc:
        print(f"Integration run failed: {exc}", file=sys.stderr)
        return 3

    results_json_path = artifacts_dir / "integration-results.json"
    summary_path = artifacts_dir / "integration-summary.txt"

    if len(suite_results) == 1:
        only_result = next(iter(suite_results.values()))
        results_json_path.write_text(json.dumps(only_result, indent=2), encoding="utf-8")
        write_summary(only_result, summary_path)
        print(summarize_suite(only_result))
        failed_total = _suite_summary(only_result)["failed"]
        return 1 if failed_total > 0 else 0

    results_json_path.write_text(json.dumps(suite_results, indent=2), encoding="utf-8")

    summary_sections: list[str] = []
    failed_total = 0
    for mode_name in ("enabled", "disabled"):
        if mode_name not in suite_results:
            continue
        result = suite_results[mode_name]
        mode_summary_path = artifacts_dir / f"integration-summary-{mode_name}.txt"
        mode_results_path = artifacts_dir / f"integration-results-{mode_name}.json"
        mode_results_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        write_summary(result, mode_summary_path)
        summary_sections.append(_format_mode_title(mode_name))
        summary_sections.append(summarize_suite(result).rstrip("\n"))
        failed_total += _suite_summary(result)["failed"]

    combined_summary = "\n\n".join(summary_sections) + "\n"
    summary_path.write_text(combined_summary, encoding="utf-8")
    print(combined_summary, end="")

    return 1 if failed_total > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
