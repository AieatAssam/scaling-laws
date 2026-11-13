# Scaling Laws

A pixel-art incremental game about running an AI lab from a garage to AGI. Godot 4.7, GDScript.

**Play in the browser:** https://aieatassam.github.io/scaling-laws/ ·
**Downloads:** [Releases](https://github.com/AieatAssam/scaling-laws/releases) (macOS, Windows, Linux, Web, Android debug APK)

Twelve producer tiers lead from an intern laptop to a universe simulator. Train fine-tune,
standard and frontier runs for score and success cash bursts; hire staff, research papers at the
desk, and buy run-scoped lab upgrades. Four reset layers unlock launch boosts, breaking-news
rewards, permanent moonshots and automation. At the Singularity, full safety evaluations,
community red-teaming or shipping early decide the ending; race rival labs and take three tiers of
regulation challenges. The HUD highlights Scale and the current goal; Statistics tracks completion,
records and lifetime counters. A first-run intro, contextual tooltips, Help, and one-time "New:"
cards explain systems as they unlock. Touch and mouse drag-scroll panels. Desktop shortcuts: 1–9
select tabs, B cycles producer buy amount, Space/Enter confirms a dialog. See [SPEC.md](SPEC.md)
for the game design and [docs/API.md](docs/API.md) for code details. Saves use versioned migrations
and keep a rolling backup for recovery.

## Run

Open the folder in Godot 4.7 and press Play, or:

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --path . --import   # once, on a fresh checkout
$GODOT --path .
```

Release builds are unsigned or ad-hoc signed:

- **macOS** — not notarized. Right-click → Open, or `xattr -dr com.apple.quarantine "Scaling Laws.app"`.
- **Windows** — keep the `.exe` and `.pck` in the same folder.
- **Linux** — `chmod +x ScalingLaws.x86_64`, with the `.pck` beside it.
- **Android** — debug-signed arm64 APK; enable "install unknown apps".

## Test

```sh
# Import resources and scripts first
$GODOT --headless --path . --import
# GUT unit tests (economy, progression, UI helpers, saves, offline, events, content)
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
# Core smoke test
$GODOT --headless --path . -s tools/smoke.gd
# Pacing simulator: 14 days with a scripted strategy
$GODOT --headless --path . -s tools/simulate.gd -- --hours=336 --seed=1 --ending=aligned
# Focused pacing and balance reports
$GODOT --headless --path . -s tools/reward_gaps.gd
$GODOT --headless --path . -s tools/training_balance.gd
# Check ending ordering in the source data
tools/ending_order.sh
# Full suite (or --fast to skip long pacing reports)
tools/check.sh
```

`tools/check.sh` runs import, GUT and smoke checks; without `--fast` it also runs the simulator and training balance report. It fails on Godot script parse/load errors even if the runner exits successfully. CI runs the checks on every push. Pushing a `vX.Y.Z` tag builds every platform, publishes a
GitHub Release and deploys the web build to Pages; bump `config/version` in `project.godot` and
the version fields in `export_presets.cfg` to match the tag first.

## Adding content

Everything is a Godot Resource under `content/<type>/*.tres` (producers, layers, staff, research,
events, benchmarks, rivals, challenges, AGI stages, endings). Drop in a new `.tres`; no code
needed. The condition and effect keys are listed in `docs/API.md`.

## Art

All sprites were generated through the Codex CLI image tool and post-processed (pixel-grid
detection, one colour per cell, quantised to the shared palette in `art/palette.hex`, chroma key
removed). Commands and the prompt recipe are in [art/README.md](art/README.md).

## What remains for Android

The game is pointer-first and responsive (360x640 base viewport, portrait and landscape), and CI
produces an arm64 debug APK. A real Android release still needs:

- Install and play on a physical device. Pause/resume offline credit, Android Back and safe-area
  insets are implemented, but still need device verification.
- A release keystore and signing config (CI signs with a throwaway debug key), plus an AAB for Play.
- Adaptive launcher icons; only a single PNG icon exists.
- A 32-bit ARM / x86_64 build if those devices matter (only arm64-v8a is exported).

## Licence

Code is MIT (see [LICENSE](LICENSE)). The bundled font is Press Start 2P under the SIL Open Font
Licence (`assets/fonts/`).
