#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_JSON="$REPO_ROOT/info.json"
cd "$REPO_ROOT"

MOD_NAME="$(python - <<'PY'
import json
from pathlib import Path
info = json.loads(Path("info.json").read_text(encoding="utf-8"))
print(f"{info['name']}_{info['version']}")
PY
)"

DIST_DIR="$REPO_ROOT/dist"
ZIP_PATH="$DIST_DIR/$MOD_NAME.zip"
STAGING_ROOT="$(mktemp -d)"
STAGING_MOD_DIR="$STAGING_ROOT/$MOD_NAME"

mkdir -p "$DIST_DIR" "$STAGING_MOD_DIR"

for entry in "$REPO_ROOT"/* "$REPO_ROOT"/.*; do
  name="$(basename "$entry")"
  if [[ "$name" == "." || "$name" == ".." ]]; then
    continue
  fi
  if [[ "$name" == ".git" || "$name" == ".vscode" || "$name" == "tests" || "$name" == "dist" ]]; then
    continue
  fi
  cp -R "$entry" "$STAGING_MOD_DIR/"
done

rm -f "$ZIP_PATH"
(cd "$STAGING_ROOT" && zip -r "$ZIP_PATH" "$MOD_NAME" >/dev/null)
echo "Packaged mod: $ZIP_PATH"
