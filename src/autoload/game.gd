extends Node
## Autoload `Game`: owns the GameState, ticks it each frame, autosaves, and turns sim results into signals.
## Every action returns the Sim result dict ({ok, reason, ...}) and emits its signal only on success.
## See docs/API.md.

signal started
signal offline_progress(summary: Dictionary)
signal producer_bought(id: String, count: int)
signal training_started(frac: float)
signal training_finished(result: Dictionary)
signal staff_hired(role: String, count: int)
signal research_bought(id: String)
signal slider_changed(value: float)
signal automation_bought(id: String)
signal legacy_bought(key: String)
signal challenge_started(id: String)
signal challenge_finished(id: String, success: bool)
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

const AUTOSAVE_SECONDS := 30.0

var state: GameState
var running := false
var save_path: String = "user://save.json"
var _autosave_t := 0.0


func _ready() -> void:
	state = GameState.new(Content, randi())


## Loads the save (if any), simulates the time since it was written, then starts ticking.
func start() -> void:
	var d := SaveSystem.load_data(save_path)
	if not d.is_empty():
		state = GameState.from_dict(Content, d)
		var away: float = Time.get_unix_time_from_system() - float(state.persist["saved_at"])
		if away > 1.0:
			var summary := Sim.offline(state, away)
			_dispatch(summary["events"])
			offline_progress.emit(summary)
	started.emit()
	running = true


func _process(delta: float) -> void:
	if not running:
		return
	_dispatch(Sim.tick(state, delta))
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_SECONDS:
		_autosave_t = 0.0
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and state != null:
		save_now()


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


func training_preview(frac: float) -> Dictionary:
	return Sim.training_preview(state, frac)


# ---------------------------------------------------------------- actions

func buy_producer(id: String, count: int = 1) -> Dictionary:
	var r := Sim.buy_producer(state, id, count)
	if r["ok"]:
		producer_bought.emit(id, r["count"])
	return r


func start_training(frac: float) -> Dictionary:
	var r := Sim.start_training(state, frac)
	if r["ok"]:
		training_started.emit(frac)
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
				training_started.emit(0.25)  # Sim._automate starts training at frac 0.25
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
