#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT=${GODOT:-$(command -v godot 2>/dev/null || true)}
if [ -z "$GODOT" ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi

cd "$ROOT" || exit 1
passed=0
total=3
[ "${1:-}" = --fast ] || total=4

run_check() {
  name=$1
  shift
  log=$(mktemp "${TMPDIR:-/tmp}/scaling-laws-check.XXXXXX") || exit 1
  if "$@" >"$log" 2>&1; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
    rm -f "$log"
    return 0
  else
    status=$?
    printf 'FAIL %s (exit %s; log: %s)\n' "$name" "$status" "$log"
    printf 'SUMMARY: %s/%s checks passed\n' "$passed" "$total"
    exit "$status"
  fi
}

run_check import "$GODOT" --headless --path . --import
run_check GUT "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit

log=$(mktemp "${TMPDIR:-/tmp}/scaling-laws-check.XXXXXX") || exit 1
if "$GODOT" --headless --path . -s tools/smoke.gd >"$log" 2>&1 && grep -qx 'OK' "$log"; then
  printf 'PASS smoke\n'
  passed=$((passed + 1))
  rm -f "$log"
else
  status=$?
  [ "$status" -ne 0 ] || status=1
  printf 'FAIL smoke (exit %s; log: %s)\n' "$status" "$log"
  printf 'SUMMARY: %s/%s checks passed\n' "$passed" "$total"
  exit "$status"
fi

if [ "${1:-}" != --fast ]; then
  run_check pacing "$GODOT" --headless --path . -s tools/simulate.gd -- --hours=336 --seed=1 --ending=aligned
fi

printf 'SUMMARY: %s/%s checks passed\n' "$passed" "$total"
