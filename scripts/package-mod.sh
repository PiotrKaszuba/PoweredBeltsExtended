#!/usr/bin/env bash
set -euo pipefail

NO_ZIP=false
CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --no-zip)
      NO_ZIP=true
      ;;
    --clean)
      CLEAN=true
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--no-zip] [--clean]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $(basename "$0") [--no-zip] [--clean]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PATH="$PROJECT_DIR/info.json"

if [[ ! -f "$INFO_PATH" ]]; then
  echo "Missing info.json at: $INFO_PATH" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  MOD_NAME="$(jq -r '.name' "$INFO_PATH")"
  VERSION="$(jq -r '.version' "$INFO_PATH")"
else
  MOD_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$INFO_PATH" | head -n 1)"
  VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$INFO_PATH" | head -n 1)"
fi

if [[ -z "$MOD_NAME" || -z "$VERSION" || "$MOD_NAME" == "null" || "$VERSION" == "null" ]]; then
  echo "Failed to read name/version from info.json" >&2
  exit 1
fi

echo "Building release for $MOD_NAME v$VERSION"

RELEASES_DIR="$PROJECT_DIR/releases"
OUTPUT_DIR="$RELEASES_DIR/${MOD_NAME}_${VERSION}"
ZIP_PATH="$RELEASES_DIR/${MOD_NAME}_${VERSION}.zip"

if [[ "$CLEAN" == "true" || -d "$OUTPUT_DIR" ]]; then
  if [[ -d "$OUTPUT_DIR" ]]; then
    echo "Removing existing release directory..."
    rm -rf "$OUTPUT_DIR"
  fi
  if [[ -f "$ZIP_PATH" ]]; then
    echo "Removing existing zip file..."
    rm -f "$ZIP_PATH"
  fi
fi

mkdir -p "$OUTPUT_DIR"

FILES_TO_INCLUDE=(
  "info.json"
  "control.lua"
  "data-final-fixes.lua"
  "settings.lua"
  "changelog.txt"
  "thumbnail.png"
  "LICENSE"
)

DIRS_TO_INCLUDE=(
  "locale"
  "prototypes"
  "modules"
)

PATHS_TO_EXCLUDE=(
  "modules/tests.lua"
)

echo
echo "Copying files:"
for file in "${FILES_TO_INCLUDE[@]}"; do
  source_path="$PROJECT_DIR/$file"
  if [[ -f "$source_path" ]]; then
    cp "$source_path" "$OUTPUT_DIR/"
    echo "  + $file"
  else
    echo "  - $file (not found, skipping)"
  fi
done

echo
echo "Copying directories:"
for dir in "${DIRS_TO_INCLUDE[@]}"; do
  source_path="$PROJECT_DIR/$dir"
  if [[ -d "$source_path" ]]; then
    dest_path="$OUTPUT_DIR/$dir"
    cp -R "$source_path" "$dest_path"

    find "$dest_path" -type f -name "Thumbs.db" -delete 2>/dev/null || true

    file_count="$(find "$dest_path" -type f | wc -l | tr -d ' ')"
    echo "  + $dir/ ($file_count files)"
  else
    echo "  - $dir/ (not found, skipping)"
  fi
done

echo
echo "Applying exclusions:"
for excluded_path in "${PATHS_TO_EXCLUDE[@]}"; do
  target_path="$OUTPUT_DIR/$excluded_path"
  if [[ -e "$target_path" ]]; then
    rm -rf "$target_path"
    echo "  - $excluded_path"
  else
    echo "  - $excluded_path (not present)"
  fi
done

if [[ "$NO_ZIP" != "true" ]]; then
  echo
  echo "Creating zip archive..."

  rm -f "$ZIP_PATH"
  (
    cd "$RELEASES_DIR"
    zip -r "$(basename "$ZIP_PATH")" "$(basename "$OUTPUT_DIR")" >/dev/null
  )

  if [[ -f "$ZIP_PATH" ]]; then
    zip_kb="$(du -k "$ZIP_PATH" | cut -f1)"
    echo "  Created: $ZIP_PATH (${zip_kb} KB)"
  fi
fi

echo
echo "========================================"
echo "Release build complete!"
echo "========================================"
echo "Output directory: $OUTPUT_DIR"
if [[ "$NO_ZIP" != "true" ]]; then
  echo "Zip file: $ZIP_PATH"
fi

echo
echo "Release contents:"
while IFS= read -r path; do
  relative_path="${path#$OUTPUT_DIR/}"
  if [[ -d "$path" ]]; then
    echo "  [DIR]  $relative_path/"
  elif [[ -f "$path" ]]; then
    echo "  [FILE] $relative_path"
  fi
done < <(find "$OUTPUT_DIR" -mindepth 1 | sort)
