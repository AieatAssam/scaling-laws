# Scaling Laws

A pixel-art incremental game about running an AI lab from a garage to AGI. Godot 4.7, GDScript.

**Play in the browser:** https://aieatassam.github.io/scaling-laws/ ·
**Downloads:** [Releases](https://github.com/AieatAssam/scaling-laws/releases) (macOS, Windows, Linux, Web, Android debug APK)

Twelve producer tiers (intern laptop → universe simulator), training runs, four reset layers
(Funding Round, Model Generation, Paradigm Shift, Singularity), events, benchmarks, offline
progress, and three endings. The design contract is in [SPEC.md](SPEC.md); the core API in
[docs/API.md](docs/API.md).

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
# GUT unit tests (economy, prestige, reset purity, save/load, offline, events, content)
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
# End-to-end smoke test of the core
$GODOT --headless --path . -s tools/smoke.gd
# Pacing simulator: plays 14 days with a scripted strategy and checks reset timing and unlock gaps
$GODOT --headless --path . -s tools/simulate.gd -- --hours=336 --seed=1 --ending=aligned
```

CI runs all three on every push. Pushing a `vX.Y.Z` tag builds every platform, publishes a
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

The game is already pointer-first and responsive (360x640 base viewport, portrait and landscape),
and CI produces a debug APK. Still to do for a real Android release:

- Test on a device: the APK has never been installed or played.
- A release keystore and signing config (CI signs with a throwaway debug key), plus an AAB for Play.
- Safe-area insets (notches, gesture bar) and the Android back button.
- Pause/resume handling: save on `NOTIFICATION_APPLICATION_PAUSED` and apply offline progress on resume.
- Adaptive launcher icons; only a single PNG icon exists.
- A 32-bit ARM / x86_64 build if those devices matter (only arm64-v8a is exported).

## Licence

Code is MIT (see [LICENSE](LICENSE)). The bundled font is Press Start 2P under the SIL Open Font
Licence (`assets/fonts/`).
