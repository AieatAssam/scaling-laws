#!/bin/sh
# Ending order check: on each seed (1-3, 336 h), the rushed AGI ending comes at least 5% sooner than open-sourced,
# and open-sourced at least 5% sooner than aligned. Every run must reach the ending it was asked for.
# Exits 1 on any violation. Seeds 4-6 are printed for information only.
#   tools/ending_order.sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT=${GODOT:-$(command -v godot 2>/dev/null || true)}
if [ -z "$GODOT" ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
cd "$ROOT" || exit 1

OUT=$(mktemp -d "${TMPDIR:-/tmp}/scaling-laws-endings.XXXXXX") || exit 1
status=0

# time_of SEED ENDING -> sets T to the AGI ending day, or "none" when the run did not reach the wanted ending.
# A run that fails its simulator gates or misses its ending counts against seeds 1-3 only.
time_of() {
  seed=$1
  ending=$2
  log="$OUT/s${seed}_${ending}.log"
  run_ok=1
  if ! "$GODOT" --headless --path . -s tools/simulate.gd -- --hours=336 --seed="$seed" --ending="$ending" >"$log" 2>&1; then
    run_ok=0
  fi
  line=$(grep '^ending:' "$log" | head -n 1)
  case "$line" in
    "ending: $ending at "*)
      T=$(printf '%s' "$line" | awk '{ print $4 }')
      ;;
    *)
      T=none
      run_ok=0
      ;;
  esac
  if [ "$run_ok" -eq 0 ] && [ "$seed" -le 3 ]; then
    printf 'FAIL seed %s %s: %s (log: %s)\n' "$seed" "$ending" "${line:-no ending line}" "$log" >&2
    status=1
  fi
}

printf '%-6s %10s %10s %10s  %s\n' seed rushed open_sourced aligned order
for seed in 1 2 3 4 5 6; do
  time_of "$seed" rushed; r=$T
  time_of "$seed" open_sourced; o=$T
  time_of "$seed" aligned; a=$T
  verdict=ok
  if [ "$seed" -le 3 ]; then
    if [ "$r" = none ] || [ "$o" = none ] || [ "$a" = none ]; then
      verdict="FAIL (missing ending)"
      status=1
    elif ! awk -v r="$r" -v o="$o" -v a="$a" 'BEGIN { exit !(r <= 0.95 * o && o <= 0.95 * a) }'; then
      verdict="FAIL (order or 5% gap)"
      status=1
    fi
  else
    verdict="info only"
  fi
  printf '%-6s %10s %10s %10s  %s\n' "$seed" "$r" "$o" "$a" "$verdict"
done

if [ "$status" -eq 0 ]; then
  printf 'PASS ending order (seeds 1-3)\n'
else
  printf 'FAIL ending order (logs: %s)\n' "$OUT"
fi
exit "$status"
