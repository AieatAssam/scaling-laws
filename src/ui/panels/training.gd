extends PanelBase
## Training: spend compute on a 60 s run. The score feeds Model Generation and the all-time best. Run history is session-only.

const FRACS := [0.25, 0.5, 1.0]

var _opts: Dictionary = {}     # frac -> {btn: Button, line: Label}
var _status: Label
var _bar: ProgressBar
var _scores: Label
var _factors: Label
var _energy: Label
var _history: Label
var _log: Array[String] = []


func _build() -> void:
	var run_box := PanelKit.section(page, "Training run", "training")
	_status = PanelKit.label("")
	run_box.add_child(_status)
	_bar = PanelKit.bar(PanelKit.CYAN)
	run_box.add_child(_bar)
	run_box.add_child(PanelKit.label(
		"Score = log10(compute spent) × training multiplier, rolled ±5%. A failed run scores nothing.", PanelKit.MUTED))
	for f in FRACS:
		var c := PanelKit.card()
		run_box.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		var btn := PanelKit.button("", Callable(), false)
		btn.pressed.connect(func() -> void: _start(f))
		v.add_child(btn)
		var line := PanelKit.label("", PanelKit.MUTED)
		v.add_child(line)
		_opts[f] = {"btn": btn, "line": line}
	_energy = PanelKit.label("", PanelKit.MUTED)
	run_box.add_child(_energy)

	var score_box := PanelKit.section(page, "Scores", "benchmarks")
	_scores = PanelKit.label("")
	score_box.add_child(_scores)
	_factors = PanelKit.label("", PanelKit.TEXT)
	score_box.add_child(_factors)

	var hist_box := PanelKit.section(page, "This session", "insights")
	_history = PanelKit.label("No runs yet this session.", PanelKit.MUTED)
	hist_box.add_child(_history)
	Game.training_finished.connect(_on_finished)


func is_unlocked() -> bool:
	return true


func wants_attention() -> bool:
	return Game.state.run["layers"][0]["training"].is_empty() and bool(Game.training_preview(0.25)["ok"])


func _start(frac: float) -> void:
	var r: Dictionary = Game.start_training(frac)
	report(r, "Training started on %s of compute." % PanelKit.pct(frac))
	if r.get("ok", false):
		PanelKit.pop(_opts[frac]["btn"])


func _on_finished(r: Dictionary) -> void:
	var line := "Score %.2f" % float(r["score"]) if r.get("ok", false) else "Failed: no score."
	_log.push_front(line)
	if _log.size() > 8:
		_log.resize(8)
	_history.text = "\n".join(_log)


func _refresh() -> void:
	var s: GameState = Game.state
	var t: Dictionary = s.run["layers"][0]["training"]
	if t.is_empty():
		_status.text = "Idle. Pick a share of compute to train with."
		_bar.value = 0.0
	else:
		_status.text = "Training on %s of compute: %ds left." % [PanelKit.pct(float(t["frac"])), ceili(float(t["left"]))]
		_bar.max_value = Sim.TRAIN_SECONDS
		_bar.value = Sim.TRAIN_SECONDS - float(t["left"])
	for f in FRACS:
		var p: Dictionary = Game.training_preview(f)
		var o: Dictionary = _opts[f]
		o.btn.text = "Train on %s" % PanelKit.pct(f)
		o.btn.disabled = not p["ok"]
		var text := "Spend %s · %s chance to fail · predicted score %.2f" % [
			(p["spend"] as BigNum).format(), PanelKit.pct(float(p["fail_chance"])), float(p["predicted_score"])]
		if not p["ok"]:
			text += "\n" + str(p["reason"])
		o.line.text = text
	var fac: Dictionary = Sim.training_factors(s)
	_factors.text = "Multiplier: data ×%.2f · architecture ×%.2f · researchers ×%.2f · total ×%.2f" % [
		fac["data"], fac["architecture"], fac["researcher"], fac["total"]]
	_scores.text = "Best this generation: %.2f · best ever: %.2f · runs: %d · failed: %d" % [
		float(s.run["layers"][2]["best"]), float(s.persist["best_all"]),
		int(s.persist["stats"]["trainings"]), int(s.persist["stats"]["failed"])]
	if s.resets(3) == 0:
		_energy.text = "Energy and data unlock after a Paradigm Shift. Each run then costs %d energy and %d data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)]
	else:
		_energy.text = "Each run costs %d energy and %d data. You have %s energy and %s data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA), s.cur("energy").format(), s.cur("data").format()]
