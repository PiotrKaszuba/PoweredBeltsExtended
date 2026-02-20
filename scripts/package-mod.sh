#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
INCLUDE_FILES=(
  "control.lua"
  "settings.lua"
  "data-final-fixes.lua"
  "info.json"
  "changelog.txt"
  "thumbnail.png"
)
INCLUDE_DIRS=(
  "locale"
  "prototypes"
)

mkdir -p "$DIST_DIR" "$STAGING_MOD_DIR"

for name in "${INCLUDE_FILES[@]}"; do
  if [[ ! -f "$REPO_ROOT/$name" ]]; then
    echo "Missing required file for packaging: $name" >&2
    exit 2
  fi
  cp "$REPO_ROOT/$name" "$STAGING_MOD_DIR/$name"
done

for name in "${INCLUDE_DIRS[@]}"; do
  if [[ ! -d "$REPO_ROOT/$name" ]]; then
    echo "Missing required directory for packaging: $name" >&2
    exit 2
  fi
  cp -R "$REPO_ROOT/$name" "$STAGING_MOD_DIR/$name"
done

rm -f "$ZIP_PATH"
(cd "$STAGING_ROOT" && zip -r "$ZIP_PATH" "$MOD_NAME" >/dev/null)
echo "Packaged mod: $ZIP_PATH"
