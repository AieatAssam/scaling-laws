#!/usr/bin/env bash
# asset.sh <category> <id> "<subject>"
#   Generate one manifest asset (gen.sh) and process it (process.py) with the flags, canvas and
#   output path that category needs. Output is the manifest path (see SPEC.md "Asset manifest").
#
# Categories: room setpiece shell-floor shell-strip worker icon event badge backdrop legacy ending intro
#   shell-floor takes id "floor"; shell-strip takes id "roof" or "ground" (ground is opaque).
#
# Env:
#   RAW=<file>     skip generation and process this existing raw (subject not needed)
#   OUT=<file>     write here instead of the manifest path (use for candidates)
#   FORCE=1        allow replacing an existing manifest file (no OUT given)
#   PREVIEW=<dir> x6 preview dir (default art/preview)
# Raw from a generation goes to art/raw/<category>_<id>_<time>.png (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$ROOT/tools/art/.venv/bin/python"
CAT="${1:?category: room|setpiece|shell-floor|shell-strip|worker|icon|event|badge|backdrop|legacy|ending|intro}"
ID="${2:?id, e.g. intern_laptop}"
SUBJ="${3:-}"

GEN_CAT=""; GEN_FLAGS=(); DIR=""; SIZE=""; GRID=""; CANVAS=""; PFLAGS=()
case "$CAT" in
  room)        GEN_CAT=room;     GEN_FLAGS=(--opaque); DIR=rooms;     SIZE=192x128; GRID=192x128; PFLAGS=(--opaque --clean) ;;
  setpiece)    GEN_CAT=setpiece;                       DIR=rooms;     SIZE=192x128; GRID=192x128; PFLAGS=(--clean) ;;
  shell-floor) GEN_CAT=floor;                          DIR=shell;     SIZE=208x144; GRID=208x144; PFLAGS=(--clean --frame 8) ;;
  shell-strip) GEN_CAT=strip;                          DIR=shell;     SIZE=208x32;                PFLAGS=(--stretch --clean) ;;
  worker)      GEN_CAT=worker;   GEN_FLAGS=(--noref); DIR=workers;   SIZE=32x48;  GRID=32x48 ;;
  icon)        GEN_CAT=icon;                           DIR=icons;     SIZE=32x32;   GRID=32x32 ;;
  event)       GEN_CAT=event;    GEN_FLAGS=(--opaque); DIR=events;    SIZE=192x128; GRID=192x128; PFLAGS=(--opaque --clean) ;;
  badge)       GEN_CAT=badge;                          DIR=badges;    SIZE=48x48;   GRID=48x48 ;;
  backdrop)    GEN_CAT=backdrop; GEN_FLAGS=(--opaque); DIR=backdrops; SIZE=640x360; GRID=320x180; CANVAS=1280x720
               PFLAGS=(--cell 4 --scale 2 --opaque --clean --speck3) ;;
  legacy)      GEN_CAT=legacy;                         DIR=legacy;    SIZE=48x48;   GRID=48x48 ;;
  ending)      GEN_CAT=ending;   GEN_FLAGS=(--opaque); DIR=endings;   SIZE=320x180; GRID=320x180; CANVAS=1280x720
               PFLAGS=(--opaque --clean --speck3) ;;
  intro)       GEN_CAT=intro;    GEN_FLAGS=(--opaque); DIR=intro;     SIZE=320x180; GRID=320x180; PFLAGS=(--opaque --clean) ;;
  *) echo "asset.sh: unknown category '$CAT'" >&2; exit 2 ;;
esac
# the ground strip is the one opaque strip
if [[ "$CAT" == shell-strip && "$ID" == ground ]]; then GEN_FLAGS=(--opaque); PFLAGS=(--stretch --clean --opaque); fi

OUT_GIVEN="${OUT:-}"
OUT="${OUT:-$ROOT/assets/$DIR/$ID.png}"
if [[ -z "$OUT_GIVEN" && -e "$OUT" && "${FORCE:-}" != 1 ]]; then
  echo "asset.sh: $OUT exists; set FORCE=1 to replace it, or OUT=<candidate path>" >&2
  exit 1
fi

if [[ -n "${RAW:-}" ]]; then
  echo "process only: $RAW"
else
  [[ -n "$SUBJ" ]] || { echo "asset.sh: subject required (or RAW=<file> to process an existing raw)" >&2; exit 2; }
  RAW="$ROOT/art/raw/${CAT}_${ID}_$(date +%s).png"
  "$ROOT/tools/art/gen.sh" "$RAW" "$SUBJ" "$GEN_CAT" ${GEN_FLAGS[@]+"${GEN_FLAGS[@]}"}
fi

PARGS=(--size "$SIZE")
[[ -n "$GRID" ]] && PARGS+=(--grid "$GRID")
[[ -n "$CANVAS" ]] && PARGS+=(--canvas "$CANVAS")
PARGS+=(${PFLAGS[@]+"${PFLAGS[@]}"})
mkdir -p "$(dirname "$OUT")"
"$PY" "$ROOT/tools/art/process.py" "$RAW" "$OUT" "${PARGS[@]}" --preview "${PREVIEW:-$ROOT/art/preview}"
echo "wrote $OUT  (raw: $RAW)"
