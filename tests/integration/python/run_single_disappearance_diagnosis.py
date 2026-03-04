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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Diagnose item disappearance in a single integration scenario.")
    parser.add_argument("scenario_id")
    parser.add_argument("--factorio-bin", type=Path, default=None)
    parser.add_argument("--artifacts-dir", type=Path, default=None)
    parser.add_argument("--timeout-seconds", type=int, default=int(os.environ.get("PBE_TEST_TIMEOUT_SECONDS", "120")))
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
    raw = client.send_command(
        '/silent-command local ok,res = pcall(function() return ' + expr + ' end); '
        'if not ok then rcon.print(helpers.table_to_json({ok=false,error=tostring(res)})); return end; '
        'rcon.print(helpers.table_to_json({ok=true,result=res}))'
    )
    payload = json.loads(raw)
    if not payload.get("ok"):
        raise RuntimeError(f"Remote command failed: {payload.get('error')}")
    return payload.get("result")


def _sum_totals(snapshot: dict[str, Any]) -> dict[str, int]:
    totals = snapshot.get("totals") or {}
    return {k: int(v) for k, v in totals.items()}


def _compute_loss(prev_totals: dict[str, int], curr_totals: dict[str, int]) -> dict[str, int]:
    out: dict[str, int] = {}
    for item, prev in prev_totals.items():
        curr = curr_totals.get(item, 0)
        if curr < prev:
            out[item] = prev - curr
    return out


def _lossy_intervals(snapshots_by_tick: dict[int, dict[str, Any]]) -> list[tuple[int, int, dict[str, int]]]:
    ticks = sorted(snapshots_by_tick)
    intervals: list[tuple[int, int, dict[str, int]]] = []
    for a, b in zip(ticks, ticks[1:]):
        loss = _compute_loss(_sum_totals(snapshots_by_tick[a]), _sum_totals(snapshots_by_tick[b]))
        if loss:
            intervals.append((a, b, loss))
    return intervals


def _location_loss(prev: dict[str, Any], curr: dict[str, Any]) -> list[dict[str, Any]]:
    prev_locs = prev.get("locations") or {}
    curr_locs = curr.get("locations") or {}
    losses: list[dict[str, Any]] = []
    for loc_name, loc in prev_locs.items():
        prev_counts = loc.get("counts") or {}
        curr_counts = (curr_locs.get(loc_name) or {}).get("counts") or {}
        for item, prev_count in prev_counts.items():
            curr_count = int(curr_counts.get(item, 0))
            prev_int = int(prev_count)
            if curr_count < prev_int:
                losses.append({"location": loc_name, "item": item, "count": prev_int - curr_count})
    return sorted(losses, key=lambda x: (-x["count"], x["location"], x["item"]))


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


def main() -> int:
    args = parse_args()
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

    runtime = stage_runtime(config)
    process: subprocess.Popen[str] | None = None
    try:
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
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        deadline = time.time() + 30
        client = None
        while time.time() < deadline:
            try:
                client = RCONClient("127.0.0.1", rcon_port, password)
                client.connect()
                break
            except Exception:
                time.sleep(0.5)
        if client is None:
            raise RuntimeError("Could not connect to RCON")

        with client:
            scenario = _send_json_command(client, f'remote.call("pbe_integration_harness","get_scenario_definition",{_to_lua(args.scenario_id)})')
            if not isinstance(scenario, dict):
                raise RuntimeError(f"Unknown scenario: {args.scenario_id}")
            max_tick = int(scenario.get("max_tick") or 1200)

            sampled_ticks: set[int] = set([0, max_tick])
            for p in range(10, 100, 10):
                sampled_ticks.add(max(0, int(max_tick * (p / 100.0))))

            run_reports: list[dict[str, Any]] = []
            for run_idx in range(args.max_refinement_runs):
                tick_list = sorted(sampled_ticks)
                extra_actions = [
                    {
                        "tick": t,
                        "type": "scan_item_locations",
                        "debug_log": True,
                        "output_file": f"pbe-chain-scan-{args.scenario_id}-run{run_idx}-tick{t}.json",
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
                _send_json_command(client, f'remote.call("pbe_integration_harness","prepare_scenario_setup",{_to_lua(args.scenario_id)},nil,{_to_lua(options)})')

                wait_deadline = time.time() + args.timeout_seconds
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
                    fp = runtime.script_output_dir / f"pbe-chain-scan-{args.scenario_id}-run{run_idx}-tick{t}.json"
                    if fp.exists():
                        snapshots_by_tick[t] = json.loads(fp.read_text(encoding="utf-8"))
                intervals = _lossy_intervals(snapshots_by_tick)
                run_reports.append({"run": run_idx, "ticks": tick_list, "intervals": intervals})

                new_ticks: set[int] = set()
                for start, end, _loss in intervals:
                    if end - start <= 1:
                        continue
                    mid = (start + end) // 2
                    if mid not in sampled_ticks:
                        new_ticks.add(mid)
                if not new_ticks:
                    final_snapshots = snapshots_by_tick
                    final_scenario = scenarios[0]
                    break
                sampled_ticks.update(new_ticks)
            else:
                final_snapshots = snapshots_by_tick
                final_scenario = scenarios[0]

            exact_disappearances: list[dict[str, Any]] = []
            for start, end, loss in _lossy_intervals(final_snapshots):
                if end - start != 1:
                    continue
                loc_loss = _location_loss(final_snapshots[start], final_snapshots[end])
                exact_disappearances.append(
                    {
                        "tick": end,
                        "loss": loss,
                        "location_loss": loc_loss,
                        "actions_context": _actions_context(scenario, end),
                    }
                )

            analysis = {
                "scenario_id": args.scenario_id,
                "max_tick": max_tick,
                "sampled_ticks": sorted(sampled_ticks),
                "runs": run_reports,
                "exact_disappearances": exact_disappearances,
                "scenario_result": final_scenario,
                "runtime_script_output": str(runtime.script_output_dir),
            }
            out_json = artifacts_dir / f"item-disappearance-analysis-{args.scenario_id}.json"
            out_txt = artifacts_dir / f"item-disappearance-analysis-{args.scenario_id}.txt"
            out_json.write_text(json.dumps(analysis, indent=2), encoding="utf-8")

            lines = [f"Scenario: {args.scenario_id}", f"Max tick: {max_tick}", f"Sampled ticks: {sorted(sampled_ticks)}", ""]
            if not exact_disappearances:
                lines.append("No exact disappearance ticks identified.")
            for entry in exact_disappearances:
                lines.append(f"Tick {entry['tick']}: loss={entry['loss']}")
                top_locations = entry.get("location_loss", [])[:8]
                for loc in top_locations:
                    lines.append(f"  - {loc['location']}: {loc['item']} x{loc['count']}")
            out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"Wrote analysis: {out_json}")
            print(f"Wrote summary: {out_txt}")

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
