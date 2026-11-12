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


func _ready() -> void:
	state = GameState.new(Content, randi())


## Loads the save (if any), simulates the time since it was written, then starts ticking.
func start() -> void:
	var d := SaveSystem.load_data(save_path)
	if not d.is_empty():
		state = GameState.from_dict(Content, d)
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
	_dispatch(Sim.tick(state, dt))
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
	settings_changed.emit(key, value)


func _dispatch(evs: Array) -> void:
	for e in evs:
		match e["kind"]:
			"training_done":
				training_finished.emit(e)
			"auto_train":
				training_started.emit(Sim.AUTO_TRAIN_RUN)
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
			"event":
				event_offered.emit(e["id"])
