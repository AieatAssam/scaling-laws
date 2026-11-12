# Scaling Laws: core API

Generated from the code in `src/` (signatures as written). Core files are pure: no scene or autoload references. The autoloads `Content`, `SaveSystem` and `Game` are the only wiring.

## Layout

| Path | Role |
|---|---|
| `src/core/big_num.gd` | `BigNum`: mantissa × 10^exponent, immutable ops. |
| `src/core/game_state.gd` | `GameState`: `persist` (survives everything) and `run` (wiped by resets). |
| `src/core/rules.gd` | `Rules`: condition checks, effect application, multiplier composition. |
| `src/core/sim.gd` | `Sim`: all economy and progression logic. Static functions taking a `GameState`. |
| `src/defs/*_def.gd` | Typed `Resource` schemas. Each extends `ContentDef`. |
| `src/autoload/content.gd` | `Content`: loads every `.tres` under `res://content/`. |
| `src/autoload/save_system.gd` | `SaveSystem`: versioned JSON save file. |
| `src/autoload/game.gd` | `Game`: owns the state, ticks it, autosaves, emits signals. |
| `content/<type>/*.tres` | All balance data. The folder name is the content type. |
| `tools/smoke.gd` | Headless smoke test (see bottom). |

## BigNum

Static: `from_float(x)`, `from_json(data)`.
Instance: `copy()`, `is_zero()`, `to_float()`, `log10()`, `add(o)`, `subtract(o)`, `multiply(o)`, `divide(o)`, `mul_f(f: float)`, `compare(o) -> int`, `gte(o)`, `lt(o)`, `power(p: float)`, `square_root()`, `floor_value()`, `format() -> String`, `to_json() -> Dictionary`.

## Content (autoload `Content`)

- `load_all()`: scans `res://content` (called from `_ready`).
- `get_def(type: String, id: String) -> ContentDef` (null if missing).
- `get_all(type: String) -> Array`: sorted by `(order, id)`.
- `types() -> Array`: the content types found.

Types loaded: `producers`, `layers`, `staff`, `research`, `automation`, `rivals`, `challenges`, `agi_stages`, `endings`, `events`, `benchmarks`.

## GameState

Fields: `db` (the Content node), `rng: RandomNumberGenerator`, `persist: Dictionary`, `run: Dictionary`.
Constant: `CURRENCY_LAYER`, which maps each currency to its reset layer (`cash`, `compute` → 0; `equity` → 1; `insights` → 2; `breakthroughs`, `data`, `energy` → 3; `legacy` → 4).

- `_init(content_db = null, seed_value: int = 1)`
- `START_CASH = 20.0`: cash granted at the start of every run and after every reset, so the first producer is affordable.
- `static fresh_run() -> Dictionary`, `static fresh_layer() -> Dictionary`
- `cur(name) -> BigNum`, `set_cur(name, v: BigNum)`, `add_cur(name, v: BigNum)`
- `owned(id) -> int`: producer count this run.
- `resets(k) -> int`: resets of layer k (1..4) done this run.
- `to_dict() -> Dictionary`, `static from_dict(content_db, d) -> GameState`

`persist` keys: `perm_mult` (dict key → float), `legacy_perks` (dict), `automation` (array of ids), `benchmarks` (array of ids), `best_all` (float), `stats` (`runs`, `resets`, `time`, `trainings`, `failed`, `events`), `lifetime_resets` (4 ints, index = layer 1..4 minus one: every reset of that layer ever, across runs; `perform_reset` increments it; the lab shows one legacy prop per non-zero entry; saves without it backfill from `run.resets_done`), `settings` (dict), `saved_at` (unix seconds).

`run` keys: `layers` (5 dicts, index = layer), `resets_done` ([4] ints), `stage` (AGI stage index), `slider` (0..1, starts 0.5), `flags` (dict), `rivals` (id → progress), `challenges_done` (array), `challenge_passed` (id → bool, set when a challenge finishes; read with `.get`, since older saves may lack it), `run_over` (ending id or "").

Each layer dict: `cur` (currency → BigNum), `life` (BigNum, cash earned since last reset), `clock` (seconds), `owned` (layer 0 only), `staff` (layer 1 only), `research` (layer 2 only, array of ids), `best` (layer 2 only, training score), `debt` (layer 0 only), `run_mult`, `timed` (layer 0 only), `training` (layer 0 only), `cooldowns` and `pending` (layer 0 only, event state), `event_timer`, `challenge` (layer 4 only).

Reset k keeps currency k, wipes layers 0..k-1 completely, and zeroes layer k's `life` and `clock`. It also adds 1 to `persist.lifetime_resets[k-1]` and to `persist.stats.resets`.

## Sim (static, pure)

Every action returns `{ok: bool, reason: String, ...}`. Failures include a human-readable `reason`.

The UI may call the pure statics below for read-only previews. Each `*_blocker` returns `""` when the action would succeed, otherwise the reason it would fail. Actions call the same blockers first, so the panel text and the action can't disagree.

Constants: `REVENUE`, `COST_GROWTH`, `MILESTONES`, `TRAIN_SECONDS` (60), `MIN_TRAIN_SPEND`, `TRAIN_ENERGY`, `TRAIN_DATA`, `DATA_RATE`, `ENERGY_RATE`, `ENERGY_CAP`, `FAIL_BASE`, `FAIL_PER_FRAC`, `DEBT_RATE`, `SLIDER_SAFE` (0.3), `EVENT_INTERVAL`, `EVENT_CHANCE`, `OFFLINE_CAP` (86400), `OFFLINE_EFF` (0.5), `OFFLINE_STEP` (60), `LEGACY_MULT`, `AUTO_RESET_MIN_SECONDS` (60).

| Function | Returns / notes |
|---|---|
| `producers(s) -> Array` | Producer defs in order. |
| `cost_for(s, id, count) -> BigNum` | Cost of buying `count` more. |
| `max_affordable(s, id) -> int` | |
| `producer_available(s, id) -> bool` | Previous tier must be owned. |
| `raw_rate(s)`, `compute_per_second(s)`, `cash_per_second(s)` | `BigNum`. |
| `buy_producer(s, id, count=1)` | `count < 0` means buy max. Result adds `count`, `cost`. |
| `hire(s, role, count=1)` | Staff, in layer 1. |
| `staff_cost(s, role, count=1) -> BigNum` | Equity cost of `count` more hires of `role`. |
| `hire_blocker(s, role, count=1) -> String` | Why `hire` would fail, or `""`. |
| `research(s, id)` | Research, in layer 2. |
| `research_blocker(s, id) -> String` | Why `research` would fail, or `""`. Prereqs read `requires <id>`. |
| `buy_automation(s, id)` | Persistent. |
| `automation_blocker(s, id) -> String` | Why `buy_automation` would fail, or `""`. |
| `buy_legacy(s, key)` | Spends legacy; unlocks after the Singularity. |
| `legacy_cost(s, key) -> BigNum` | Next legacy price: 2^n × `perm_mult` growth of the perk. |
| `legacy_blocker(s, key) -> String` | Why `buy_legacy` would fail, or `""`. |
| `set_slider(s, value)` | Result adds `value`. Unlocks after reset 2. |
| `new_run(s)` | Starts a new run after the current one ends. |
| `training_preview(s, frac) -> Dictionary` | Keys `ok`, `reason`, `spend`, `seconds`, `fail_chance`, `predicted_score` (log10(spend) × training multiplier, before the ±5% roll; 0 when the spend is zero), `factors` (see `training_factors`). |
| `training_factors(s) -> Dictionary` | Keys `data`, `architecture`, `researcher`, `total`. `total` is the multiplier applied to the score. |
| `start_training(s, frac)` | `frac` ∈ {0.25, 0.5, 1.0}. Result adds `spend`, `seconds`. |
| `layer_def(s, k)` | `LayerDef` for layer k, or null. |
| `reset_preview(s, k) -> Dictionary` | Keys `layer`, `currency`, `gain`, `holding`, `highlight`, `allowed`, `reason`. |
| `perform_reset(s, k)` | Result adds `layer`, `gain`, `currency`. |
| `resolve_event(s, choice)` | Applies the pending event's choice. Result adds `id`, `choice`. |
| `start_challenge(s, id)` | Unlocks after reset 4; one at a time. |
| `challenge_blocker(s, id) -> String` | Why `start_challenge` would fail, or `""`. A completed challenge can't be entered again. |
| `abandon_challenge(s) -> Dictionary` | Stops the running challenge with no reward and no penalty. Result adds `id`. Fails with "no challenge running". The challenge stays available. |
| `rival_launch_time(s, id) -> float` | Layer-4 clock second when the rival launches: `launch_hours × 3600 × (1 − progress)`, floored at 10% of the base time. |
| `tick(s, dt, offline=false) -> Array` | Advances the state. Returns event dicts (see below). |
| `offline(s, seconds) -> Dictionary` | Keys `seconds`, `capped`, `cash`, `compute`, `events`. Runs in 60 s steps at 50% efficiency, capped at 24 h. |

Event dicts returned by `tick`, each with a `kind` key:

- `training_done` (`ok`; `score` is present only when `ok` is true)
- `auto_train`
- `reset` (`layer`, `gain`)
- `challenge_done` (`id`, `success`)
- `rival_launched` (`id`)
- `agi_advanced` (`index`)
- `ending` (`id`)
- `benchmark` (`id`, `badge`)
- `event` (`id`): an event is now pending. Choose with `resolve_event`.

## SaveSystem (autoload `SaveSystem`)

- `VERSION = 1`, `DEFAULT_PATH = "user://save.json"`
- `save(state: Dictionary, path=DEFAULT_PATH) -> bool`: writes `{"version", "state"}` as JSON.
- `load_data(path=DEFAULT_PATH) -> Dictionary`: returns the migrated state dict, or `{}`.
- `delete(path=DEFAULT_PATH)`
- `migrate(wrapper) -> Dictionary`: one `if v < N:` block per schema change.

## Game (autoload `Game`)

Fields: `state: GameState`, `running: bool`, `save_path: String` (default `user://save.json`).
Constant: `AUTOSAVE_SECONDS` (30).

Lifecycle:
- The main scene must call `Game.start()` once. Nothing else calls it, and `running` stays false until it does.
- `start()`: loads the save if one exists, simulates the time since `saved_at` (`Sim.offline`), then starts ticking.
- `_process(delta)`: ticks the state and autosaves every 30 s.
- On close request: saves.
- `save_now() -> bool`

Read helpers: `cash()`, `compute()`, `cash_per_second()`, `compute_per_second()`, `producer_cost(id, count=1)`, `max_affordable(id)`, `producer_available(id)`, `reset_preview(layer)`, `training_preview(frac)`.

Automation runs inside `tick` and emits no `producer_bought` for auto-buy, so the UI should poll `cash()` and `compute()` every frame rather than rely on signals. Auto-reset does emit `layer_reset`. An automatic reset of layer k (from `auto_fund` for k=1, `auto_gen` for k=2) fires only when `reset_preview(s, k)` is `allowed` and `highlight`, and the layer's clock is at least `Sim.AUTO_RESET_MIN_SECONDS` (60 s). The clock is zeroed by any reset of that layer, so this also spaces automatic resets apart. `LayerDef.target_hours` plays no part in this rule.

Read helpers also include `staff_cost(role, count=1) -> BigNum`.

Actions (each returns the Sim result dict and emits its signal only on `ok`): `buy_producer(id, count=1)`, `start_training(frac)`, `hire(role, count=1)`, `research(id)`, `set_slider(value)`, `buy_automation(id)`, `buy_legacy(key)`, `start_challenge(id)`, `abandon_challenge()`, `resolve_event(choice)`, `reset_layer(layer)`, `new_run()`.
`set_setting(key, value)` writes `persist.settings` and emits `settings_changed`.

Signals:

| Signal | Args |
|---|---|
| `started` | |
| `offline_progress` | `summary: Dictionary` (the `Sim.offline` result) |
| `producer_bought` | `id: String, count: int` |
| `training_started` | `frac: float` (also emitted for auto-training at 0.25) |
| `training_finished` | `result: Dictionary` |
| `staff_hired` | `role: String, count: int` |
| `research_bought` | `id: String` |
| `slider_changed` | `value: float` |
| `automation_bought` | `id: String` |
| `legacy_bought` | `key: String` |
| `challenge_started` | `id: String` |
| `challenge_finished` | `id: String, success: bool` |
| `challenge_abandoned` | `id: String` |
| `event_offered` | `id: String` |
| `event_resolved` | `id: String, choice: int` |
| `benchmark_unlocked` | `id: String, badge: String` |
| `rival_launched` | `id: String` |
| `agi_advanced` | `index: int` |
| `ending_reached` | `id: String` |
| `layer_reset` | `layer: int, gain: int` |
| `new_run_started` | |
| `saved` | `ok: bool` |
| `settings_changed` | `key: String, value: Variant` |

## Content schema (`.tres`)

All defs extend `ContentDef`. Base keys on every def:

- `id: String`: should match the file name. Ids must be unique per type (a duplicate is logged and skipped).
- `title: String`, `description: String`, `icon: String`

Per-type keys:

| Type (folder) | Def | Keys |
|---|---|---|
| `producers` | `ProducerDef` | `order`, `base_cost`, `base_output` |
| `layers` | `LayerDef` | `index`, `currency`, `threshold`, `target_hours` (design target for the pacing report only; no game rule reads it) |
| `staff` | `StaffDef` | `base_cost`, `cost_growth`, `bonus_key`, `bonus_per_hire` |
| `research` | `ResearchDef` | `cost`, `prereqs` (PackedStringArray), `branch`, `effects` (array of `{key, value}` multipliers) |
| `automation` | `AutomationDef` | `order`, `cost` |
| `rivals` | `RivalDef` | `launch_hours` |
| `challenges` | `ChallengeDef` | `duration`, `goal`, `reward`, `penalty` (arrays of dicts) |
| `agi_stages` | `AgiStageDef` | `order`, `conditions`. Stages advance in order; each stage's conditions are checked once the previous stage is done. AGI compute requirements are `compute_rate_gte` (sustained FLOP/s), never a held stock. |
| `endings` | `EndingDef` | `order`, `conditions` |
| `events` | `EventDef` | `category`, `weight`, `cooldown`, `conditions`, `choices` |
| `benchmarks` | `BenchmarkDef` | `badge`, `conditions`, `effects` |

### Event `.tres` (`content/events/`)

Example: `content/events/talent_poaching.tres`, `compute_incident.tres`, `rival_launch_aurora.tres`.

- `category: String`: free text, e.g. `poaching`, `incident`.
- `weight: float`: relative pick weight.
- `cooldown: float`: seconds before the event can repeat.
- `conditions: Array[Dictionary]`: all must pass.
- `choices: Array[Dictionary]`: each `{label: String, effects: Array[Dictionary]}`.

### Benchmark `.tres` (`content/benchmarks/`)

Example: `content/benchmarks/first_model.tres`, `garage_to_rack.tres`, `aligned_lab.tres`.

- `badge: String`: `bronze`, `silver`, `gold`, or other label.
- `conditions: Array[Dictionary]`
- `effects: Array[Dictionary]`: applied once when unlocked.

### Condition dicts (allowed keys)

`{type, id?, layer?, value?}`. Allowed `type` values, and the keys each reads:

| type | Keys | Passes when |
|---|---|---|
| `owned_gte` | `id`, `value` | producer `id` owned ≥ value |
| `currency_gte` | `id`, `value` | currency `id` ≥ value |
| `resets_gte` | `layer`, `value` | resets of `layer` ≥ value |
| `training_best_gte` | `value` | layer-2 best score ≥ value |
| `staff_gte` | `id`, `value` | staff `id` hired ≥ value |
| `research_has` | `id` | research `id` owned |
| `slider_gte` | `value` | slider ≥ value |
| `time_played_gte` | `value` | total seconds played ≥ value |
| `benchmark_unlocked` | `id` | benchmark `id` unlocked |
| `flag_set` | `id` | run flag `id` set |
| `debt_gte` | `value` | debt ≥ value |
| `compute_rate_gte` | `value` | compute per second (after every multiplier) ≥ value, in FLOP/s. Rate, not a held stock: AGI stages use it, since resets wipe held compute. |

### Effect dicts (allowed keys)

`{type, id?, key?, value?, seconds?}`. Allowed `type` values:

| type | Keys | Does |
|---|---|---|
| `add_currency` | `id`, `value` | Adds to currency `id` (negative subtracts, clamped at 0). |
| `add_debt` | `value` | Adds to debt (floor 0). |
| `add_slider` | `value` | Adds to slider (clamped 0..1). |
| `add_flag` | `id` | Sets run flag `id`. |
| `timed_mod` | `key`, `value`, `seconds` | Multiplier `key` × `value` for `seconds`. |
| `run_mult` | `key`, `value` | Multiplies run multiplier `key` (until reset). |
| `perm_mult` | `key`, `value` | Multiplies persistent multiplier `key` (kept across resets). |
| `rival_progress` | `id`, `value` | Adds progress to rival `id`. |

Research `effects` are multipliers only: `{key, value}`.

## Smoke test

`tools/smoke.gd` covers: content counts and every condition/effect type, BigNum sanity, state creation, tick, producer buys, a training run, all four resets in sequence, event resolution, challenge start, save round-trip (identical after reload), offline progress and the cap, and that `game.gd` compiles.

Run:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/smoke.gd
```

It prints `OK` and exits 0, or prints `FAIL` lines and exits 1.
