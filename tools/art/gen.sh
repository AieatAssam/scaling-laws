#!/usr/bin/env bash
# Usage: tools/art/gen.sh <out_raw.png> "<subject prompt>" [WxH] [--opaque]
# Generates ONE asset via `codex exec` (built-in image tool) and copies the raw PNG to <out_raw.png>.
# Raw output is NOT game-ready: run tools/art/process.py on it next.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ARG="${1:?out_raw.png required}"; SUBJECT="${2:?subject prompt required}"
SIZE="${3:-16x16}"; OPAQUE="${4:-}"
W="${SIZE%x*}"; H="${SIZE#*x}"

mkdir -p "$(dirname "$OUT_ARG")"
OUT="$(cd "$(dirname "$OUT_ARG")" && pwd)/$(basename "$OUT_ARG")"
PAL="$(awk 'NF{printf "#%s ", $1}' "$ROOT/art/palette.hex")"

if [[ "$OPAQUE" == "--opaque" ]]; then
  BG="Fill the ENTIRE canvas with the scene (opaque interior, no magenta, no empty border)."
else
  BG="Background: flat solid pure magenta #FF00FF filling everything outside the asset, no shadow, no gradient, no texture on it."
fi

PROMPT="Use your built-in image generation tool (NOT any script, CLI or API fallback). Generate exactly one image. Do NOT resize, convert, crop, copy or post-process it. Reply with the single word DONE.

Style: crisp pixel art, chunky clean square pixels on a visible grid, drawn as about ${W} x ${H} pixels, no anti-aliasing, no gradients, no dithering, no blur or soft glow, no text or letters or watermark. Flat side view (orthographic), single asset centred with a small margin. Canvas aspect ratio ${W}:${H}.
Use ONLY these colours (hex): ${PAL}
${BG}
Subject: ${SUBJECT}"

ATTACH=()
[[ -f "$ROOT/art/style_ref.png" ]] && ATTACH=(--image="$ROOT/art/style_ref.png")

LOG="${OUT%.png}.log"
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
echo "$OUT"
