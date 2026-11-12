# Scaling Laws — build spec (contract for all agents)

Pixel-art incremental game: run an AI lab from a garage to AGI. Godot 4.7 (GDScript only).
Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (referred to as `$GODOT`).
macOS desktop first; Android later → pointer-first input (mouse == touch, no hover-only or
keyboard-only features), responsive layout, no fixed resolution.
**Nothing stubbed.** Every feature must be implemented and playable end to end.
Agents: do NOT `git commit` (the orchestrator commits). Only touch files in your task's scope.
Keep code small and boring; no speculative abstractions.

## Game design (authoritative)

PRODUCERS — 12 tiers; cost = base * 1.15^owned; milestone multipliers at 25/50/100/200 owned.
ids: intern_laptop, cloud_gpus, server_rack, data_centre, custom_silicon, hyperscale_campus,
fusion_plant, orbital_cluster, lunar_foundry, dyson_swarm, matrioshka_brain, universe_simulator.
Output is Compute (FLOPs); Cash is a secondary currency (producers are bought with cash; compute
earns cash through a passive "inference revenue" conversion; compute itself is spent on training).
Training Runs: spend compute to train a model, scored by data quality and architecture; a higher
score gives a permanent (for the current layer-2 generation; best score carries a reduced bonus
across resets) multiplier. Runs take time and can fail (failure chance shown up front).

RESET LAYERS (each: new currency, longer horizon, new mechanic; resets never delete all benefit)
1. Funding Round (~30 min) → Equity. Unlocks Hiring: researchers, engineers, ops, distinct bonuses.
2. Model Generation (~4 h) → Insights. Unlocks a Research Tree with mutually exclusive
   architecture branches, and an Alignment-vs-Capability slider.
3. Paradigm Shift (~1–2 days) → Breakthroughs. Unlocks Data, Energy and Alignment resources that
   constrain compute, plus automation of earlier layers (auto-buy, auto-train, auto-fund, auto-gen).
4. Singularity (multi-day) → Legacy. Unlocks rival labs, regulation challenges, and the final AGI
   sequence with three endings (aligned / rushed / open-sourced).
Gain = floor(sqrt(lifetime/threshold)); UI highlights the reset when gain >= 2x current holding.

SYSTEMS
- Benchmarks: auto-unlocking achievements with permanent bonuses.
- Events: rival launches, regulation, talent poaching; short choices with trade-offs; neglected
  alignment worsens later events.
- Offline progress: 24h cap, 50% efficiency, "while you were away" summary.

TECHNICAL
- Big-number class (mantissa+exponent); suffix (K, M, B, T, Qa…) then scientific notation.
- Content as Godot Resources (.tres) so adding content needs no code.
- Versioned JSON save in user://. Strict persistent/run state split.
- Headless simulator that plays hours with a scripted strategy and checks pacing
  (no unlock deserts, sensible time to each reset).
- GUT tests for economy, prestige, reset purity and save/load, all passing.

VISUALS
- Pixel art, one shared palette (`art/palette.hex`, one RRGGBB per line). UI colours come ONLY
  from this palette.
- project.godot: stretch mode canvas_items, aspect expand, base viewport 640x360, default texture
  filter nearest, window resizable. UI built from anchored Control nodes in containers.
- Side-view lab cutaway that grows with each tier; late tiers zoom out to orbit, a swarm and a
  simulated universe. A reset collapses the scene and keeps one legacy prop per layer.
- Ambient looping animations, event animations, pixel UI theme, tweened number ticks and purchase
  pops, a prestige transition, and a `reduce_motion` setting.

## Layout

```
project.godot
src/core/      pure logic (RefCounted/Resource, no scene tree; runs headless)
src/defs/      Resource scripts (class_name ...Def) for content
src/autoload/  Game (state + tick + signals), Content (loads res://content/**.tres), SaveSystem
content/<type>/*.tres    producers, layers, staff, research, events, benchmarks, rivals, challenges…
src/ui/        main.tscn (main scene), theme/, panels/<name>.tscn (+ .gd), widgets/
src/lab/       lab_view.tscn (+ .gd) — the cutaway scene, instanced by main.tscn
assets/        processed game-ready PNGs (see manifest)
art/           palette.hex, style_ref, raw generations, README
tools/         simulate.gd (headless sim), art/ (python pipeline)
tests/         GUT tests (addons/gut vendored)
docs/API.md    the core API the UI codes against (written by the core agent)
```

## Asset manifest (final paths; sizes in px; transparent bg unless noted)

- `assets/rooms/<producer_id>.png` ×12 — 192x128. Tiers 1–6 are building interiors (opaque room
  interior, fills the frame); tiers 7–12 are exterior/space set-pieces on transparent bg.
- `assets/shell/floor.png` 208x144 — one building-floor frame (walls/slab with transparent 192x128
  hole in the middle, 8 px border); `assets/shell/roof.png` 208x32; `assets/shell/ground.png` 208x32 (opaque).
- `assets/workers/{researcher,engineer,ops}.png` — 32x48 standing sprite.
- `assets/icons/<id>.png` 32x32 — compute, cash, equity, insights, breakthroughs, legacy, data,
  energy, alignment, capability, training, hiring, research, benchmarks, events, rivals,
  regulation, automation, settings, agi.
- `assets/events/<category>.png` 192x128 — rival_launch, regulation, poaching, incident,
  breakthrough, media, funding, outage. Opaque illustrations (full-bleed art, no transparent background).
- `assets/badges/{bronze,silver,gold,platinum,diamond,cosmic}.png` 48x48.
- `assets/backdrops/{garage_sky,city,orbit,swarm,universe}.png` 640x360 (opaque).
- `assets/legacy/{funding,generation,paradigm,singularity}.png` 48x48 — the prop kept after a
  reset of that layer (e.g. framed term sheet, old model weights drive, chalkboard, monolith).
- `assets/endings/{aligned,rushed,open_sourced}.png` 320x180 (opaque).
- `assets/intro/{01_idea,02_pizza_box,03_phone_call,04_garage_deal,05_open_for_business}.png` 320x180
  (opaque) — the first-run intro beats, shown by `src/ui/intro.tscn` (`Intro.BEATS` lists them).

Code that loads art must use these exact paths. Until the art lands, missing textures fall back to
a flat palette-coloured rect (dev only; a test asserts every manifest file exists at the end).
