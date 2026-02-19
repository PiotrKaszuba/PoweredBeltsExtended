from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert blueprint fixture strings into normalized layouts.")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--strict", action="store_true", help="Fail if any blueprint fixture is invalid.")
    return parser.parse_args()


def load_blueprint_data(blueprint_string: str) -> dict[str, Any]:
    try:
        from draftsman.blueprintable import Blueprint
    except Exception as exc:
        raise RuntimeError("factorio-draftsman is required for blueprint preprocessing") from exc

    blueprint_obj: Any
    if hasattr(Blueprint, "from_string"):
        blueprint_obj = Blueprint.from_string(blueprint_string)  # type: ignore[attr-defined]
    else:
        blueprint_obj = Blueprint()
        if hasattr(blueprint_obj, "from_string"):
            blueprint_obj.from_string(blueprint_string)
        elif hasattr(blueprint_obj, "load_from_string"):
            blueprint_obj.load_from_string(blueprint_string)
        else:
            raise RuntimeError("Unsupported factorio-draftsman Blueprint API")

    if hasattr(blueprint_obj, "to_dict"):
        data = blueprint_obj.to_dict()
    else:
        raise RuntimeError("Unsupported factorio-draftsman Blueprint API: missing to_dict")
    return data


def normalize_layout(layout_id: str, blueprint_dict: dict[str, Any]) -> dict[str, Any]:
    root = blueprint_dict.get("blueprint", blueprint_dict)
    entities = root.get("entities", [])

    normalized_entities: list[dict[str, Any]] = []
    references: dict[str, str] = {}

    sorted_entities = sorted(entities, key=lambda e: int(e.get("entity_number", 0)))
    xs: list[float] = []
    ys: list[float] = []
    for entity in sorted_entities:
        position = entity.get("position", {})
        x = float(position.get("x", 0.0))
        y = float(position.get("y", 0.0))
        xs.append(x)
        ys.append(y)

        tags = entity.get("tags") or {}
        ref_name = tags.get("pbe_ref")
        entity_id = ref_name if isinstance(ref_name, str) and ref_name else f"e_{entity.get('entity_number', 0)}"

        normalized = {
            "id": entity_id,
            "name": entity.get("name"),
            "position": {"x": x, "y": y},
        }
        if "direction" in entity:
            normalized["direction"] = int(entity["direction"])
        if "type" in entity:
            normalized["type"] = entity["type"]
        if "recipe" in entity:
            normalized["recipe"] = entity["recipe"]
        if "control_behavior" in entity:
            normalized["control_behavior"] = entity["control_behavior"]

        normalized_entities.append(normalized)
        if ref_name:
            references[ref_name] = entity_id

    if xs and ys:
        area = {
            "left_top": {"x": min(xs) - 6.0, "y": min(ys) - 6.0},
            "right_bottom": {"x": max(xs) + 6.0, "y": max(ys) + 6.0},
        }
    else:
        area = {"left_top": {"x": -16.0, "y": -16.0}, "right_bottom": {"x": 16.0, "y": 16.0}}

    return {
        "id": layout_id,
        "version": 1,
        "area": area,
        "references": references,
        "entities": normalized_entities,
    }


def to_lua(value: Any, indent: int = 0) -> str:
    space = " " * indent
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(value, list):
        if not value:
            return "{}"
        parts = ["{"]
        for item in value:
            parts.append(f"{space}  {to_lua(item, indent + 2)},")
        parts.append(f"{space}}}")
        return "\n".join(parts)
    if isinstance(value, dict):
        if not value:
            return "{}"
        parts = ["{"]
        for key, item in value.items():
            if isinstance(key, str) and key.replace("_", "").isalnum():
                key_repr = key
            else:
                key_repr = f"[{to_lua(key, indent + 2)}]"
            parts.append(f"{space}  {key_repr} = {to_lua(item, indent + 2)},")
        parts.append(f"{space}}}")
        return "\n".join(parts)
    raise TypeError(f"Unsupported type for Lua serialization: {type(value)}")


def write_layout_outputs(layout: dict[str, Any], layouts_dir: Path, harness_layouts_dir: Path) -> None:
    layout_id = layout["id"]
    layouts_dir.mkdir(parents=True, exist_ok=True)
    harness_layouts_dir.mkdir(parents=True, exist_ok=True)

    json_path = layouts_dir / f"{layout_id}.json"
    json_path.write_text(json.dumps(layout, indent=2), encoding="utf-8")

    lua_path = harness_layouts_dir / f"{layout_id}.lua"
    lua_path.write_text("return " + to_lua(layout) + "\n", encoding="utf-8")


def write_index(harness_layouts_dir: Path) -> None:
    files = sorted(path.stem for path in harness_layouts_dir.glob("*.lua") if path.stem != "index")
    lines = ["return {"]
    for stem in files:
        lines.append(f'  {stem} = require("layouts_generated.{stem}"),')
    lines.append("}")
    (harness_layouts_dir / "index.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root
    blueprint_dir = repo_root / "tests" / "fixtures" / "blueprints"
    layouts_dir = repo_root / "tests" / "fixtures" / "layouts"
    harness_layouts_dir = repo_root / "tests" / "integration" / "harness_mod" / "layouts_generated"

    errors: list[str] = []
    for blueprint_file in sorted(blueprint_dir.glob("*.txt")):
        raw = blueprint_file.read_text(encoding="utf-8").strip()
        layout_id = blueprint_file.stem
        try:
            if raw and raw.startswith("0"):
                blueprint_dict = load_blueprint_data(raw)
                layout = normalize_layout(layout_id, blueprint_dict)
                print(f"Generated layout from blueprint: {layout_id}")
            else:
                existing_json = layouts_dir / f"{layout_id}.json"
                if not existing_json.exists():
                    continue
                layout = json.loads(existing_json.read_text(encoding="utf-8"))
                print(f"Generated layout from JSON fixture: {layout_id}")
            write_layout_outputs(layout, layouts_dir, harness_layouts_dir)
        except Exception as exc:
            errors.append(f"{blueprint_file.name}: {exc}")

    write_index(harness_layouts_dir)
    if errors:
        for err in errors:
            print(f"ERROR: {err}")
        return 1 if args.strict else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
