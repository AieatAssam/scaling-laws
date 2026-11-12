# Art pipeline

Generate with the Codex built-in image tool, then convert to a game-ready PNG.
Palette: `art/palette.hex` (32 colours, shared by everything). Style ref: `art/style_ref.png`.

## Commands

```sh
# one-time
python3 -m venv tools/art/.venv && tools/art/.venv/bin/pip install pillow numpy

# generate raw (≈30–70 s per call, writes art/raw/<name>.png, log in art/raw/<name>.log)
tools/art/gen.sh art/raw/compute_icon.png "a single small microchip icon ..." 16x16
tools/art/gen.sh art/raw/intern_laptop.png "side-view cutaway of a garage ..." 96x64 --opaque

# process to game asset (+ optional x6 preview)
tools/art/.venv/bin/python tools/art/process.py art/raw/compute_icon.png assets/icons/compute.png --size 16x16 --preview art/preview
tools/art/.venv/bin/python tools/art/process.py art/raw/intern_laptop.png assets/rooms/intern_laptop.png --size 96x64 --opaque --preview art/preview
```

`gen.sh <out_raw.png> "<subject>" [WxH] [--opaque]`: one asset per call. Attaches `art/style_ref.png`
when present. Raw output is never game-ready; always run `process.py`.

## How it works

- `gen.sh` runs `codex exec --json -s read-only` with a fixed style preamble (palette hex list,
  chunky pixels, no AA/gradients/text, flat #FF00FF key or opaque fill, aspect hint). It takes the
  `thread_id` from the JSON event stream and copies the newest `~/.codex/generated_images/<thread_id>/*.png`.
- `process.py`: keys magenta (distance < 120 from #FF00FF, so fringe goes too) → crops to content →
  finds the model's own pixel grid (edge positions → largest lattice period with circular
  concentration ≥ 0.85, then least-squares refine). If the model's grid is regular, one palette
  mode per cell; otherwise (freehand grid) it box-samples straight to the target size. Then fit
  (aspect kept, transparent pad) or exact resize (`--opaque`), and palette quantise. Asserts exact
  size, only palette colours, alpha ∈ {0,255}.

## Prompt recipe that worked

Preamble (in gen.sh): "Use your built-in image generation tool (NOT any script, CLI or API fallback).
Generate exactly one image. Do NOT resize, convert, crop, copy or post-process it. Reply DONE."
then style, palette, background, and `Subject:`. The style ref (160x90 cutaway) gives a consistent look.
Keep subjects concrete: side view, one asset, named colours from the palette.

## Pitfalls

- Without the "do not resize" instruction the model resized its output with `sips` (raw destroyed).
- Native output is ~1024–1672 px wide, not the target size. The model draws its own "fake" pixels
  (≈16–28 cells across for a 16x16 request). Grid detection is only exact when the model drew a regular grid
  (the heart: yes; the 16x16 chip icon: no, it fell back to box sampling).
- `-i` is variadic, so the style ref is passed as `--image=PATH`, not `-i PATH`, so the prompt isn't eaten as a file.
- `codex exec` waits on stdin unless stdin is `/dev/null`. gen.sh does this.
- The style ref had a cat and a robot; the model adds extra props. Check the output and regenerate if they sneak into a small asset.
- Icons at 16x16 lose thin details (pins become 1px). Keep icon subjects bold and simple.
- Model used for images is whatever the Codex built-in tool uses; the `-m` flag is not passed (it selects the agent, not the image model), so `gpt-image-2.6` is not verified here.

## Timing and parallelism

- gen.sh: ~30–35 s per call alone (icon); ~70 s for the 96x64 room while a second call ran concurrently
  (both launched together). Runs are independent (separate thread dirs), so parallel generation works; expect slower per-call times when run concurrently.
- process.py: <1 s for 16x16 sources, a few seconds for the 1536 px room.

## Status

- Tested: `assets/rooms/intern_laptop.png` (96x64 opaque, reads as an intern at a laptop in a garage),
  `assets/icons/compute.png` (16x16 chip, readable but coarse). Previews in `art/preview/`.
- Known issues: laptop/screen details blur into blobs at 96x64; icon pins are thin. Prompts can be
  rerun (no blind retries: change the subject or style deliberately).
