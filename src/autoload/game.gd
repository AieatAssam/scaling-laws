extends Node
## Autoload `Game`: owns the GameState, ticks it each frame, autosaves, and turns sim results into signals.
## Every action returns the Sim result dict ({ok, reason, ...}) and emits its signal only on success.
## See docs/API.md.

signal started
signal offline_progress(summary: Dictionary)
signal producer_bought(id: String, count: int)
signal training_started(run_type: String)
signal training_finished(result: Dictionary)
signal staff_hired(role: String, count: int)
signal research_bought(id: String)
signal slider_changed(value: float)
signal automation_bought(id: String)
signal legacy_bought(key: String)
signal challenge_started(id: String)
signal challenge_finished(id: String, success: bool)
signal challenge_abandoned(id: String)
signal event_offered(id: String)
signal event_resolved(id: String, choice: int)
signal paper_offered(id: String)
signal paper_resolved(id: String, choice: int)
signal benchmark_unlocked(id: String, badge: String)
signal rival_launched(id: String)
signal agi_advanced(index: int)
signal ending_reached(id: String)
signal layer_reset(layer: int, gain: int)
signal new_run_started
signal saved(ok: bool)
signal settings_changed(key: String, value: Variant)
## A damaged or newer save was set aside, or a backup was used (text for the player). Emitted before `started`.
signal save_notice(text: String)
## A layer reset beat that layer's fastest cycle (not its first reset). Notices shows the toast.
signal record_set(layer: int, secs: float)
signal upgrade_bought(id: String)
signal launch_fired(id: String)
signal news_spawned(id: String)
signal news_caught(id: String, reward: Dictionary)
signal moonshot_started(id: String)
signal moonshot_finished(id: String)
## AGI stage `index` (1-based) cleared with method ("full", "redteam", "ship"); a failed full or red-team eval.
signal agi_cleared(index: int, method: String)
signal agi_failed(index: int, method: String)
signal rival_outpaced(id: String)
## Outship ("outship") or Acqui-hire ("acqui") on rival `id`.
signal race_action(id: String, kind: String)

const AUTOSAVE_SECONDS := 30.0
## Offline progress is only reported (the "While you were away" card) for absences at least this long.
const SUMMARY_MIN_SECONDS := 60.0
## One frame never simulates more than this. A frame that arrives after the app was suspended would otherwise
## run the whole gap at full rate, before the resume handler has the chance to credit it at 50%.
const MAX_TICK_SECONDS := 1.0

var state: GameState
var running := false
var save_path: String = "user://save.json"
var _autosave_t := 0.0
## Unix time the app went away (paused, or lost focus on mobile/web); 0 when it is not away.
var _away_since := 0.0
## Seconds the sim ticked since _away_since: already simulated at full rate, so not credited again on return.
var _ticked_since := 0.0


## Set by Main while a modal is open: breaking news does not spawn then (see News).
var news_held := false


func _ready() -> void:
	state = GameState.new(Content, randi())
	# Records (see Records) are kept here, from the same signals for manual actions and sim events alike.
	producer_bought.connect(func(id: String, _n: int) -> void: Records.note(state.persist, "producers", id))
	research_bought.connect(func(id: String) -> void: Records.note(state.persist, "research", id))
	challenge_finished.connect(_on_challenge_finished)
	agi_advanced.connect(func(index: int) -> void: Records.note_agi(state.persist, index))
	ending_reached.connect(func(id: String) -> void: Records.note_ending(state, id))
	layer_reset.connect(_on_layer_reset)
	new_run_started.connect(func() -> void: Records.new_run(state.persist))


## Loads the save (if any), simulates the time since it was written, then starts ticking.
func start() -> void:
	var d := SaveSystem.load_data(save_path)
	if not d.is_empty():
		state = GameState.from_dict(Content, d)
	apply_settings()
	Records.absorb(state)  # counts what a loaded save already holds; the hooks in _ready count the rest
	Reveals.seed(state)
	if SaveSystem.last_notice != "":
		save_notice.emit(SaveSystem.last_notice)
	var saved_at := float(state.persist.get("saved_at", 0.0))
	var away := maxf(0.0, Time.get_unix_time_from_system() - saved_at) if saved_at > 0.0 else 0.0
	_catch_up(away, away)
	started.emit()
	running = true


## Credits `credit` seconds of offline progress (at 50% efficiency, by Sim.offline) and saves it. `away` is the real
## time away, reported to the player. Nothing is credited while the intro is unplayed: the intro must not sit over
## an offline dialog.
func _catch_up(credit: float, away: float) -> void:
	Sim.drop_stale_pending(state)
	if credit <= 1.0 or not bool(state.persist.get("intro_seen", true)):
		return
	var summary := Sim.offline(state, credit)
	summary["away"] = away
	_dispatch(summary["events"])
	save_now()  # so a quit before the next autosave cannot credit this time again
	if away >= SUMMARY_MIN_SECONDS:
		offline_progress.emit(summary)


func _process(delta: float) -> void:
	if not running:
		return
	var dt := minf(delta, MAX_TICK_SECONDS)
	_dispatch(Sim.tick(state, dt, false, news_held))
	if _away_since > 0.0:
		_ticked_since += dt
	_autosave_t += dt
	if _autosave_t >= AUTOSAVE_SECONDS:
		_autosave_t = 0.0
		save_now()


func _notification(what: int) -> void:
	if state == null:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_now()
		NOTIFICATION_APPLICATION_PAUSED:
			_begin_away()
		NOTIFICATION_APPLICATION_RESUMED:
			_end_away()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_now()
			if _losing_focus_is_away():
				_begin_away()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if _losing_focus_is_away():
				_end_away()


## On phones and in browsers a lost focus means the app is in the background (notification shade, tab switch).
## On desktop it is just a click elsewhere, so the sim keeps running and nothing is credited.
static func _losing_focus_is_away() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web")


## The app went away: save now, and start measuring how long. A second signal for the same absence is ignored.
func _begin_away() -> void:
	save_now()
	if _away_since == 0.0:
		_away_since = Time.get_unix_time_from_system()
		_ticked_since = 0.0


## The app came back. Credits the part of the absence the sim did not already tick through. No marker means a
## resume at launch (nothing to credit); a stopped sim (the intro is up) only closes the measurement.
func _end_away() -> void:
	if _away_since == 0.0:
		return
	var away := Time.get_unix_time_from_system() - _away_since
	var ticked := _ticked_since
	_away_since = 0.0
	_ticked_since = 0.0
	if running:
		_catch_up(maxf(0.0, away - ticked), away)


func _on_challenge_finished(id: String, success: bool) -> void:
	if success:
		Records.note(state.persist, "challenges", id)


func _on_layer_reset(layer: int, gain: int) -> void:
	Records.note_gain(state.persist, layer, gain)
	var r := Records.note_reset(state.persist, layer)
	if r["record"]:
		record_set.emit(layer, float(r["secs"]))


func save_now() -> bool:
	state.persist["saved_at"] = Time.get_unix_time_from_system()
	var ok := SaveSystem.save(state.to_dict(), save_path)
	saved.emit(ok)
	return ok


# ---------------------------------------------------------------- read-only helpers

func cash() -> BigNum:
	return state.cur("cash")


func compute() -> BigNum:
	return state.cur("compute")


func cash_per_second() -> BigNum:
	return Sim.cash_per_second(state)


func compute_per_second() -> BigNum:
	return Sim.compute_per_second(state)


func producer_cost(id: String, count: int = 1) -> BigNum:
	return Sim.cost_for(state, id, count)


func max_affordable(id: String) -> int:
	return Sim.max_affordable(state, id)


func producer_available(id: String) -> bool:
	return Sim.producer_available(state, id)


func reset_preview(layer: int) -> Dictionary:
	return Sim.reset_preview(state, layer)


func training_preview(run_type: String) -> Dictionary:
	return Sim.training_preview(state, run_type)


func staff_cost(role: String, count: int = 1) -> BigNum:
	return Sim.staff_cost(state, role, count)


# ---------------------------------------------------------------- actions

func buy_producer(id: String, count: int = 1) -> Dictionary:
	var r := Sim.buy_producer(state, id, count)
	if r["ok"]:
		producer_bought.emit(id, r["count"])
	return r


func start_training(run_type: String) -> Dictionary:
	var r := Sim.start_training(state, run_type)
	if r["ok"]:
		training_started.emit(run_type)
	return r


func hire(role: String, count: int = 1) -> Dictionary:
	var r := Sim.hire(state, role, count)
	if r["ok"]:
		staff_hired.emit(role, count)
	return r


func research(id: String) -> Dictionary:
	var r := Sim.research(state, id)
	if r["ok"]:
		research_bought.emit(id)
	return r


func set_slider(value: float) -> Dictionary:
	var r := Sim.set_slider(state, value)
	if r["ok"]:
		slider_changed.emit(r["value"])
	return r


func buy_automation(id: String) -> Dictionary:
	var r := Sim.buy_automation(state, id)
	if r["ok"]:
		automation_bought.emit(id)
	return r


func buy_upgrade(id: String) -> Dictionary:
	var r := Upgrades.buy(state, id)
	if r["ok"]:
		upgrade_bought.emit(id)
	return r


func fire_launch(id: String) -> Dictionary:
	var r := Launches.fire(state, id)
	if r["ok"]:
		launch_fired.emit(id)
	return r


func start_moonshot(id: String) -> Dictionary:
	var r := Moonshots.start(state, id)
	if r["ok"]:
		moonshot_started.emit(id)
	return r


func start_research_programme() -> Dictionary:
	var r := Moonshots.start_programme(state)
	if r["ok"]:
		moonshot_started.emit("research_programme")
	return r


func catch_news() -> Dictionary:
	var r := News.catch(state)
	if r["ok"]:
		news_caught.emit(r["id"], r)
	return r


## Clears the pending AGI stage: "ship" at once, "redteam" or "full" starts an evaluation (see Endgame).
func agi_choose(method: String) -> Dictionary:
	var r := Endgame.start_choice(state, method)
	if r["ok"]:
		_dispatch(r["events"])
	return r


func outship(id: String) -> Dictionary:
	var r := Endgame.outship(state, id)
	if r["ok"]:
		race_action.emit(id, "outship")
	return r


func acqui_hire(id: String) -> Dictionary:
	var r := Endgame.acqui(state, id)
	if r["ok"]:
		race_action.emit(id, "acqui")
	return r


func buy_legacy(key: String) -> Dictionary:
	var r := Sim.buy_legacy(state, key)
	if r["ok"]:
		legacy_bought.emit(key)
	return r


func start_challenge(id: String) -> Dictionary:
	var r := Sim.start_challenge(state, id)
	if r["ok"]:
		challenge_started.emit(id)
	return r


func abandon_challenge() -> Dictionary:
	var id := String(state.run["layers"][4]["challenge"].get("id", ""))
	var r := Sim.abandon_challenge(state)
	if r["ok"]:
		challenge_abandoned.emit(id)
	return r


func resolve_event(choice: int) -> Dictionary:
	var r := Sim.resolve_event(state, choice)
	if r["ok"]:
		event_resolved.emit(r["id"], choice)
	return r


func resolve_paper(slot: int, choice: int) -> Dictionary:
	var r := Desk.resolve(state, slot, choice)
	if r["ok"]:
		paper_resolved.emit(r["id"], choice)
	return r


func reset_layer(layer: int) -> Dictionary:
	var r := Sim.perform_reset(state, layer)
	if r["ok"]:
		layer_reset.emit(layer, r["gain"])
	return r


func new_run() -> Dictionary:
	var r := Sim.new_run(state)
	if r["ok"]:
		new_run_started.emit()
	return r


func set_setting(key: String, value: Variant) -> void:
	state.persist["settings"][key] = value
	apply_settings()
	settings_changed.emit(key, value)


## Pushes the display settings that BigNum reads (number notation). Call after any change to state.persist.settings
## or after replacing `state` (import, hard reset).
func apply_settings() -> void:
	BigNum.notation = BigNum.notation_from_key(String(state.persist["settings"].get("notation", "suffix")))


func _dispatch(evs: Array) -> void:
	for e in evs:
		match e["kind"]:
			"training_done":
				Records.note_deployment_burst(state.persist, e.get("revenue", BigNum.new()))
				training_finished.emit(e)
			"auto_train":
				training_started.emit(e["id"])
			"reset":
				layer_reset.emit(e["layer"], e["gain"])
			"challenge_done":
				challenge_finished.emit(e["id"], e["success"])
			"rival_launched":
				rival_launched.emit(e["id"])
			"agi_advanced":
				agi_advanced.emit(e["index"])
			"ending":
				ending_reached.emit(e["id"])
			"benchmark":
				benchmark_unlocked.emit(e["id"], e["badge"])
			"paper_offered":
				paper_offered.emit(e["id"])
			"paper_resolved":
				paper_resolved.emit(e["id"], e["choice"])
			"event":
				event_offered.emit(e["id"])
			"upgrade_bought":
				upgrade_bought.emit(e["id"])
			"launch_fired":
				launch_fired.emit(e["id"])
			"news":
				news_spawned.emit(e["id"])
			"moonshot_done":
				moonshot_finished.emit(e["id"])
			"agi_cleared":
				agi_cleared.emit(e["index"], e["method"])
			"agi_failed":
				agi_failed.emit(e["index"], e["method"])
			"rival_outpaced":
				rival_outpaced.emit(e["id"])
