from __future__ import annotations

from pathlib import Path

from .models import SuiteResult


def summarize_suite(result: SuiteResult) -> str:
    lines: list[str] = []
    lines.append("PBE Integration Suite")
    lines.append(f"Started tick: {result.run_started_tick}")
    lines.append(f"Finished tick: {result.run_finished_tick}")
    lines.append(
        "Summary: "
        f"total={result.summary.total}, "
        f"passed={result.summary.passed}, "
        f"failed={result.summary.failed}, "
        f"blocking_failed={result.summary.blocking_failed}, "
        f"non_blocking_failed={result.summary.non_blocking_failed}, "
        f"expected_non_blocking_failed={result.summary.expected_non_blocking_failed}"
    )
    for scenario in result.scenarios:
        status = "PASS" if scenario.passed else "FAIL"
        lines.append(
            f"- {scenario.id}: {status} "
            f"(blocking_failed={scenario.blocking_failed_count}, "
            f"non_blocking_failed={scenario.non_blocking_failed_count}, "
            f"expected_non_blocking_failed={scenario.expected_non_blocking_failed_count})"
        )
        failed_assertions = [assertion for assertion in scenario.assertions if not assertion.passed]
        for assertion in failed_assertions:
            message = assertion.message or ""
            expected_suffix = " expected=True" if assertion.expected_failure else ""
            lines.append(
                f"  - tick={assertion.checkpoint_tick} "
                f"type={assertion.type} "
                f"blocking={assertion.blocking} "
                f"message={message}{expected_suffix}"
            )
    return "\n".join(lines) + "\n"


def write_summary(result: SuiteResult, summary_path: Path) -> None:
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(summarize_suite(result), encoding="utf-8")
