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
| `src/ui/main.gd`, `src/ui/panels/` | HUD, goal rail, tabs, Stats overlay and game panels. |
| `content/<type>/*.tres` | All balance data. The folder name is the content type. |
| `tools/smoke.gd` | Headless smoke test (see bottom). |
| `tools/simulate.gd`, `reward_gaps.gd`, `training_balance.gd` | Headless progression and balance reports. |
| `tools/ending_order.sh` | Checks ending order in content. |
| `tools/check.sh` | Import, GUT, smoke, and (unless `--fast`) simulator and training-balance checks. |

## BigNum

Static: `from_float(x)`, `from_json(data)`.
Instance: `copy()`, `is_zero()`, `to_float()`, `log10()`, `add(o)`, `subtract(o)`, `multiply(o)`, `divide(o)`, `mul_f(f: float)`, `compare(o) -> int`, `gte(o)`, `lt(o)`, `power(p: float)`, `square_root()`, `floor_value()`, `format() -> String`, `to_json() -> Dictionary`.

## Content (autoload `Content`)

- `load_all()`: scans `res://content` (called from `_ready`).
- `get_def(type: String, id: String) -> ContentDef` (null if missing).
- `get_all(type: String) -> Array`: sorted by `(order, id)`.
- `types() -> Array`: the content types found.

Types loaded: `producers`, `layers`, `staff`, `research`, `automation`, `rivals`, `challenges`, `agi_stages`, `endings`, `events`, `benchmarks`, `training_runs`, `help`, `papers`, `upgrades`, `launches`, `news`, `moonshots`.

`help` (`HelpTopicDef`, `content/help/*.tres`): `order`, `conditions` (same shape as other unlocks; locked topics show `???` and `hint`), `hint`, `body`. `body` is a light markup: `## ` headings, `- ` bullets, blank-line paragraphs, `[icon:x]` / `[badge:x]` inline images, `{CONST}` / `{CONST:pct|h|min}` / `{threshold:k}` / `{layer:k}` tokens resolved against live state (unknown tokens render as `<UNKNOWN:x>`, which the test catches), and the `[training]` and `[layers]` directives. Resolved by `HelpText.to_bbcode` (`src/ui/panels/parts/help_text.gd`). Tested in `tests/test_help.gd`.

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

`persist` keys: `perm_mult` (dict key → float), `legacy_perks` (dict), `automation` (array of ids), `benchmarks` (array of ids), `best_all` (float), `stats` (runs, resets, time, trainings, failed trainings, events, papers, landmarks, upgrades, launches, news, moonshots, evals passed/failed, ships and challenge-tier counts), `moonshots` (running and completed projects plus Research Programme level and progress), `records`, `seen_reveals`, `reveals_seeded`, `lifetime_resets` (4 ints, index = layer 1..4 minus one: every reset of that layer ever, across runs; `perform_reset` increments it), `settings`, `intro_seen`, `saved_at` (unix seconds), and AGI eval seed data. Missing fields in older saves are filled from the current state template.

`run` keys: `layers` (5 dicts, index = layer), `resets_done` ([4] ints), `stage` (AGI stage index), `slider` (0..1, starts 0.5), `peak_compute_rate` and `agi_peaks` (best AGI requirement values since the last Singularity reset), `flags` (dict), `rivals` (id → progress), `challenges_done` (array), `challenge_passed` (id → bool, set when a challenge finishes; read with `.get`, since older saves may lack it), `run_over` (ending id or "").

Each layer dict: `cur` (currency → BigNum), `life` (BigNum, cash earned since last reset), `clock` (seconds), `owned` (layer 0 only), `staff` (layer 1 only), `research` (layer 2 only, array of ids), `best` (layer 2 only, training score), `debt` (layer 0 only), `run_mult`, `timed` (layer 0 only), `training` (layer 0 only), `cooldowns` and `pending` (layer 0 only, event state), `event_timer`, `challenge` (layer 4 only).

Reset k keeps currency k, wipes layers 0..k-1, and zeroes layer k's `life` and `clock`. Singularity (k = 4) also preserves unspent Breakthroughs while resetting Data, Energy, and Paradigm-layer upgrades; persistent moonshots keep running through every reset. It also adds 1 to `persist.lifetime_resets[k-1]` and to `persist.stats.resets`.

## Sim (static, pure)

Every action returns `{ok: bool, reason: String, ...}`. Failures include a human-readable `reason`.

The UI may call the pure statics below for read-only previews. Each `*_blocker` returns `""` when the action would succeed, otherwise the reason it would fail. Actions call the same blockers first, so the panel text and the action can't disagree.

Constants: `REVENUE`, `COST_GROWTH`, `MILESTONES`, `MIN_TRAIN_SPEND` (100), `TRAIN_ENERGY`, `TRAIN_DATA`, `REFUND_SHARE` (0.5: a failed run returns this share of its spend), `SCORE_ROLL` (0.02: a run's score rolls +/- this), `FAIL_FLOOR` (0.4: Ops cut a run's fail chance to this share of its base at most), `PICK_MAX_FAIL` (0.2: a chased run must fail at most this often; each run's `chase_margin` sets how far it must predict above the best), `PICK_NEAR_BEST` (0.45: Standard replaces a fail-blocked Frontier in the pick when it predicts within this share below the best), `DATA_RATE`, `ENERGY_RATE`, `ENERGY_CAP`, `DEBT_RATE`, `SLIDER_SAFE` (0.3), `EVENT_INTERVAL`, `EVENT_CHANCE`, `OFFLINE_CAP` (86400), `OFFLINE_EFF` (0.5), `OFFLINE_STEP` (60), `LEGACY_MULT`, `AUTO_RESET_MIN_SECONDS` (60).

| Function | Returns / notes |
|---|---|
| `producers(s) -> Array` | Producer defs in order. |
| `cost_for(s, id, count) -> BigNum` | Cost of buying `count` more. |
| `max_affordable(s, id) -> int` | |
| `producer_available(s, id) -> bool` | Previous tier must be owned. |
| `producer_raw_rate(s, id)` | `BigNum`: one producer's output per second before the compute multiplier (owned × base × milestone doublings). |
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
| `run_def(s, id)` | `TrainingRunDef` from `content/training_runs`, or null. |
| `training_fail_factor(s) -> float` | Ops cut: `max(FAIL_FLOOR, 1 - sum of fail_per_hire x hires)`. |
| `training_preview(s, id) -> Dictionary` | `id` is a run type (`fine_tune`, `standard`, `frontier`). Keys `ok`, `reason` ("unknown run type", "already training", "needs at least N compute", "not enough energy or data"), `id`, `title`, `spend`, `seconds`, `score_mult`, `base_fail`, `fail_factor`, `fail_chance` (base x Ops factor), `min_compute` (smallest stock at which the share meets `MIN_TRAIN_SPEND`), `predicted_score` (log10(spend) x training multiplier x `score_mult`, before the roll; 0 when the spend is zero), `bonus_now` and `bonus_if_success` (compute bonus before and after the predicted score lands), `factors` (see `training_factors`), `revenue_seconds` (the run type's cash burst length) and `revenue` (BigNum: the burst paid on success now, `revenue_seconds` x `cash_per_second`, before the run's own score). |
| `pick_training(s) -> String` | The run the simulator and auto-train pick, or `""`. The highest predicted score among startable runs that beat the best by their own `chase_margin` and fail at most `PICK_MAX_FAIL`. Fallback: if Frontier fails above `PICK_MAX_FAIL` and Standard's predicted score is at least `(1 - PICK_NEAR_BEST)` x best (`PICK_NEAR_BEST` = 0.45), pick Standard. Otherwise the startable run with the most cash per second, `(1 - fail) x revenue_seconds / seconds` (fine-tune), or `""` when none can start. Pure. |
| `training_factors(s) -> Dictionary` | Keys `data`, `architecture`, `researcher`, `total`. `total` is the multiplier applied to the score. |
| `start_training(s, id)` | Charges the spend up front (and energy/data after reset 3). Result adds `id`, `spend`, `seconds`. The run dict in `layers[0].training` holds `type`, `spend`, `log`, `left`, `fail`, `score_mult` and `revenue_seconds`. |
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

- `training_done` (`id` = run type, `ok`, `revenue` = BigNum cash burst, zero on failure). Success adds `score`, `new_best` and `new_all_time`. Failure adds `refund` (BigNum, half the spend, already added to compute). A success pays `revenue_seconds` of the cash rate at finish (before its own score lands), scaled by `eff` like income (offline 50%), added to cash and to every layer's `life`. A failure pays no burst; a run saved before the burst existed (no `revenue_seconds`) pays none.
- `auto_train` (`id` = the run type `pick_training` chose and started)
- `reset` (`layer`, `gain`)
- `challenge_done` (`id`, `success`)
- `rival_launched` (`id`)
- `agi_advanced` (`index`)
- `ending` (`id`)
- `benchmark` (`id`, `badge`)
- `event` (`id`): an event is now pending. Choose with `resolve_event`.

## Rules (static, pure)

- `mult(s, key) -> float`: product of `mult_parts(s, key)`.
- `mult_parts(s, key) -> Array`: each factor as `{id, name, value}` (legacy perks, run upgrades, timed boosts, owned research, staff, and for `compute` alignment, debt and training score). The UI uses it for "why is my multiplier this?" tooltips.
- `training_bonus(s) -> float`: the training score factor, `training_bonus_for(best, best_all)` with the state's bests.
- `training_bonus_for(best: float, best_all: float) -> float`: `(1 + 0.05 x best) x (1 + 0.01 x best_all)`. Used for previews of a score before it lands.
- `condition_progress(s, cond) -> float`: 0..1 toward one condition dict. Exactly 1.0 only when `check()` passes; otherwise capped at 0.99. Currency-like amounts (`currency_gte`, `compute_rate_gte`) use log scale (`log10(1 + x)`), counts are linear. Every condition type is covered; the all-or-nothing ones (`research_has`, `benchmark_unlocked`, `flag_set`) are 0 until they hold.
- `conditions_progress(s, conds) -> float`: the minimum over a condition list (1.0 for an empty list).
- `reset_worth_life(s, k) -> BigNum`: lifetime cash (layer k's `life`) at which a reset of layer k is highlighted. Gain needed is `G = max(2, ceil(2 x holding))`, life is `threshold x G^2`, matching `Sim.reset_preview`.
- `reset_eta(s, k) -> {worth_now: bool, worth_in: float, next_in: float}`: seconds (estimate) at the current `Sim.cash_per_second`. `worth_in` is 0 when worth it now; `next_in` is the time until the gain rises by one. Both are `INF` when cash income is zero. Assumes income stays put.
- `next_goals(s, n) -> Array`: the n nearest unmet goals, each `{kind, id, title, progress, hint}`. Kinds: `benchmark` (locked; `title` is the real name, so the UI hides it), `reset` (the layer's worth-it point; layers 1..4, when reachable and not yet worth it), `producer` (first tier not owned), `milestone` (next of 25/50/100/200 for an owned producer), `agi` (current AGI stage once Singularity is reachable). Sorted by progress; a big kind (`BIG_KINDS`: reset, producer, agi) within `BIG_BONUS` (0.10) of the nearest ranks first. Pure.

## UI widgets

- Help: the Help tab is `src/ui/panels/help.gd` (`HelpPanel`). `main.gd` `open_help(topic)` (reached through the `shell` group) selects it and calls `open_topic(id)`, which opens and scrolls to that topic. The "?" buttons (`PanelHelp.button(topic)`) call `open_help`.
- `Tip` (`src/ui/widgets/tip.gd`, a CanvasLayer added once by `main.gd`): `Tip.attach(ctrl, source)` gives any control a tooltip. `source` is a String or a `Callable` returning one, re-read while the tip is open. The first line is the title. Mouse: shows after 0.35 s of hover. Touch: a press held 0.4 s shows it; lifting the finger or tapping elsewhere hides it and swallows that input, so a Buy button under the finger does not fire. `reduce_motion` skips the fade.
- `GoalRail` (`src/ui/widgets/goal_rail.gd`): the one-line "Next: <title> <bar> <pct>" row under the HUD, 14 px tall. Built by `main.gd` `_build_shell`. It polls `Rules.next_goals(Game.state, 3)` every 0.25 s; a tap cycles the three goals. A locked benchmark reads "Benchmark: <requirements>" (name and reward hidden). The tooltip gives the goal's hint and requirements.
- Reset cards (`PanelResetCard`, `src/ui/panels/parts/panel_reset_card.gd`): show "Est.: worth it in ~12m, next +1 in ~3m" from `Rules.reset_eta`. "now" once worth it; "-" when cash income is zero.
- Benchmarks panel: locked rows show a progress bar and percent from `Rules.conditions_progress`, plus the requirement text.
- `DragScroll` (`src/ui/widgets/drag_scroll.gd`, a `ScrollContainer`): every scroll page is one (`PanelKit.scroll_page`, Help, event popup, tip-hosting pages). Touch and mouse drags scroll it from `_input`, so child buttons (which stop the press) cannot swallow the drag. Movement under 8 px is a tap and goes to the child. A drag cancels the press on the child it started on (`MOUSE_EXIT`); the release is passed through with that child's signals muted for one frame so no click fires. A release with speed fling-scrolls (`FLING_MIN` 150 px/s, `FLING_FRICTION`, stops below `FLING_STOP`); a press during a fling stops it and is not a click.
- `RevealCard` (`src/ui/overlays/reveal_card.gd`): the one-time "New: <System>" card. Asked of the shell's modal queue (`gate`) once a second, never during the intro, at most one per `REVEAL_GAP_MS` (30 s). OK, Space/Enter or Back closes it. "Learn more" closes it and calls `open_help(topic)`. Showing it marks the reveal seen and saves at once.
- `StatsPanel` (`src/ui/panels/stats.gd`): the Statistics overlay, opened from Settings > Statistics (`shell` group `open_stats`). Shows completion (`Records.completion`), this run (time played, resets per layer), all time (persist.stats), the fastest cycle of each reset layer, and lifetime resets. Read-only.
- Keyboard (desktop), in `main.gd` `_hotkey`: keys 1–9 select the visible tab in order; B cycles the producer buy amount (1, 10, MAX); Space/Enter (`_confirm_top`) closes the open reveal card, else the notice card. Ignored with Ctrl/Alt/Meta and while a text field has focus. Tabs and B are also ignored while a modal or the Statistics overlay is up. Listed in Settings and the `hotkeys` help topic.
- Notices: `show_record(layer, secs)` shows the toast "New record: fastest <layer> <duration>" on `Game.record_set`. Not shown for a layer's first reset.

## SaveSystem (autoload `SaveSystem`)

- `VERSION = 10`, `DEFAULT_PATH = "user://save.json"`. v2: a training run stores its `type`; a v1 run in flight (a bare compute share) is refunded its spend into compute and cleared. v3 → v4 (`_v3_to_v4`): adds `persist.records`. v7 → v8 adds Singularity-scoped AGI peak state. v8 → v9 adds lifetime offline-credit and training-burst cash totals; v9 → v10 adds Research Programme level and progress. A save with no version field counts as v0.
- `save(state: Dictionary, path=DEFAULT_PATH) -> bool`: writes `{"version", "state"}` as JSON. Before overwriting, copies the current file to `<path>.bak`, but only if it is a valid save, so a damaged file never replaces the backup. Refuses (`false`, `push_error`) to overwrite a file written by a newer version.
- `load_data(path=DEFAULT_PATH) -> Dictionary`: returns the migrated state dict, or `{}` for a new game. Sets `last_notice: String` (empty when nothing needed reporting):
  - missing file: `{}`, no notice.
  - damaged file (not JSON, no `state`, wrong shape): renamed to `<path>.bad-<ms>`, then `<path>.bak` is used if valid (notice says it was restored), else a new game (notice says so).
  - newer version: renamed to `<path>.newer-<ms>` and a new game starts (notice).
  - Never migrates or fills defaults itself. `GameState.from_dict` fills missing keys, so `migrate` followed by `from_dict` is the full load (what Settings > Import does).
- `delete(path=DEFAULT_PATH)`: removes the save and `<path>.bak` (Hard reset).
- `migrate(wrapper) -> Dictionary`: runs the `if v < N:` blocks in order, one per schema change. Returns `{}` for a version newer than `VERSION`.
- `_parse(path)`: reads a file without migrating; status is `missing`, `corrupt`, `newer` or `ok`.

## Game (autoload `Game`)

Fields: `state: GameState`, `running: bool`, `save_path: String` (default `user://save.json`).
Constants: `AUTOSAVE_SECONDS` (30), `SUMMARY_MIN_SECONDS` (60: shorter absences are credited with no card), `MAX_TICK_SECONDS` (1: a frame never simulates more than this).

Lifecycle:
- The main scene must call `Game.start()` once. Nothing else calls it, and `running` stays false until it does.
- `start()`: loads the save (emitting `save_notice` first if the loader had to recover), then credits the time since `saved_at` (`_catch_up`), then starts ticking. A missing or zero `saved_at` credits nothing.
- `_catch_up(credit, away)`: runs `Sim.offline(credit)` when `credit > 1` and `persist.intro_seen` is true (the player quit mid-intro gets no catch-up), saves, and emits `offline_progress` only when `away >= SUMMARY_MIN_SECONDS`. The summary is the `Sim.offline` result plus `"away"`: the real seconds away.
- `_process(delta)`: ticks the state with `min(delta, MAX_TICK_SECONDS)` and autosaves every 30 s. The web build's periodic save is this autosave; nothing else is needed there.
- Going away and coming back (no double counting): `NOTIFICATION_APPLICATION_PAUSED` begins an absence; `NOTIFICATION_APPLICATION_RESUMED` ends it. On phones and in browsers, `FOCUS_OUT`/`FOCUS_IN` do the same. Beginning saves and records `_away_since`; the frames ticked meanwhile are counted in `_ticked_since`. Ending credits `away - ticked` through `_catch_up` (so the 50% credit covers only what was not simulated) and saves. A repeated begin or end is ignored, a resume at launch (no marker) does nothing, and an end while `running` is false (the intro is up) only closes the measurement.
- `NOTIFICATION_APPLICATION_FOCUS_OUT` always saves (desktop included).
- `NOTIFICATION_WM_CLOSE_REQUEST`: saves. (Android back is handled by the shell, see below; the app does not quit on it.)
- `start()` also calls `Records.absorb(state)` (counts what a loaded save already holds) and `Reveals.seed(state)` (already-met reveals count as seen, so an old save gets no burst of cards).
- `record_set(layer: int, secs: float)`: emitted by a layer reset that beats that layer's fastest cycle (never a layer's first reset). Notices shows the toast.
- Main scene: `play_intro()` plays the first-run intro over the shell and sets `Game.running = false` until it finishes (finish or skip sets `intro_seen` and saves). Settings > Replay intro calls it too.
- `save_now() -> bool`

Read helpers: `cash()`, `compute()`, `cash_per_second()`, `compute_per_second()`, `producer_cost(id, count=1)`, `max_affordable(id)`, `producer_available(id)`, `reset_preview(layer)`, `training_preview(run_type)`.

Automation runs inside `tick` and emits no `producer_bought` for auto-buy, so the UI should poll `cash()` and `compute()` every frame rather than rely on signals. Auto-reset does emit `layer_reset`. An automatic reset of layer k (from `auto_fund` for k=1, `auto_gen` for k=2) fires only when `reset_preview(s, k)` is `allowed` and `highlight`, and the layer's clock is at least `Sim.AUTO_RESET_MIN_SECONDS` (60 s). The clock is zeroed by any reset of that layer, so this also spaces automatic resets apart. `LayerDef.target_hours` plays no part in this rule.

Read helpers also include `staff_cost(role, count=1) -> BigNum`.

Actions (each returns the Sim result dict and emits its signal only on `ok`): `buy_producer(id, count=1)`, `start_training(run_type)`, `hire(role, count=1)`, `research(id)`, `set_slider(value)`, `buy_automation(id)`, `buy_legacy(key)`, `start_challenge(id)`, `abandon_challenge()`, `resolve_event(choice)`, `reset_layer(layer)`, `new_run()`, `agi_choose(method)` (`ship`, `redteam` or `full`; the last two start an evaluation), `start_moonshot(id)`, `start_research_programme()`, `outship(id)`, `acqui_hire(id)`.
`set_setting(key, value)` writes `persist.settings` and emits `settings_changed`.

Signals:

| Signal | Args |
|---|---|
| `started` | |
| `offline_progress` | `summary: Dictionary` (the `Sim.offline` result plus `away`: real seconds away; emitted only for `away >= 60`) |
| `save_notice` | `text: String`: the save was damaged or newer and was set aside, or a backup was restored. Emitted once, before `started`. |
| `producer_bought` | `id: String, count: int` |
| `training_started` | `run_type: String` (also emitted for auto-training, which starts the run `pick_training` chose) |
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
| `rival_outpaced` | `id: String` |
| `agi_advanced` | `index: int` |
| `agi_cleared` | `index: int, method: String` |
| `agi_failed` | `index: int, method: String` |
| `race_action` | `id: String, action: String` (`outship` or `acqui`) |
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
| `layers` | `LayerDef` | `index`, `currency`, `threshold`, `target_hours` (design target for the pacing report only; no game rule reads it; Singularity content threshold is 1.34e12 lifetime cash) |
| `staff` | `StaffDef` | `base_cost`, `cost_growth`, `bonus_key`, `bonus_per_hire`, `fail_per_hire` (cut to a training run's fail chance per hire; see `Sim.training_fail_factor`) |
| `training_runs` | `TrainingRunDef` | `order`, `spend_share` (0..1 of current compute), `seconds`, `fail_chance`, `score_mult`, `revenue_seconds` (cash burst on success: seconds of cash income; 0 = none) |
| `research` | `ResearchDef` | `cost`, `prereqs` (PackedStringArray), `branch`, `effects` (array of `{key, value}` multipliers) |
| `automation` | `AutomationDef` | `order`, `cost` |
| `rivals` | `RivalDef` | `launch_hours` |
| `challenges` | `ChallengeDef` | `duration`, `goal`, `reward`, `penalty` (arrays of dicts) |
| `agi_stages` | `AgiStageDef` | `order`, `conditions`. Stages unlock sequentially after the previous stage is cleared. AGI rate, energy, training-best and owned-count requirements use the best reached since the last Singularity reset. |
| `endings` | `EndingDef` | `order`, `conditions` |
| `events` | `EventDef` | `category`, `weight`, `cooldown`, `conditions`, `choices` |
| `benchmarks` | `BenchmarkDef` | `badge`, `conditions`, `effects` |
| `papers` | `PaperDef` | `blurb`, `weight`, `conditions`, `choices` |
| `upgrades` | `UpgradeDef` | `cost`, `kind`, `target`, `source`, `value`, `conditions` |
| `launches` | `LaunchDef` | `cost_currency`, `cost_share`, `cooldown`, `conditions`, `effects` |
| `news` | `NewsDef` | `weight`, `reward` |
| `moonshots` | `MoonshotDef` | `hours`, `breakthroughs`, `cash`, `prereqs`, `conditions`, `effects` |

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
| `compute_rate_gte` | `value` | compute per second (after every multiplier) ≥ value, in FLOP/s. AGI stages compare the peak rate since the last Singularity reset. |

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

## Records, completion and reveals

`Records` (`src/core/records.gd`, pure) keeps `persist.records`, which survives resets: `fastest` (layer key "1".."4" → seconds of the quickest cycle), `cycle_start` (per layer 0..4, game time the layer was last cleared), `run_start`, the achieved sets `producers`, `research`, `challenges`, `endings`, `outpaced` (rivals not launched when an ending is reached), `agi_best`, `offline_seconds` (credited offline elapsed seconds), and `deployment_burst_cash` (serialized BigNum lifetime cash from successful training bursts). `note_offline` and `note_deployment_burst` accumulate the two lifetime totals.
- `note_reset(persist, k) -> {layer, secs, first, record}`: `secs` is the time since layer k's clock. The first reset of a layer sets its baseline (no record). Later ones are records when faster; a reset of k clears clocks 0..k. `Game` calls it from `layer_reset`.
- `note(persist, group, id)`, `note_agi(persist, index)` (keeps the max), `note_ending(s, id)`, `new_run(persist)`, `absorb(s)`.
- `completion(s) -> {percent: float 0..100, parts: [{id, label, done, total}]}`: ten equally weighted parts: producer tiers, benchmarks, research, automation, reset layers, challenges, rivals outpaced, AGI stages, endings and completed moonshots.
- `run_seconds(persist)`, `format_duration(secs)` ("45s", "12m 04s", "1h 03m"), `layer_title(s, k)`.

`Reveals` (`src/core/reveals.gd`, pure) holds the one-time "New: <System>" cards. Each entry has `id`, `title`, `topic` (the Help topic it links to), `body` and `conditions` (mirrors the topic). `next_due(s)` returns the first reveal whose conditions hold and that is not in `persist.seen_reveals`; `mark_seen`, `is_seen`, `find`. `seed(s)` runs once (`persist.reveals_seeded`). "Constraints" covers the regulation challenges; "Training" uses `time_played_gte` 600 because training has no content gate. The card itself is `RevealCard` (see UI widgets).

## Research desk

`Desk` (`src/core/desk.gd`) owns the generation-scoped desk in `run.layers[2].desk`: `slots`, `timer`, and additive `bonus`. It unlocks after the first lifetime Model Generation. `Desk.tick(s, dt, events)` draws a weighted eligible paper every 1,200 seconds while fewer than three slots are occupied, including during offline simulation. `Desk.resolve(s, slot, choice)` consumes a card and increments persistent `stats.papers` and, for landmarks, `stats.landmarks`. `Desk.best_cash(s, card)` is the simulator and Auto-review policy. Model Generation and higher resets clear the desk; Funding does not. Save version 3 initializes the desk for older saves.

Paper resources have `blurb`, `conditions`, `weight`, and `choices`. Choices have `label`, `effects`, and an optional `{id, value}` currency `cost`. Alongside event effects, `cash_seconds` pays the given seconds of current cash income and `generation_mult` adds to the generation's compute bonus (capped at 0.5). Landmark effects double their magnitudes, including the excess above 1 for multipliers. Paper timed effects replace other timed effects on the same key. `stat_gte` conditions compare a persistent statistic by `id` and `value`. `Game.resolve_paper(slot, choice)` emits `paper_resolved`; draws emit `paper_offered`.

## Lab upgrades (static, pure: `src/core/upgrades.gd`)

Run-scoped (layer 0), bought once per run with cash. Definitions: `content/upgrades/*.tres` (`UpgradeDef`: `cost`, `kind`, `target`, `source`, `value`, `conditions`). Kinds: `double`, `synergy` (+1% per unit, capped by `SYNERGY_CAP` = 1.0), `cost` (-10%), `revenue` (cash), `train_speed`. Effects reach the sim only through `Rules.mult_parts`.

- `Upgrades.all(s)`, `owned_ids(s)`, `is_owned(s, id)`, `owned_defs(s)`
- `Upgrades.blocker(s, id)` -> `""` or one of `"unknown upgrade"`, `"already bought"`, `"locked: needs N <Producer>"`, `"not enough cash"`
- `Upgrades.buy(s, id)` -> `{ok, ...}`; `Upgrades.parts(s, key)` and `tier_mult` / `cost_mult` feed `Rules.mult_parts`
- `Upgrades.automate(s, evs)`: buys the cheapest affordable upgrade when `auto_upgrade` is owned

## Launches (static, pure: `src/core/launches.gd`)

Timed boosts (`content/launches/*.tres`: `LaunchDef` with `cost_currency`, `cost_share`, `cooldown`, `conditions`, `effects`). Cost is `cost_share` of the paying currency. One timed mod per key: a new one replaces the old, it does not stack.

- `Launches.cost(s, id)`, `cooldown_left(s, id)`, `blocker(s, id)` -> `""`, `"locked"`, `"cooling down"`, `"not enough <currency>"`, `"buy a producer first"`
- `Launches.fire(s, id)` pays, applies effects, starts the cooldown, and counts `stats.launches`
- `Launches.tick(s, dt)` counts down `run["launches"]` (id -> seconds left)
- `Launches.automate(s, evs)`: fires every ready, affordable launch when `auto_launch` is owned

The "buy a producer first" guard exists because a cash launch right after a reset (cash = `START_CASH`, nothing owned) can leave less than the first producer costs, which is a permanent stall with no income.

## Breaking news (static, pure: `src/core/news.gd`)

Random headlines (`content/news/*.tres`: `NewsDef` with `weight`, `reward` = `cash` | `compute` | `double_cash` | `viral`). Timing: first headline after `FIRST_SECONDS` (150 s), then `MIN_GAP` (90 s) plus an exponential with mean `MEAN_EXTRA` (150 s), so the mean gap is about 240 s. Shown for `CHIP_SECONDS` (15 s). Does not tick while a modal or the intro is up, or offline (`Game._process` passes `news_held`).

- `News.tick(s, dt, evs, hold)`: counts the timer down and spawns a headline (weighted pick on `s.rng`); `run["news"]` = `{"timer", "chip": {id, left} or {}}`
- `News.catch(s)` -> `{ok, id, title, reward, amount?, seconds?}`; one reward per tap; a miss costs nothing. Counts `stats.news`
- Benchmarks `news_10`, `news_100`, `news_500` count caught headlines
- `reduce_motion` makes the lab chip static instead of pulsing

## Moonshots (static, pure: `src/core/moonshots.gd`)

Long real-time projects on the Paradigm panel. Defs: `content/moonshots/*.tres` (`MoonshotDef`: `hours`, `breakthroughs`, `cash`, `prereqs`, `conditions`, `effects`). Unlock at the first Paradigm Shift. One running slot (`BAY_SLOTS` = 2 with `second_bay`). Progress is raw game seconds, so offline time runs projects at full speed. Rewards are permanent (`persist`), so they survive every reset.

- `Moonshots.all(s)`, `done(s, id)`, `running(s)`, `is_running(s, id)`, `slots(s)`, `time_left(s, id)`
- `Moonshots.blocker(s, id)` -> `""` or `"unknown moonshot"`, `"done"`, `"running"`, `"locked"`, `"needs <Title>"`, `"no free project slot"`, `"not enough breakthroughs"`, `"not enough cash"`
- `Moonshots.start(s, id)` -> `{ok, ...}`; spends breakthroughs and cash; `Game.start_moonshot` wraps it
- `Moonshots.tick(s, dt, evs)`: counts down regular projects; a finished project applies its effects, adds to `persist.stats.moonshots`, and emits `moonshot_done` (`Game.moonshot_finished`). Research Programme completion increments its level and persistent compute multiplier and emits the same event with id `research_programme`.
- Research Programme: `programme_level(s)`, `programme_cost(s)`, `programme_hours(s)`, `programme_left(s)`, `programme_blocker(s)`, `start_programme(s)`. Available after the first Paradigm Shift; it runs separately from the project slots, costs `0.35 × 1.4^level` Breakthroughs, takes 4–8h and grants a permanent compounding +3% compute per level, capped at 25. `Game.start_research_programme()` wraps the start action and emits `moonshot_started`.
- Hooks read by other systems: `producer_cost_mult`, `cooldown_mult`, `staff_cost_mult`, `fail_mult`, `chip_mult`, `desk_slots`, `threshold_for` (Funding and Generation gain bonuses), `bonus_gain` (Paradigm, Singularity), `parts` (AGI road compute)
- `Moonshots.before_wipe(s, k)` / `after_wipe(s, k, keep)`: called by `Sim.perform_reset`. On a Funding Round (k = 1) they keep the training run when `second_cluster` is done, and the early lab upgrades (order ≤ `LAB_KEEP_ORDER`) when `institutional_memory` is done

State: `persist.moonshots` = `{running: [{id, left}], done: [id], programme: {level, left}}`. `SaveSystem._v5_to_v6` adds moonshot state and `_v9_to_v10` adds the programme fields.

## Endgame (static, pure: `src/core/endgame.gd`)

The AGI road, the ending choice, the rival race and the regulation challenge tiers. `sim.gd` calls `Endgame.tick` once per tick and `Endgame.launch_seconds` for rival clocks; nothing else in the core holds this logic. The final stage's compute-rate requirement is 5e12/s.

- Methods: `ship` (instant, Ship it), `redteam` (6 h community red-team), `full` (12 h full eval suite, then a 1 h cooldown after a failure). The previous stage's method scales the next stage's resource requirements: ship ×0.001, red-team ×1.0, full ×1.85 (capped at a resource maximum); reset gates are unchanged. The final stage starts no earlier than day 9 after Ship, day 9.5 after Red-team, or day 11 after Full eval. `start_choice(s, method)` clears the pending stage (`pending_index`), returning `{ok, reason, index, method, events}`.
- `stage_conditions(s, index, previous_method="")` returns a stage's live gates; `previous_method` previews the numeric scaling before that method is cleared.
- Evaluations: `run.eval = {method, index, left}`. Pass chance: red-team `RED_PASS` (0.7); full suite `FULL_BASE` + `FULL_SLIDER` × alignment slider + `FULL_OPS` per ops staff, capped at `FULL_CAP` (0.97). A pass clears the stage; a fail reopens it (the full suite then cools down).
- Ending: `majority(choices)` picks the most-used method, ties going to the most recent choice. `ending_for(choices)` maps it to `aligned` (full), `open_sourced` (redteam) or `rushed` (ship). Run ends after the fifth stage clears.
- Counters: Assurance = full picks, Openness = redteam picks, Recklessness = ship picks. Ship picks raise negative alignment losses in bad events by `RECK_SEVERITY` per pick, clamped at the debt threshold; equity and production costs are unchanged.
- Rivals: each rival races from its `outpace_stage` (`racing`). Its clock speeds up with `redteam_uses` (`RED_SPEED` per use). Clearing the stage first outpaces it (`rival_outpaced`, recorded in `persist.records.outpaced`). `outship(s, id)` cuts the remaining delay by `OUTSHIP_GAIN` of the gap, costs compute (`OUTSHIP_COST` × `OUTSHIP_COST_GROWTH` per use), cooldown `OUTSHIP_COOLDOWN` (1800 s). `acqui(s, id)` pays `ACQUI_CASH_SECONDS` of cash income into cash and layer 1–4 life, adds a researcher, and slows that rival by `ACQUI_SPEED`; cooldown `ACQUI_COOLDOWN`.
- Challenge tiers: `tier_blocker(s, id)` requires the tier below to have been passed once ever (`challenge.requires`). `challenge_effect` multiplies the tier reward by `1.05 / 1.08 / 1.12` for tiers I/II/III; `persist.challenge_mult` caps at `CHALLENGE_CAP` (1.4).

`Game` wraps the actions (`agi_choose`, `start_moonshot`, `start_research_programme`, `outship`, `acqui_hire`) and emits `agi_cleared`, `agi_failed`, `rival_outpaced` and `race_action`.

## Save version 10

`SaveSystem.VERSION = 10`. `_v6_to_v7` adds `run.agi_choices` (one method per stage). `_v7_to_v8` adds `run.peak_compute_rate` and `run.agi_peaks`. `_v8_to_v9` adds lifetime offline-credit and training-burst cash totals to `persist.records`. `_v9_to_v10` adds Research Programme level and progress to `persist.moonshots`. A finished run gets its ending's method on every stage (`aligned` full, `open_sourced` redteam, `rushed` ship). A run still going gets `ship` for each stage already reached.

## Save version 5

`SaveSystem.VERSION = 5`. `_v4_to_v5` adds `layers[0].upgrades`, `run.launches`, `run.news`, and `stats.launches` / `stats.news`. Upgrades are run-scoped, so a reset clears them.

## Simulator hooks (tools/simulate.gd)

The scripted player buys upgrades cheapest-first before producers, fires every ready launch after hiring, and catches every second breaking headline. The report line `new systems: upgrades bought N (run-scoped, rebought after wipes; M defs), launches fired ..., breaking news ... shown, ... caught` uses whole-run counters, not end state, because Singularity wipes layer 0.
