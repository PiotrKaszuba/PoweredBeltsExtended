from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class AssertionResult(BaseModel):
    checkpoint_tick: int
    type: str
    blocking: bool
    passed: bool
    expected_failure: bool = False
    message: str = ""
    extra: dict[str, Any] | None = None


class ScenarioResult(BaseModel):
    id: str
    blocking: bool
    start_tick: int
    end_tick: int
    duration_ticks: int
    has_any_failed: bool
    has_blocking_failed: bool
    blocking_failed_count: int
    non_blocking_failed_count: int
    expected_non_blocking_failed_count: int = 0
    passed: bool
    assertions: list[AssertionResult] = Field(default_factory=list)


class SuiteSummary(BaseModel):
    total: int
    passed: int
    failed: int
    blocking_failed: int
    non_blocking_failed: int
    expected_non_blocking_failed: int = 0


class SuiteResult(BaseModel):
    run_started_tick: int
    run_finished_tick: int | None = None
    scenarios: list[ScenarioResult] = Field(default_factory=list)
    summary: SuiteSummary
