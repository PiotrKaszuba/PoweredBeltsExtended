from __future__ import annotations

import os
from pathlib import Path

import pytest

from .backends.base import RunConfig
from .run_integration import run_suite


@pytest.fixture(scope="session")
def suite_result():
    factorio_bin_raw = os.environ.get("FACTORIO_BIN")
    if not factorio_bin_raw:
        pytest.skip("FACTORIO_BIN is not set")
    factorio_bin = Path(factorio_bin_raw)
    if not factorio_bin.exists():
        pytest.skip(f"Factorio binary not found: {factorio_bin}")

    repo_root = Path(__file__).resolve().parents[3]
    artifacts_dir = repo_root / "tests" / "artifacts"
    config = RunConfig(
        factorio_bin=factorio_bin,
        repo_root=repo_root,
        artifacts_dir=artifacts_dir,
        timeout_seconds=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "900")),
        until_tick=int(os.environ.get("PBE_TEST_UNTIL_TICK", "9000")),
    )
    backend = os.environ.get("PBE_TEST_BACKEND", "cli")
    return run_suite(config, backend_name=backend)


def test_suite_has_scenarios(suite_result):
    assert suite_result.summary.total > 0
    assert len(suite_result.scenarios) == suite_result.summary.total


def test_blocking_scenarios_pass(suite_result):
    assert suite_result.summary.blocking_failed == 0
