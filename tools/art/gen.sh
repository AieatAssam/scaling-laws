#!/usr/bin/env bash
# Usage: tools/art/gen.sh <out_raw.png> "<subject prompt>" <category> [--opaque] [--ref|--noref]
#   category: room | setpiece | event | worker | icon | badge | legacy | floor | strip | backdrop | ending | intro
#   Usually called through tools/art/asset.sh, which also picks the flags and the output path.
# Generates ONE asset via `codex exec` (built-in image tool) and copies the raw PNG to <out_raw.png>.
# The prompt fixes the logical grid AND the canvas (exact integer cell size), so process.py can
# sample cells without guessing. Raw output is NOT game-ready: run tools/art/process.py next
# (see art/README.md for the matching --cell/--scale/--size per category).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ARG="${1:?out_raw.png required}"; SUBJECT="${2:?subject prompt required}"
CAT="${3:?category required: room|setpiece|event|worker|icon|badge|legacy|floor|strip|backdrop|ending|intro}"
shift 3
OPAQUE=""; REF_FLAG=""
for a in "$@"; do case "$a" in --opaque) OPAQUE=1;; --noref) REF_FLAG=no;; --ref) REF_FLAG=yes;; *) echo "unknown flag $a" >&2; exit 2;; esac; done

# category -> "logical grid WxH|cell px|canvas WxH|direction"
case "$CAT" in
  room)     SPEC="192x128|8|1536x1024|building interior seen side-on in cutaway, the room fills the whole frame, one dominant machine or structure as the focal point; the subject text names everything else" ;;
  setpiece) SPEC="192x128|8|1536x1024|one large exterior or space object drawn on the magenta key, filling about 85 percent of the canvas, centred, no starfield, no background scenery, no ground unless the subject needs it" ;;
  event)    SPEC="192x128|8|1536x1024|single bold event scene with one focal symbol, centred, 2-3 big shapes, dark outline" ;;
  worker)   SPEC="32x48|32|1024x1536|one standing character, full body, facing right, 3/4 side view, big head, 4-5 colours of clothes, dark outline" ;;
  icon)     SPEC="32x32|32|1024x1024|one bold icon, 2-3 solid shapes, thick dark outline, no thin lines under 2 art pixels, centred with 2 art pixel margin" ;;
  badge)    SPEC="48x48|20|960x960|one round or shield-shaped medal badge, rim in metal colour, dark outline, centred, transparent around it" ;;
  legacy)   SPEC="48x48|20|960x960|one small prop object, chunky, dark outline, centred, transparent around it" ;;
  floor)    SPEC="208x144|8|1664x1152|building floor frame: walls and slab around a rectangular hole filled with pure #FF00FF magenta (the key colour, exactly the middle 192x128 art pixels, 8 art pixels border on every side)" ;;
  strip)    SPEC="208x32|8|1664x256|a horizontal strip of panels with lights, dark outline, the strip spans the full width" ;;
  backdrop) SPEC="320x180|4|1280x720|wide opaque sky/space backdrop, distant silhouettes, soft-looking but pixel-blocky gradient bands made of solid steps only, fills whole canvas" ;;
  ending)   SPEC="320x180|4|1280x720|wide opaque scene for an ending card, one focal scene, fills whole canvas" ;;
  intro)    SPEC="320x180|4|1280x720|wide opaque scene for one story beat, one focal scene, fills whole canvas" ;;
  *) echo "unknown category $CAT" >&2; exit 2 ;;
esac
IFS='|' read -r GRID CELL CANVAS DIRECTION <<<"$SPEC"
GW="${GRID%x*}"; GH="${GRID#*x}"; CW="${CANVAS%x*}"; CH="${CANVAS#*x}"

mkdir -p "$(dirname "$OUT_ARG")"
OUT="$(cd "$(dirname "$OUT_ARG")" && pwd)/$(basename "$OUT_ARG")"
PAL="$(awk 'NF{printf "#%s ", $1}' "$ROOT/art/palette.hex")"

if [[ -n "$OPAQUE" ]]; then
  BG="Fill the ENTIRE canvas with the scene (opaque, no magenta, no empty border, no margin)."
else
  BG="Background: flat solid pure magenta #FF00FF filling everything outside the asset, no shadow, no gradient, no texture on it. The subject must not contain #FF00FF."
fi

PROMPT="Use your built-in image generation tool (NOT any script, CLI or API fallback). Generate exactly one image. Do NOT resize, convert, crop, copy or post-process it. Reply with the single word DONE.

Canvas: exactly ${CW} x ${CH} pixels.
Pixel grid: the art is a ${GW} x ${GH} pixel grid. Every art pixel is an exact ${CELL} x ${CELL} pixel square block, aligned to the canvas from the top-left corner, so the grid is ${GW} columns by ${GH} rows of blocks. Hard edges only: no anti-aliasing, no gradients, no dithering noise, no blur, no soft glow, no sub-block detail, no text, no letters, no numbers, no watermark.
Style: crisp retro pixel art, cosy purple/teal/amber sci-fi look, flat side view (orthographic), a clear silhouette with a 1-art-pixel dark outline (#0B0E1A) around the main shapes, 3-tone shading per material (base, shadow, highlight), one readable focal point. ${DIRECTION}.
Use ONLY these colours (hex): ${PAL}
${BG}
Subject: ${SUBJECT}"

# The style ref helps scenes (consistent palette/lighting) but crowds small sprites: it made the
# worker's face smaller and added props to the icon. Sprites default to --noref; scenes use it.
ATTACH=()
case "$CAT" in room|floor|strip|backdrop|ending|intro) REF_DEFAULT=yes ;; *) REF_DEFAULT=no ;; esac
USE_REF="${REF_FLAG:-$REF_DEFAULT}"
if [[ "$USE_REF" == yes && -f "$ROOT/art/style_ref.png" ]]; then ATTACH=(--image="$ROOT/art/style_ref.png"); fi

LOG="${OUT%.png}.log"
printf '%s\n' "$PROMPT" > "${OUT%.png}.prompt.txt"   # full prompt kept beside the raw, for reproducibility
EVENTS="$(mktemp)"
codex exec --json --skip-git-repo-check -s read-only -C "$ROOT/art/raw" ${ATTACH[@]+"${ATTACH[@]}"} "$PROMPT" </dev/null >"$EVENTS" 2>"$LOG" || { echo "codex exec failed, see $LOG" >&2; cat "$EVENTS" >&2; exit 1; }

THREAD="$(sed -n 's/.*"thread_id":"\([^"]*\)".*/\1/p' "$EVENTS" | head -1)"
GEN_DIR="$HOME/.codex/generated_images/$THREAD"
SRC="$(ls -t "$GEN_DIR"/*.png 2>/dev/null | head -1 || true)"
if [[ -z "$THREAD" || -z "$SRC" ]]; then
  echo "no generated image for thread '$THREAD' in $GEN_DIR; see $LOG" >&2; exit 1
fi
cp "$SRC" "$OUT"
rm -f "$EVENTS"
echo "$OUT (asked: grid ${GRID}, cell ${CELL}, canvas ${CANVAS})"
