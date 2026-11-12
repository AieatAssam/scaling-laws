# Art pipeline

Every game asset is made the same way: the Codex built-in image tool draws a raw PNG
(`tools/art/gen.sh`), then `tools/art/process.py` samples it onto the logical pixel grid, snaps it to
the palette and writes the exact game size. `tools/art/asset.sh` runs both for one manifest asset and
picks the canvas, grid, flags and output path, so you only give a category, an id and a subject.

- Raw files: `art/raw/` (gitignored). Game assets: `assets/` (paths in `SPEC.md`, "Asset manifest").
- Palette: `art/palette.hex` (32 colours). Art uses only these, plus full transparency.
- Previews (x6, nearest): `art/preview/`.

## One-time setup

```sh
python3 -m venv tools/art/.venv && tools/art/.venv/bin/pip install pillow numpy
```

## Quick use

```sh
tools/art/asset.sh <category> <id> "<subject>"        # generate + process -> manifest path
tools/art/asset.sh <category> <id>                    # process only: RAW=art/raw/x.png (no generation)
OUT=art/raw/cand/x.png tools/art/asset.sh ...         # write a candidate instead of the final
FORCE=1 tools/art/asset.sh ...                        # replace an existing final
```

`asset.sh` refuses to overwrite an existing manifest file unless `FORCE=1` or `OUT=` is set. A gen call
takes minutes; processing takes seconds. Calls can run in parallel; give each a unique id.

## Categories

| asset.sh category | Output (manifest) | Grid (art px) | Cell px | Canvas asked | Transparent? | gen flags |
|---|---|---|---|---|---|---|
| `room` | `assets/rooms/<id>.png` 192x128 | 192x128 | 8 | 1536x1024 | no (opaque scene) | `--opaque` |
| `setpiece` | `assets/rooms/<id>.png` 192x128 | 192x128 | 8 | 1536x1024 | yes | none |
| `shell-floor` | `assets/shell/floor.png` 208x144 (id `floor`) | 208x144 | 8 | 1664x1152 | yes, 192x128 hole | none |
| `shell-strip` | `assets/shell/roof.png` 208x32; `ground` 208x32 (opaque) | 208x32 | 8 | 1664x256 | roof yes, ground no | ground: `--opaque` |
| `worker` | `assets/workers/<id>.png` 32x48 | 32x48 | 32 | 1024x1536 | yes | `--noref` |
| `icon` | `assets/icons/<id>.png` 32x32 | 32x32 | 32 | 1024x1024 | yes | none |
| `event` | `assets/events/<id>.png` 192x128 | 192x128 | 8 | 1536x1024 | no (opaque scene) | `--opaque` |
| `badge` | `assets/badges/<id>.png` 48x48 | 48x48 | 20 | 960x960 | yes | none |
| `backdrop` | `assets/backdrops/<id>.png` 640x360 | 320x180 (x2) | 4 | 1280x720 | no | `--opaque` |
| `legacy` | `assets/legacy/<id>.png` 48x48 | 48x48 | 20 | 960x960 | yes | none |
| `ending` | `assets/endings/<id>.png` 320x180 | 320x180 | 4 | 1280x720 | no | `--opaque` |
| `intro` | `assets/intro/<id>.png` 320x180 | 320x180 | 4 | 1280x720 | no | `--opaque` |

The `process.py` flags each category gets (set inside `asset.sh`):

| category | process flags |
|---|---|
| room, event, intro | `--opaque --clean` (intro: no `--canvas`) |
| setpiece | `--clean` |
| shell-floor | `--clean --frame 8` |
| shell-strip roof | `--stretch --clean` |
| shell-strip ground | `--stretch --clean --opaque` |
| worker, icon, badge, legacy | none (grid only) |
| backdrop | `--cell 4 --scale 2 --opaque --clean --canvas 1280x720 --speck3` |
| ending | `--opaque --clean --canvas 1280x720 --speck3` |

## Examples (one per category)

```sh
tools/art/asset.sh room intern_laptop "a young intern with messy brown hair and a teal hoodie sits side-on at a wooden desk in a garage workshop, typing on an open laptop whose teal screen glows; a warm amber desk lamp and a server rack in the background; at most 6 props total"
tools/art/asset.sh setpiece dyson_swarm "a large Dyson swarm: a bright amber star with a ring of small solar panels around it, drawn on the magenta key"
tools/art/asset.sh shell-floor floor "building floor frame: walls and slab around a rectangular hole filled with pure #FF00FF magenta"
tools/art/asset.sh shell-strip roof "a horizontal strip of roof panels with antennae and lights, dark outline, the strip spans the full width"
tools/art/asset.sh shell-strip ground "a horizontal strip of rough dirt-and-rock ground with a brown top edge, fills the whole strip"
tools/art/asset.sh worker ops "one standing character, full body, facing right, 3/4 side view, big head, 4-5 colours of clothes, dark outline"
tools/art/asset.sh icon training "one bold graduation cap icon, 2-3 solid shapes, thick dark outline"
tools/art/asset.sh event funding "a single bold funding event scene: a stack of gold coins beside a rising arrow, dark outline"
tools/art/asset.sh badge gold "one round medal badge, gold rim, dark outline, centred, transparent around it"
tools/art/asset.sh backdrop city "wide opaque city skyline at dusk with distant silhouettes, solid colour steps only, fills whole canvas"
tools/art/asset.sh legacy singularity "one small prop object, a glowing monolith, chunky, dark outline, centred, transparent around it"
tools/art/asset.sh ending aligned "wide opaque scene for an ending card: a calm lit lab with a single glowing sphere, fills whole canvas"
tools/art/asset.sh intro 01_idea "wide opaque scene for one story beat: a lone figure with a sketchbook at a desk in a dim room, fills whole canvas"
```

## Prompt recipe

`gen.sh` wraps the subject in a fixed preamble: use the built-in image tool, make one image, do not
resize or post-process, reply DONE. It then sets the canvas, the logical grid, the cell size, the
hard-edge rules, the style (dark outline #0B0E1A, 3-tone shading, one focal point), the palette list,
the background rule, and `Subject:`. The category sets the direction line; the subject carries the
content. Write one concrete side-view object, name the palette colours, cap the props, keep it bold.
Do not put a fixed content detail (a lamp, a colour scheme) in a category direction: it leaks into every
asset of that category.

Backgrounds: `--opaque` categories (room, event, intro, backdrop, ending) fill the whole canvas.
Transparent categories (setpiece, floor, strip, worker, icon, badge, legacy) draw on flat #FF00FF,
which `process.py` keys out.

## process.py

`process.py <raw> <out> --size WxH [--grid GWxGH] [--cell N] [--canvas WxH] [--scale K] [--opaque]
[--outline] [--clean] [--stretch] [--speck3] [--frame N] [--preview DIR]`

- `--grid` / `--cell`: known-grid mode (the recommended mode). Cells are sampled at the detected lattice
  period, one palette colour per cell, then mapped to exactly `--grid`.
- `--canvas WxH`: nearest-resample the raw to the canvas the prompt asked for, when they differ.
- `--stretch`: no lattice. Maps the whole raw onto `--size` cells, aspect ignored. Keyed input is
  first cropped to its content (so a strip drawn small in a big canvas is not squashed).
- `--clean`: removes isolated shade specks (4-neighbour rule).
- `--speck3`: opaque only. 3x3 majority rule for speckle on backdrops (cells with <= 2 of their own colour
  in their 3x3 window and a colour with >= 5 votes take that colour).
- `--frame N`: floor frame. Extends the frame's outer transparent edge to the canvas from the nearest
  opaque edge cell, then forces the inner hole (N-px border) transparent.
- `--scale K`: integer pixel-doubling after sampling (backdrops: 320x180 art to 640x360).
- `--outline`: 1 px #0B0E1A outline for transparent sprites. Skip it when the model already drew one.
- Output is asserted: exact size, palette colours plus full transparency only, alpha 0 or 255.
- Without `--grid`/`--cell`: detection mode (fallback for raws without a known grid).

## Verification

Checked on the raws in `art/raw/` (process-only, into a temp dir, compared with the file in `assets/`):

| category | sample | result |
|---|---|---|
| room | cloud_gpus, custom_silicon, hyperscale_campus, server_rack | identical |
| setpiece | dyson_swarm | identical |
| shell-floor | floor | identical |
| shell-strip roof | roof | visually equivalent (alpha mismatch 123 px) |
| shell-strip ground | ground | not reproduced (no on-disk raw matches the final) |
| worker | ops, researcher | identical |
| icon | training, cash, compute | not reproduced (no on-disk raw matches the final) |
| event | funding | identical |
| badge | silver, cosmic, gold | identical |
| backdrop | city | identical |
| legacy | singularity, generation, funding | identical |
| ending | aligned | identical |
| intro | 01_idea | near-exact |
| badge (regenerated 2026-11-12) | platinum, diamond | identical on re-run from `art/raw/badge_platinum_1794470828.png`, `art/raw/badge_diamond_1794470828.png` |
| icon (regenerated 2026-11-12) | alignment | identical on re-run from `art/raw/icon_alignment_1794470828.png` |

"Not reproduced" means the final was made from a raw that is no longer in `art/raw/`, or from an earlier
prompt. The pipeline still produces a usable asset from the current raw; regenerate to get a matching one.

## Pitfalls

- The model does not honour the requested grid counts. `process.py` maps the cells it drew onto `--grid`,
  so the output is usable, but the detail is set by what the model drew.
- The model does not honour the requested canvas. The `city` backdrop raw came back at 1672x941 for a
  1280x720 request. Backdrop and ending use `--canvas 1280x720`, which resamples to that canvas first.
  For floor, adding `--canvas` made the match worse, so asset.sh does not pass it there.
- The model does not honour strip canvas shapes. Use `--stretch` for roof and ground: it crops keyed
  content first, which avoids the squashed sliver of a plain stretch.
- Non-square lattice on some icons: lattice detection can fail, and process warns "no regular cell
  lattice" and box-samples. Check the x6 preview; if it is blurred, regenerate with a bolder subject.
- The style ref crowds sprites (gen.sh comment: it shrank the worker's face and added props to the icon).
  Sprites default to `--noref`. Scenes use the ref (`art/style_ref.png`).
- `--outline` adds a 1 px outline; skip it when the model already drew one.
- `codex exec` waits on stdin unless stdin is `/dev/null`; `gen.sh` does this.
- Events are opaque scenes (the finals are fully opaque, unlike `SPEC.md`'s "transparent unless noted").
