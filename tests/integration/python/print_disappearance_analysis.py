from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print detailed disappearance diagnostics from existing analysis/snapshot files."
    )
    parser.add_argument(
        "analysis_json",
        nargs="?",
        type=Path,
        default=None,
        help="Path to item-disappearance-analysis-<scenario>.json",
    )
    parser.add_argument("--scenario-id", type=str, default=None, help="Scenario id to resolve from artifacts dir.")
    parser.add_argument("--artifacts-dir", type=Path, default=None)
    parser.add_argument("--max-locations", type=int, default=12)
    parser.add_argument("--include-unresolved", choices=("true", "false"), default="true")
    return parser.parse_args()


def _format_loss_items(loss: dict[str, int]) -> str:
    if not loss:
        return "(none)"
    items = sorted(((name, int(count)) for name, count in loss.items()), key=lambda it: (-it[1], it[0]))
    return ", ".join(f"{name} x{count}" for name, count in items)


def _compact_action(action: dict[str, Any]) -> str:
    compact: dict[str, Any] = {
        "tick": int(action.get("tick", 0) or 0),
        "type": action.get("type"),
    }
    for key in ("target_ref", "target_refs", "target_name", "name", "item_name", "mode", "position"):
        if key in action:
            compact[key] = action.get(key)
    if isinstance(action.get("stacks"), list):
        compact["stacks"] = f"{len(action['stacks'])} entries"
    if isinstance(action.get("orders"), list):
        compact["orders"] = f"{len(action['orders'])} entries"
    return json.dumps(compact, separators=(",", ":"), sort_keys=False)


def _print_nearest_actions(context: dict[str, list[dict[str, Any]]], prefix: str = "") -> None:
    for label, key in (("at", "at_tick"), ("before", "before"), ("after", "after")):
        actions = context.get(key) or []
        if not actions:
            print(f"{prefix}{label}: (none)")
            continue
        for action in actions:
            print(f"{prefix}{label}: {_compact_action(action)}")


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _run_tick_from_name(path: Path) -> tuple[int, int] | None:
    m = re.search(r"-run(\d+)-tick(\d+)\.json$", path.name)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def _find_snapshot(
    runtime_script_output: Path,
    scenario_id: str,
    tick: int,
    *,
    preferred_run: int | None = None,
) -> Path | None:
    if preferred_run is not None:
        exact = runtime_script_output / f"pbe-chain-scan-{scenario_id}-run{preferred_run}-tick{tick}.json"
        if exact.exists():
            return exact

    candidates = list(runtime_script_output.glob(f"pbe-chain-scan-{scenario_id}-run*-tick{tick}.json"))
    if not candidates:
        return None
    candidates.sort(key=lambda p: (_run_tick_from_name(p) or (-1, -1))[0])
    return candidates[-1]


def _entry_state(entry: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(entry, dict):
        return {}
    out: dict[str, Any] = {}
    for key in ("entity_id", "name", "type", "position", "counts", "hand", "transport_lines", "ground_stack"):
        if key in entry:
            out[key] = entry.get(key)
    return out


def _detailed_location_loss(
    prev_snapshot: dict[str, Any],
    curr_snapshot: dict[str, Any],
    include_items: set[str] | None = None,
) -> list[dict[str, Any]]:
    prev_locs = prev_snapshot.get("locations") or {}
    curr_locs = curr_snapshot.get("locations") or {}
    details: list[dict[str, Any]] = []
    for location, prev_entry in prev_locs.items():
        if not isinstance(prev_entry, dict):
            continue
        curr_entry = curr_locs.get(location) or {}
        prev_counts = prev_entry.get("counts") or {}
        curr_counts = curr_entry.get("counts") or {}
        for item_name, prev_count in prev_counts.items():
            if include_items is not None and item_name not in include_items:
                continue
            prev_int = int(prev_count)
            curr_int = int(curr_counts.get(item_name, 0))
            if curr_int < prev_int:
                details.append(
                    {
                        "location": location,
                        "item": item_name,
                        "count": prev_int - curr_int,
                        "before_count": prev_int,
                        "after_count": curr_int,
                        "before_state": _entry_state(prev_entry),
                        "after_state": _entry_state(curr_entry if isinstance(curr_entry, dict) else None),
                    }
                )
    return sorted(details, key=lambda x: (-x["count"], x["location"], x["item"]))


def _print_detailed_losses(
    losses: list[dict[str, Any]],
    *,
    prefix: str = "",
    max_locations: int = 12,
) -> None:
    if not losses:
        print(f"{prefix}location loss details: (none)")
        return
    print(f"{prefix}location loss details:")
    for entry in losses[:max_locations]:
        print(
            f"{prefix}  - {entry['location']}: {entry['item']} x{entry['count']} "
            f"(before={entry['before_count']}, after={entry['after_count']})"
        )
        print(f"{prefix}    before: {json.dumps(entry['before_state'], separators=(',', ':'), sort_keys=False)}")
        print(f"{prefix}    after:  {json.dumps(entry['after_state'], separators=(',', ':'), sort_keys=False)}")
    if len(losses) > max_locations:
        print(f"{prefix}  ... {len(losses) - max_locations} more")


def _analysis_paths(args: argparse.Namespace, repo_root: Path) -> list[Path]:
    artifacts_dir = args.artifacts_dir or (repo_root / "tests" / "artifacts")
    if args.analysis_json is not None:
        return [args.analysis_json]
    if args.scenario_id:
        return [artifacts_dir / f"item-disappearance-analysis-{args.scenario_id}.json"]
    paths = sorted(
        [
            p
            for p in artifacts_dir.glob("item-disappearance-analysis-*.json")
            if p.name != "item-disappearance-analysis-all.json"
        ]
    )
    return paths


def _print_analysis(path: Path, max_locations: int, include_unresolved: bool) -> int:
    if not path.exists():
        print(f"Missing analysis file: {path}", file=sys.stderr)
        return 1
    analysis = _load_json(path)
    scenario_id = str(analysis.get("scenario_id") or "<unknown>")
    runtime_script_output = Path(str(analysis.get("runtime_script_output") or ""))
    runs = analysis.get("runs") or []
    preferred_run = max((int(run.get("run", -1)) for run in runs if isinstance(run, dict)), default=None)

    print(f"=== {scenario_id} ===")
    print(f"analysis: {path}")
    print(f"runtime_script_output: {runtime_script_output}")
    print(f"tracked_item_names: {analysis.get('tracked_item_names')}")

    exact = analysis.get("exact_disappearances") or []
    print(f"exact_disappearances={len(exact)}")
    for entry in exact:
        tick = int(entry.get("tick", 0))
        start_tick = tick - 1
        loss = entry.get("loss") or {}
        print(f"- tick={tick} missing={_format_loss_items(loss)}")
        _print_nearest_actions(entry.get("nearest_actions") or {}, prefix="  ")
        if not runtime_script_output.exists():
            print("  location loss details: (runtime_script_output missing)")
            continue
        prev_path = _find_snapshot(runtime_script_output, scenario_id, start_tick, preferred_run=preferred_run)
        curr_path = _find_snapshot(runtime_script_output, scenario_id, tick, preferred_run=preferred_run)
        if prev_path is None or curr_path is None:
            print(f"  location loss details: (missing snapshot files for ticks {start_tick}->{tick})")
            continue
        prev = _load_json(prev_path)
        curr = _load_json(curr_path)
        detailed = _detailed_location_loss(prev, curr, set(loss.keys()) if loss else None)
        print(f"  snapshots: {prev_path.name} -> {curr_path.name}")
        _print_detailed_losses(detailed, prefix="  ", max_locations=max_locations)

    unresolved = analysis.get("unresolved_loss_intervals") or []
    if include_unresolved:
        print(f"unresolved_intervals={len(unresolved)}")
        for interval in unresolved:
            start_tick = int(interval.get("start_tick", 0))
            end_tick = int(interval.get("end_tick", 0))
            loss = interval.get("loss") or {}
            print(
                f"- [{start_tick},{end_tick}] focus_tick={interval.get('focus_tick')} "
                f"missing={_format_loss_items(loss)}"
            )
            _print_nearest_actions(interval.get("nearest_actions") or {}, prefix="  ")
            if not runtime_script_output.exists():
                print("  location loss details: (runtime_script_output missing)")
                continue
            prev_path = _find_snapshot(runtime_script_output, scenario_id, start_tick, preferred_run=preferred_run)
            curr_path = _find_snapshot(runtime_script_output, scenario_id, end_tick, preferred_run=preferred_run)
            if prev_path is None or curr_path is None:
                print(f"  location loss details: (missing snapshot files for ticks {start_tick}->{end_tick})")
                continue
            prev = _load_json(prev_path)
            curr = _load_json(curr_path)
            detailed = _detailed_location_loss(prev, curr, set(loss.keys()) if loss else None)
            print(f"  snapshots: {prev_path.name} -> {curr_path.name}")
            _print_detailed_losses(detailed, prefix="  ", max_locations=max_locations)
    print("")
    return 0


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[3]
    paths = _analysis_paths(args, repo_root)
    if not paths:
        print("No analysis JSON files found.", file=sys.stderr)
        return 2
    include_unresolved = args.include_unresolved == "true"
    failed = 0
    for path in paths:
        failed += _print_analysis(path, args.max_locations, include_unresolved)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

