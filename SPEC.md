# Scaling Laws — build spec (contract for all agents)

Pixel-art incremental game: run an AI lab from a garage to AGI. Godot 4.7 (GDScript only), 360x640
base viewport, Press Start 2P font, ASCII UI text and palette-only colours.
Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (referred to as `$GODOT`).
macOS desktop first; Android later → pointer-first input (mouse == touch, no hover-only or
keyboard-only features), responsive layout, no fixed resolution.
**Nothing stubbed.** Every feature must be implemented and playable end to end.
Agents: do NOT `git commit` (the orchestrator commits). Only touch files in your task's scope.
Keep code small and boring; no speculative abstractions.

## Game design (authoritative)

PRODUCERS — 12 tiers; cost grows with ownership; milestone multipliers at 25/50/100/200 owned.
ids: intern_laptop, cloud_gpus, server_rack, data_centre, custom_silicon, hyperscale_campus,
fusion_plant, orbital_cluster, lunar_foundry, dyson_swarm, matrioshka_brain, universe_simulator.
Output is Compute (FLOPs); Cash comes from production and is spent on producers, staff and upgrades.
Training has Fine-tune (cash burst), Standard and Frontier runs; runs spend compute, need data and
energy after a Paradigm Shift, take time, can fail, and successful runs improve the generation's
compute bonus. The best score also gives a reduced bonus across resets.

RESET LAYERS (each: new currency, longer horizon, new mechanic; resets never delete all benefit)
1. Funding Round (~30 min) → Equity. Unlocks Hiring: researchers, engineers, ops, distinct bonuses.
2. Model Generation → Insights. Unlocks the research tree, mutually exclusive model branches,
   the alignment slider and a desk that offers papers with selectable effects.
3. Paradigm Shift → Breakthroughs. Adds Data and capped Energy for training, automation, and
  long-running moonshots whose rewards survive resets. Launch actions give timed boosts and
   cooldowns; the Launch Pad moonshot shortens them.
4. Singularity → Legacy. Unlocks rival labs, three challenge tiers and five sequential AGI stages.
   Keeps unspent Breakthroughs and in-progress moonshots; Data and Energy reset. Paradigm upgrades
   still reset. The final AGI stage starts no earlier than day 9 after Ship, day 9.5 after Red-team,
   or day 11 after Full eval.
   Each stage can be cleared by an instant Ship it, a 6h community red-team or a 12h full safety
   evaluation. The majority choice determines the ending; ties go to the last choice.
Gain = floor(sqrt(lifetime/threshold)); UI highlights the reset when gain >= 2x current holding.

SYSTEMS
- Benchmarks: auto-unlocking achievements with permanent bonuses.
- Events and breaking news: short event choices have trade-offs; timed news chips can be caught for
  cash, compute or temporary boosts.
- Offline progress: 24h cap, 50% efficiency, "while you were away" summary.
- Rival race actions can delay or slow rivals; outpacing a rival records the achievement.
- The HUD shows the Scale headline, current goal rail and Stats screen. Reveal cards appear once as
  systems become available. Touch and mouse can drag-scroll panels; desktop hotkeys select tabs,
  cycle producer quantity and confirm dialogs.

TECHNICAL
- Big-number class (mantissa+exponent); suffix (K, M, B, T, Qa…) then scientific notation.
- Content as Godot Resources (.tres) so adding content needs no code.
- Version 9 JSON saves in `user://`, with rolling `.bak` files, recovery and sequential migrations.
- Headless tools: `simulate.gd` (scripted 14-day run), `reward_gaps.gd`, `ending_order.sh`,
  `training_balance.gd` and `check.sh`.
- GUT tests for economy, prestige, reset purity and save/load, all passing.

VISUALS
- Pixel art, one shared palette (`art/palette.hex`, one RRGGBB per line). UI colours come ONLY
  from this palette.
- project.godot: stretch mode canvas_items, aspect expand, base viewport 360x640, default texture
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
