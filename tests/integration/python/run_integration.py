from __future__ import annotations

import argparse
from dataclasses import replace
import json
import os
import shutil
import sys
from pathlib import Path

from .backends import cli_backend, rcon_backend
from .backends.base import RunConfig
from .models import SuiteResult
from .reporting import summarize_suite, write_summary


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
    return parser.parse_args()


def run_suite(config: RunConfig, backend_name: str) -> SuiteResult:
    if backend_name == "rcon":
        result_path = rcon_backend.run(config)
    else:
        result_path = cli_backend.run(config)
    raw = result_path.read_text(encoding="utf-8")
    return SuiteResult.model_validate(json.loads(raw))


def _format_mode_title(mode: str) -> str:
    return f"=== PoweredBeltsExtended {mode.upper()} ==="


def _run_modes(base_config: RunConfig, backend_name: str, mod_state: str) -> dict[str, SuiteResult]:
    modes: list[tuple[str, bool]]
    if mod_state == "enabled":
        modes = [("enabled", True)]
    elif mod_state == "disabled":
        modes = [("disabled", False)]
    else:
        modes = [("enabled", True), ("disabled", False)]

    results: dict[str, SuiteResult] = {}
    for mode_name, enabled in modes:
        mode_config = replace(base_config, powered_belts_enabled=enabled)
        results[mode_name] = run_suite(mode_config, backend_name=backend_name)
    return results


def main() -> int:
    args = parse_args()
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
        results_json_path.write_text(only_result.model_dump_json(indent=2), encoding="utf-8")
        write_summary(only_result, summary_path)
        print(summarize_suite(only_result))
        blocking_failed_total = only_result.summary.blocking_failed
        return 1 if blocking_failed_total > 0 else 0

    aggregate_payload = {mode: result.model_dump(mode="json") for mode, result in suite_results.items()}
    results_json_path.write_text(json.dumps(aggregate_payload, indent=2), encoding="utf-8")

    summary_sections: list[str] = []
    blocking_failed_total = 0
    for mode_name in ("enabled", "disabled"):
        if mode_name not in suite_results:
            continue
        result = suite_results[mode_name]
        mode_summary_path = artifacts_dir / f"integration-summary-{mode_name}.txt"
        mode_results_path = artifacts_dir / f"integration-results-{mode_name}.json"
        mode_results_path.write_text(result.model_dump_json(indent=2), encoding="utf-8")
        write_summary(result, mode_summary_path)
        summary_sections.append(_format_mode_title(mode_name))
        summary_sections.append(summarize_suite(result).rstrip("\n"))
        blocking_failed_total += result.summary.blocking_failed

    combined_summary = "\n\n".join(summary_sections) + "\n"
    summary_path.write_text(combined_summary, encoding="utf-8")
    print(combined_summary, end="")

    return 1 if blocking_failed_total > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
