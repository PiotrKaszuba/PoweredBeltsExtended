#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AAI_MOD_PATH="${PBE_AAI_MOD_PATH:-}"
SKIP_AAI=0
SKIP_SYNTAX=0
SKIP_COMPILE=0
INTEGRATION_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aai-mod-path)
      AAI_MOD_PATH="$2"
      shift 2
      ;;
    --skip-aai)
      SKIP_AAI=1
      shift
      ;;
    --skip-syntax)
      SKIP_SYNTAX=1
      shift
      ;;
    --skip-compile)
      SKIP_COMPILE=1
      shift
      ;;
    --)
      shift
      INTEGRATION_ARGS+=("$@")
      break
      ;;
    *)
      INTEGRATION_ARGS+=("$1")
      shift
      ;;
  esac
done

run_step() {
  local name="$1"
  shift
  echo "==> $name"
  "$@"
}

if [[ $SKIP_SYNTAX -eq 0 ]]; then
  run_step "Lua syntax checks" lua -e "assert(loadfile('control.lua')); assert(loadfile('modules/compatibility.lua')); assert(loadfile('modules/undergrounds.lua')); assert(loadfile('tests/integration/harness_mod/lib/runtime.lua')); assert(loadfile('tests/integration/harness_mod/lib/assertions.lua')); assert(loadfile('tests/integration/harness_mod/lib/world.lua')); assert(loadfile('tests/integration/harness_mod/scenarios.lua')); print('lua syntax ok')"
fi

if [[ $SKIP_COMPILE -eq 0 ]]; then
  run_step "Python compile checks" python -m compileall tests/integration/python
fi

run_step "Integration suite (baseline: no AAI extra mod)" python -m tests.integration.python.run_integration "${INTEGRATION_ARGS[@]}"

if [[ $SKIP_AAI -eq 0 ]]; then
  if [[ -z "$AAI_MOD_PATH" ]]; then
    echo "Warning: skipping AAI integration runs (no AAI mod path; set PBE_AAI_MOD_PATH or pass --aai-mod-path)." >&2
  elif [[ ! -e "$AAI_MOD_PATH" ]]; then
    echo "AAI mod path does not exist: $AAI_MOD_PATH" >&2
    exit 2
  else
    run_step "Integration suite (AAI lubricated mode)" python -m tests.integration.python.run_integration --mod-state enabled --extra-mod-path "$AAI_MOD_PATH" --aai-mode lubricated "${INTEGRATION_ARGS[@]}"
    run_step "Integration suite (AAI expensive mode)" python -m tests.integration.python.run_integration --mod-state enabled --extra-mod-path "$AAI_MOD_PATH" --aai-mode expensive "${INTEGRATION_ARGS[@]}"
  fi
fi
