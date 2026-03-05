from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from .backends.base import RunConfig, cleanup_runtime_dir, find_free_port, run_factorio_command, stage_runtime


def _log_step(message: str) -> None:
    print(f"[diagnose] {message}", flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Diagnose item disappearance in one integration scenario or all scenarios.")
    parser.add_argument("scenario_id", nargs="?", default=None)
    parser.add_argument(
        "--exclude-scenario-ids",
        nargs="+",
        default=None,
        help="Scenario IDs to skip when running all scenarios.",
    )
    parser.add_argument("--factorio-bin", type=Path, default=None)
    parser.add_argument("--artifacts-dir", type=Path, default=None)
    parser.add_argument("--timeout-seconds", type=int, default=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "300")))
    parser.add_argument("--build-order-mode", choices=("normal", "reversed", "random"), default="normal")
    parser.add_argument("--build-order-seed", type=int, default=None)
    parser.add_argument("--powered-belts-enabled", choices=("true", "false"), default="true")
    parser.add_argument("--remove-runtime-dir-on-exit", choices=("true", "false"), default="true")
    parser.add_argument("--max-refinement-runs", type=int, default=6)
    return parser.parse_args()


def _to_lua(value: Any) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{" + ",".join(_to_lua(v) for v in value) + "}"
    if isinstance(value, dict):
        parts: list[str] = []
        for key, val in value.items():
            if isinstance(key, str) and key.replace("_", "").isalnum() and not key[0].isdigit():
                parts.append(f"{key}={_to_lua(val)}")
            else:
                parts.append(f"[{_to_lua(key)}]={_to_lua(val)}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"Unsupported value for Lua conversion: {type(value)!r}")


def _create_world(config: RunConfig, runtime) -> None:
    result = run_factorio_command(
        config.factorio_bin,
        ["--mod-directory", str(runtime.mods_dir), "--config", str(runtime.config_path), "--create", str(runtime.save_path)],
        timeout_seconds=config.timeout_seconds,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Create world failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")


def _send_json_command(client, expr: str) -> Any:
    wrapped = (
        '/silent-command local ok,res = pcall(function() return '
        + expr
        + ' end); '
        'if not ok then rcon.print(helpers.table_to_json({ok=false,error=tostring(res)})); return end; '
        'rcon.print(helpers.table_to_json({ok=true,result=res}))'
    )
    for attempt in (1, 2):
        raw = client.send_command(wrapped)
        if raw is None:
            if attempt < 2:
                _log_step("RCON returned no payload; retrying once.")
                time.sleep(0.2)
                continue
            raise RuntimeError(f"RCON returned no payload for expression: {expr}")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            if attempt < 2:
                _log_step("RCON returned non-JSON payload; retrying once.")
                time.sleep(0.2)
                continue
            raise RuntimeError(f"RCON returned non-JSON payload for expression {expr}: {raw!r}") from exc
        if not isinstance(payload, dict):
            raise RuntimeError(f"RCON response payload must be an object, got {type(payload)!r}: {payload!r}")
        if not payload.get("ok"):
            raise RuntimeError(f"Remote command failed: {payload.get('error')}")
        return payload.get("result")
    raise RuntimeError("Unreachable RCON retry state")


def _sum_totals(snapshot: dict[str, Any], include_items: set[str] | None = None) -> dict[str, int]:
    totals = snapshot.get("totals") or {}
    out: dict[str, int] = {}
    for k, v in totals.items():
        if include_items is not None and k not in include_items:
            continue
        out[k] = int(v)
    return out


def _compute_loss(prev_totals: dict[str, int], curr_totals: dict[str, int]) -> dict[str, int]:
    out: dict[str, int] = {}
    for item, prev in prev_totals.items():
        curr = curr_totals.get(item, 0)
        if curr < prev:
            out[item] = prev - curr
    return out


def _lossy_intervals(
    snapshots_by_tick: dict[int, dict[str, Any]],
    include_items: set[str] | None = None,
) -> list[tuple[int, int, dict[str, int]]]:
    ticks = sorted(snapshots_by_tick)
    intervals: list[tuple[int, int, dict[str, int]]] = []
    for a, b in zip(ticks, ticks[1:]):
        loss = _compute_loss(
            _sum_totals(snapshots_by_tick[a], include_items),
            _sum_totals(snapshots_by_tick[b], include_items),
        )
        if loss:
            intervals.append((a, b, loss))
    return intervals


def _location_loss(
    prev: dict[str, Any],
    curr: dict[str, Any],
    include_items: set[str] | None = None,
) -> list[dict[str, Any]]:
    prev_locs = prev.get("locations") or {}
    curr_locs = curr.get("locations") or {}
    losses: list[dict[str, Any]] = []
    for loc_name, loc in prev_locs.items():
        prev_counts = loc.get("counts") or {}
        curr_counts = (curr_locs.get(loc_name) or {}).get("counts") or {}
        for item, prev_count in prev_counts.items():
            if include_items is not None and item not in include_items:
                continue
            curr_count = int(curr_counts.get(item, 0))
            prev_int = int(prev_count)
            if curr_count < prev_int:
                losses.append({"location": loc_name, "item": item, "count": prev_int - curr_count})
    return sorted(losses, key=lambda x: (-x["count"], x["location"], x["item"]))


def _interval_probe_ticks(start: int, end: int, count: int = 10) -> set[int]:
    span = end - start
    if span <= 1 or count <= 0:
        return set()
    interior = span - 1
    target_count = min(count, interior)
    if target_count <= 0:
        return set()

    probes: set[int] = set()
    # Start with evenly spaced candidates inside (start, end).
    for idx in range(1, target_count + 1):
        tick = start + int(round(idx * (span / (target_count + 1))))
        tick = max(start + 1, min(end - 1, tick))
        probes.add(tick)

    # Fill any gaps caused by rounding collisions, preferring center-out ticks.
    if len(probes) < target_count:
        center = (start + end) / 2.0
        interior_ticks = list(range(start + 1, end))
        interior_ticks.sort(key=lambda tick: (abs(tick - center), tick))
        for tick in interior_ticks:
            probes.add(tick)
            if len(probes) >= target_count:
                break
    return probes


def _tracked_items_from_source_seed_actions(scenario: dict[str, Any]) -> set[str]:
    tracked: set[str] = set()
    for action in scenario.get("actions") or []:
        if not isinstance(action, dict):
            continue
        if action.get("type") != "fill_inventory":
            continue
        if _action_tick(action) != 0:
            continue
        action_target = action.get("target_ref") or action.get("target_entity_id")
        stacks = action.get("stacks")
        if not isinstance(stacks, list):
            continue
        for stack in stacks:
            if not isinstance(stack, dict):
                continue
            stack_target = stack.get("target_ref") or stack.get("target_entity_id") or action_target
            if not isinstance(stack_target, str):
                continue
            if not (stack_target == "source" or stack_target.startswith("source_")):
                continue
            item_name = stack.get("name")
            if isinstance(item_name, str) and item_name != "":
                tracked.add(item_name)
    return tracked


def _tracked_items_from_source_locations(snapshot: dict[str, Any]) -> set[str]:
    tracked: set[str] = set()
    locations = snapshot.get("locations") or {}
    if not isinstance(locations, dict):
        return tracked
    for location_id, entry in locations.items():
        if not isinstance(entry, dict):
            continue
        entity_id = entry.get("entity_id")
        source_match = isinstance(entity_id, str) and (entity_id == "source" or entity_id.startswith("source_"))
        if not source_match and isinstance(location_id, str):
            source_match = location_id.startswith("source")
        if not source_match:
            continue
        counts = entry.get("counts") or {}
        if not isinstance(counts, dict):
            continue
        for item_name, count in counts.items():
            if isinstance(item_name, str) and item_name != "" and int(count) > 0:
                tracked.add(item_name)
    return tracked


def _actions_context(scenario: dict[str, Any], tick: int) -> dict[str, Any]:
    actions = [a for a in (scenario.get("actions") or []) if a.get("type") != "scan_item_locations"]
    at_tick = [a for a in actions if int(a.get("tick", 0)) == tick]
    prev_tick = tick - 1
    prev = [a for a in actions if int(a.get("tick", 0)) == prev_tick]
    fallback_tick = None
    fallback: list[dict[str, Any]] = []
    if not prev:
        prior_ticks = sorted({int(a.get("tick", 0)) for a in actions if int(a.get("tick", 0)) < tick})
        if prior_ticks:
            fallback_tick = prior_ticks[-1]
            fallback = [a for a in actions if int(a.get("tick", 0)) == fallback_tick]
    return {
        "current_tick_actions": at_tick,
        "previous_tick_actions": prev,
        "latest_prior_tick": fallback_tick,
        "latest_prior_tick_actions": fallback,
    }


def _action_tick(action: dict[str, Any]) -> int:
    try:
        return int(action.get("tick", 0))
    except (TypeError, ValueError):
        return 0


def _scenario_non_scan_actions(scenario: dict[str, Any]) -> list[dict[str, Any]]:
    raw_actions = scenario.get("actions") or []
    actions = [a for a in raw_actions if isinstance(a, dict) and a.get("type") != "scan_item_locations"]
    return sorted(actions, key=lambda a: (_action_tick(a), str(a.get("type") or "")))


def _nearest_actions_context(
    scenario: dict[str, Any],
    tick: int,
    *,
    before_count: int = 2,
    after_count: int = 2,
) -> dict[str, list[dict[str, Any]]]:
    actions = _scenario_non_scan_actions(scenario)
    at_tick = [a for a in actions if _action_tick(a) == tick]
    before = [a for a in actions if _action_tick(a) < tick][-before_count:]
    after = [a for a in actions if _action_tick(a) > tick][:after_count]
    return {
        "at_tick": at_tick,
        "before": before,
        "after": after,
    }


def _compact_action(action: dict[str, Any]) -> str:
    compact: dict[str, Any] = {
        "tick": _action_tick(action),
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


def _sorted_loss_items(loss: dict[str, int]) -> list[tuple[str, int]]:
    return sorted(((name, int(count)) for name, count in loss.items()), key=lambda item: (-item[1], item[0]))


def _format_loss_items(loss: dict[str, int]) -> str:
    items = _sorted_loss_items(loss)
    if not items:
        return "(none)"
    return ", ".join(f"{name} x{count}" for name, count in items)


def _append_nearest_actions_lines(lines: list[str], context: dict[str, list[dict[str, Any]]], *, prefix: str = "") -> None:
    lines.append(f"{prefix}nearest actions:")
    for label, key in (("at", "at_tick"), ("before", "before"), ("after", "after")):
        actions = context.get(key) or []
        if not actions:
            lines.append(f"{prefix}  {label}: (none)")
            continue
        for action in actions:
            lines.append(f"{prefix}  {label}: {_compact_action(action)}")


def _print_nearest_actions_console(context: dict[str, list[dict[str, Any]]], *, prefix: str = "") -> None:
    for label, key in (("at", "at_tick"), ("before", "before"), ("after", "after")):
        actions = context.get(key) or []
        if not actions:
            print(f"{prefix}{label}: (none)", flush=True)
            continue
        for action in actions:
            print(f"{prefix}{label}: {_compact_action(action)}", flush=True)


def _print_scenario_console_report(
    scenario_id: str,
    exact_disappearances: list[dict[str, Any]],
    unresolved_loss_intervals: list[dict[str, Any]],
    *,
    max_entries: int = 8,
) -> None:
    print(
        f"[diagnose][report] {scenario_id}: "
        f"exact_disappearances={len(exact_disappearances)} "
        f"unresolved_intervals={len(unresolved_loss_intervals)}",
        flush=True,
    )
    if exact_disappearances:
        print("[diagnose][report] Exact disappearance ticks:", flush=True)
        for entry in exact_disappearances[:max_entries]:
            print(
                f"[diagnose][report]   tick={entry['tick']} missing={_format_loss_items(entry['loss'])}",
                flush=True,
            )
            _print_nearest_actions_console(entry.get("nearest_actions") or {}, prefix="[diagnose][report]     ")
    else:
        print("[diagnose][report] Exact disappearance ticks: (none)", flush=True)
    if len(exact_disappearances) > max_entries:
        print(
            f"[diagnose][report]   ... {len(exact_disappearances) - max_entries} more exact entries",
            flush=True,
        )

    if unresolved_loss_intervals:
        print("[diagnose][report] Unresolved intervals:", flush=True)
        for interval in unresolved_loss_intervals[:max_entries]:
            print(
                "[diagnose][report]   "
                f"[{interval['start_tick']},{interval['end_tick']}] "
                f"focus_tick={interval['focus_tick']} "
                f"missing={_format_loss_items(interval['loss'])}",
                flush=True,
            )
            _print_nearest_actions_console(interval.get("nearest_actions") or {}, prefix="[diagnose][report]     ")
    else:
        print("[diagnose][report] Unresolved intervals: (none)", flush=True)
    if len(unresolved_loss_intervals) > max_entries:
        print(
            f"[diagnose][report]   ... {len(unresolved_loss_intervals) - max_entries} more unresolved intervals",
            flush=True,
        )


def _scenario_log(scenario_id: str, message: str) -> None:
    _log_step(f"{scenario_id}: {message}")


def _list_scenario_ids(client) -> list[str]:
    raw = _send_json_command(client, 'remote.call("pbe_integration_harness","list_scenario_ids")')
    if not isinstance(raw, list):
        raise RuntimeError(f"Scenario id list must be a list, got {type(raw)!r}")
    out: list[str] = []
    for entry in raw:
        if isinstance(entry, str) and entry != "":
            out.append(entry)
    if not out:
        raise RuntimeError("No scenarios available from harness list_scenario_ids")
    return out


def _run_diagnosis_for_scenario(
    client,
    runtime,
    args: argparse.Namespace,
    artifacts_dir: Path,
    scenario_id: str,
) -> dict[str, Any]:
    _scenario_log(scenario_id, "Loading scenario definition.")
    scenario = _send_json_command(client, f'remote.call("pbe_integration_harness","get_scenario_definition",{_to_lua(scenario_id)})')
    if not isinstance(scenario, dict):
        raise RuntimeError(f"Unknown scenario: {scenario_id}")
    max_tick = int(scenario.get("max_tick") or 1200)
    _scenario_log(scenario_id, f"Scenario max_tick={max_tick}.")
    tracked_item_names = _tracked_items_from_source_seed_actions(scenario)
    if tracked_item_names:
        _scenario_log(scenario_id, f"Tracking source-seeded items: {sorted(tracked_item_names)}")
    else:
        _scenario_log(scenario_id, "No source-seeded items detected in tick-0 fill actions; will infer from source snapshot.")

    sampled_ticks: set[int] = set([0, max_tick])
    for p in range(10, 100, 10):
        sampled_ticks.add(max(0, int(max_tick * (p / 100.0))))
    all_sampled_ticks: set[int] = set(sampled_ticks)

    run_reports: list[dict[str, Any]] = []
    for run_idx in range(args.max_refinement_runs):
        tick_list = sorted(sampled_ticks)
        all_sampled_ticks.update(tick_list)
        _scenario_log(scenario_id, f"Refinement run {run_idx + 1}/{args.max_refinement_runs}: ticks={tick_list}")
        extra_actions = [
            {
                "tick": t,
                "type": "scan_item_locations",
                "debug_log": True,
                "output_file": f"pbe-chain-scan-{scenario_id}-run{run_idx}-tick{t}.json",
            }
            for t in tick_list
        ]
        options = {
            "keep_active": True,
            "pause": False,
            "save_snapshot": False,
            "build_order_mode": args.build_order_mode,
            "build_order_seed": args.build_order_seed,
            "extra_actions": extra_actions,
        }
        _scenario_log(scenario_id, "Preparing scenario setup with scan actions.")
        _send_json_command(client, f'remote.call("pbe_integration_harness","prepare_scenario_setup",{_to_lua(scenario_id)},nil,{_to_lua(options)})')

        wait_deadline = time.time() + args.timeout_seconds
        _scenario_log(scenario_id, "Waiting for scenario completion.")
        while time.time() < wait_deadline:
            results = _send_json_command(client, 'remote.call("pbe_integration_harness","get_results")')
            scenarios = results.get("scenarios") or []
            if scenarios:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("Timed out waiting for scenario completion")

        snapshots_by_tick: dict[int, dict[str, Any]] = {}
        for t in tick_list:
            fp = runtime.script_output_dir / f"pbe-chain-scan-{scenario_id}-run{run_idx}-tick{t}.json"
            if fp.exists():
                snapshots_by_tick[t] = json.loads(fp.read_text(encoding="utf-8"))
            else:
                _scenario_log(scenario_id, f"Missing snapshot file for tick {t}: {fp}")
        if not tracked_item_names and snapshots_by_tick:
            first_tick = min(snapshots_by_tick)
            tracked_item_names = _tracked_items_from_source_locations(snapshots_by_tick[first_tick])
            if tracked_item_names:
                _scenario_log(scenario_id, f"Tracking source-snapshot items from tick {first_tick}: {sorted(tracked_item_names)}")
            else:
                _scenario_log(scenario_id, f"Source snapshot at tick {first_tick} had no items; falling back to all items.")
        item_filter = tracked_item_names if tracked_item_names else None
        intervals = _lossy_intervals(snapshots_by_tick, item_filter)
        _scenario_log(scenario_id, f"Run {run_idx + 1}: loaded {len(snapshots_by_tick)} snapshots, lossy intervals={len(intervals)}")
        run_reports.append({"run": run_idx, "ticks": tick_list, "intervals": intervals})

        new_ticks: set[int] = set()
        for start, end, _loss in intervals:
            if end - start <= 1:
                continue
            for probe_tick in _interval_probe_ticks(start, end, count=10):
                if probe_tick not in sampled_ticks:
                    new_ticks.add(probe_tick)
        if not new_ticks:
            _scenario_log(scenario_id, "No new probe ticks required; refinement complete.")
            final_snapshots = snapshots_by_tick
            final_scenario = scenarios[0]
            break
        lossy_boundary_ticks: set[int] = {0, max_tick}
        for start, end, _loss in intervals:
            lossy_boundary_ticks.add(start)
            lossy_boundary_ticks.add(end)
        sampled_ticks = lossy_boundary_ticks | new_ticks
        _scenario_log(scenario_id, f"Adding probe ticks for next run: {sorted(new_ticks)}")
    else:
        final_snapshots = snapshots_by_tick
        final_scenario = scenarios[0]

    _scenario_log(scenario_id, "Computing exact disappearance ticks.")
    item_filter = tracked_item_names if tracked_item_names else None
    final_intervals = _lossy_intervals(final_snapshots, item_filter)
    unresolved_loss_intervals = []
    for start, end, loss in final_intervals:
        if end - start <= 1:
            continue
        focus_tick = (start + end) // 2
        unresolved_loss_intervals.append(
            {
                "start_tick": start,
                "end_tick": end,
                "focus_tick": focus_tick,
                "loss": loss,
                "nearest_actions": _nearest_actions_context(scenario, focus_tick),
            }
        )
    exact_disappearances: list[dict[str, Any]] = []
    for start, end, loss in final_intervals:
        if end - start != 1:
            continue
        loc_loss = _location_loss(final_snapshots[start], final_snapshots[end], item_filter)
        exact_disappearances.append(
            {
                "tick": end,
                "loss": loss,
                "location_loss": loc_loss,
                "actions_context": _actions_context(scenario, end),
                "nearest_actions": _nearest_actions_context(scenario, end),
            }
        )

    analysis = {
        "scenario_id": scenario_id,
        "max_tick": max_tick,
        "tracked_item_names": sorted(tracked_item_names),
        "sampled_ticks": sorted(all_sampled_ticks),
        "runs": run_reports,
        "exact_disappearances": exact_disappearances,
        "unresolved_loss_intervals": unresolved_loss_intervals,
        "scenario_result": final_scenario,
        "runtime_script_output": str(runtime.script_output_dir),
    }
    out_json = artifacts_dir / f"item-disappearance-analysis-{scenario_id}.json"
    out_txt = artifacts_dir / f"item-disappearance-analysis-{scenario_id}.txt"
    _scenario_log(scenario_id, f"Writing analysis JSON to {out_json}")
    out_json.write_text(json.dumps(analysis, indent=2), encoding="utf-8")

    lines = [
        f"Scenario: {scenario_id}",
        f"Max tick: {max_tick}",
        f"Tracked items: {sorted(tracked_item_names) if tracked_item_names else '(all items fallback)'}",
        f"Sampled ticks: {sorted(all_sampled_ticks)}",
        "",
    ]
    lines.append("Exact disappearance ticks:")
    if not exact_disappearances:
        lines.append("  (none)")
    for entry in exact_disappearances:
        lines.append(f"- tick {entry['tick']}: missing {_format_loss_items(entry['loss'])}")
        top_locations = entry.get("location_loss", [])[:8]
        if not top_locations:
            lines.append("  location loss: (none)")
        else:
            lines.append("  location loss:")
            for loc in top_locations:
                lines.append(f"    - {loc['location']}: {loc['item']} x{loc['count']}")
        _append_nearest_actions_lines(lines, entry.get("nearest_actions") or {}, prefix="  ")
        lines.append("")

    lines.append("Unresolved loss intervals:")
    if unresolved_loss_intervals:
        lines.append("  (increase --max-refinement-runs to narrow further)")
        for interval in unresolved_loss_intervals:
            lines.append(f"- [{interval['start_tick']}, {interval['end_tick']}] focus_tick={interval['focus_tick']}: missing {_format_loss_items(interval['loss'])}")
            _append_nearest_actions_lines(lines, interval.get("nearest_actions") or {}, prefix="  ")
            lines.append("")
    else:
        lines.append("  (none)")
    _scenario_log(scenario_id, f"Writing summary TXT to {out_txt}")
    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    _print_scenario_console_report(scenario_id, exact_disappearances, unresolved_loss_intervals)
    print(f"Wrote analysis: {out_json}")
    print(f"Wrote summary: {out_txt}")
    return analysis


def main() -> int:
    args = parse_args()
    if args.scenario_id is None:
        _log_step("Starting diagnosis for all scenarios")
    else:
        _log_step(f"Starting diagnosis for scenario '{args.scenario_id}'")
    repo_root = Path(__file__).resolve().parents[3]
    factorio_bin = args.factorio_bin or (Path(os.environ["FACTORIO_BIN"]) if "FACTORIO_BIN" in os.environ else None)
    if factorio_bin is None or not factorio_bin.exists():
        print("Missing Factorio binary", file=sys.stderr)
        return 2
    artifacts_dir = args.artifacts_dir or (repo_root / "tests" / "artifacts")
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    remove_runtime = args.remove_runtime_dir_on_exit == "true"

    config = RunConfig(
        factorio_bin=factorio_bin,
        repo_root=repo_root,
        artifacts_dir=artifacts_dir,
        timeout_seconds=args.timeout_seconds,
        until_tick=120000,
        powered_belts_enabled=args.powered_belts_enabled == "true",
        remove_runtime_dir_on_exit=remove_runtime,
        build_order_mode=args.build_order_mode,
        build_order_seed=args.build_order_seed,
    )

    _log_step("Staging runtime directory.")
    runtime = stage_runtime(config)
    process: subprocess.Popen[object] | None = None
    try:
        _log_step("Creating initial world save.")
        _create_world(config, runtime)
        try:
            from factorio_rcon import RCONClient
        except Exception as exc:
            raise RuntimeError("factorio-rcon-py is required") from exc

        game_port = find_free_port()
        rcon_port = find_free_port()
        password = "pbe-diagnose"
        cmd = [
            str(config.factorio_bin), "--mod-directory", str(runtime.mods_dir), "--config", str(runtime.config_path),
            "--start-server", str(runtime.save_path), "--server-settings", str(runtime.server_settings_path),
            "--bind", "127.0.0.1", "--port", str(game_port), "--disable-audio",
            "--rcon-port", str(rcon_port), "--rcon-password", password, "--until-tick", str(config.until_tick),
        ]
        _log_step(f"Starting Factorio server (game port={game_port}, rcon port={rcon_port}).")
        process = subprocess.Popen(cmd)

        deadline = time.time() + 30
        client = None
        _log_step("Waiting for RCON connection.")
        while time.time() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"Factorio server exited early with code {process.returncode}")
            try:
                client = RCONClient("127.0.0.1", rcon_port, password)
                client.connect()
                break
            except Exception:
                time.sleep(0.5)
        if client is None:
            raise RuntimeError("Could not connect to RCON")
        _log_step("RCON connected.")

        with client:
            if args.scenario_id is None:
                _log_step("Loading scenario id list from harness.")
                scenario_ids = _list_scenario_ids(client)
                exclude_ids = {
                    entry.strip()
                    for entry in (args.exclude_scenario_ids or [])
                    if isinstance(entry, str) and entry.strip() != ""
                }
                if exclude_ids:
                    before_count = len(scenario_ids)
                    scenario_ids = [scenario_id for scenario_id in scenario_ids if scenario_id not in exclude_ids]
                    _log_step(
                        "Excluded scenarios via --exclude-scenario-ids: "
                        f"{sorted(exclude_ids)} (kept {len(scenario_ids)}/{before_count})"
                    )
                    if not scenario_ids:
                        raise RuntimeError("No scenarios left after applying --exclude-scenario-ids")
            else:
                scenario_ids = [args.scenario_id]
                if args.exclude_scenario_ids:
                    _log_step("Ignoring --exclude-scenario-ids because a single scenario_id was provided.")

            analyses: list[dict[str, Any]] = []
            failures: list[dict[str, str]] = []
            for idx, scenario_id in enumerate(scenario_ids, start=1):
                _log_step(f"Running scenario {idx}/{len(scenario_ids)}: {scenario_id}")
                try:
                    analysis = _run_diagnosis_for_scenario(client, runtime, args, artifacts_dir, scenario_id)
                    analyses.append(analysis)
                except Exception as exc:
                    failures.append({"scenario_id": scenario_id, "error": str(exc)})
                    print(f"Diagnosis run failed for scenario {scenario_id}: {exc}", file=sys.stderr)
                    if len(scenario_ids) == 1:
                        raise

            if len(scenario_ids) > 1:
                summary_json = artifacts_dir / "item-disappearance-analysis-all.json"
                summary_txt = artifacts_dir / "item-disappearance-analysis-all.txt"
                aggregate = {
                    "scenario_ids": scenario_ids,
                    "analyses_written": [a.get("scenario_id") for a in analyses],
                    "failed": failures,
                    "scenario_summaries": [
                        {
                            "scenario_id": a.get("scenario_id"),
                            "exact_disappearance_count": len(a.get("exact_disappearances") or []),
                            "unresolved_interval_count": len(a.get("unresolved_loss_intervals") or []),
                        }
                        for a in analyses
                    ],
                }
                summary_json.write_text(json.dumps(aggregate, indent=2), encoding="utf-8")
                lines = [
                    f"Scenarios requested: {len(scenario_ids)}",
                    f"Scenarios analyzed: {len(analyses)}",
                    f"Scenarios failed: {len(failures)}",
                    "",
                ]
                for item in aggregate["scenario_summaries"]:
                    lines.append(
                        f"- {item['scenario_id']}: "
                        f"exact_disappearances={item['exact_disappearance_count']} "
                        f"unresolved_intervals={item['unresolved_interval_count']}"
                    )
                if failures:
                    lines.append("")
                    lines.append("Failures:")
                    for failure in failures:
                        lines.append(f"- {failure['scenario_id']}: {failure['error']}")
                summary_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
                print(f"Wrote analysis: {summary_json}")
                print(f"Wrote summary: {summary_txt}")
            if failures:
                return 3

    except Exception as exc:
        if process is not None and process.poll() is None:
            process.kill()
        print(f"Diagnosis run failed: {exc}", file=sys.stderr)
        return 3
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        if config.remove_runtime_dir_on_exit:
            try:
                cleanup_runtime_dir(runtime.runtime_root)
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
