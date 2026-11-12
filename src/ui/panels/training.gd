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
	run_box.get_child(0).add_child(PanelHelp.button("training"))
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
		var blocker := PanelKit.label("", PanelKit.GOLD)
		blocker.visible = false
		v.add_child(blocker)
		var bar := PanelKit.bar(PanelKit.TEAL)
		bar.visible = false
		v.add_child(bar)
		var line := PanelKit.label("", PanelKit.MUTED)
		v.add_child(line)
		Tip.attach(c, Callable(self, "_tip").bind(f))
		_opts[f] = {"btn": btn, "line": line, "blocker": blocker, "bar": bar}
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
	if not Game.state.run["layers"][0]["training"].is_empty():
		return false
	for f in FRACS:
		if Game.training_preview(f)["ok"]:
			return true
	return false


## Why option `f` is blocked right now, or "" when it can run. Compute short, energy/data short, or a run already going.
func _blocker(f: float, p: Dictionary) -> String:
	var s: GameState = Game.state
	if not (s.run["layers"][0]["training"] as Dictionary).is_empty():
		return "Already training. Wait for this run to finish."
	var min_c: BigNum = p["min_compute"]
	if s.cur("compute").compare(min_c) < 0:
		return "Needs %s compute to train on %s — you have %s." % [
			min_c.format(), PanelKit.pct(f), s.cur("compute").format()]
	if not p["ok"]:
		return "Needs %d energy and %d data — you have %s energy and %s data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA), s.cur("energy").format(), s.cur("data").format()]
	return ""


## Full explanation of one training option: spend, fail chance, predicted score and what a bigger run buys.
func _tip(f: float) -> String:
	var s: GameState = Game.state
	var p: Dictionary = Game.training_preview(f)
	var fac: Dictionary = p["factors"]
	var total := float(fac["total"])
	var lines: Array[String] = []
	lines.append("Train on %s of compute" % PanelKit.pct(f))
	lines.append("Spends %s of your %s compute up front, for a %ds run." % [
		(p["spend"] as BigNum).format(), s.cur("compute").format(), int(Sim.TRAIN_SECONDS)])
	lines.append("Score = log10(spend) × multiplier ×%.2f, rolled ±5%%. Predicted now: %.2f." % [
		total, float(p["predicted_score"])])
	lines.append("Fail chance %s. A failed run scores nothing and the spend is lost." % PanelKit.pct(float(p["fail_chance"])))
	lines.append("Each doubling of spend adds %.2f to the score. Bigger runs score more but fail more often." % (log(2.0) / log(10.0) * total))
	lines.append("Minimum spend is %d compute, so this needs %s compute." % [
		int(Sim.MIN_TRAIN_SPEND), (p["min_compute"] as BigNum).format()])
	if s.resets(3) > 0:
		lines.append("Also costs %d energy and %d data." % [int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)])
	return "\n".join(lines)


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
		var why := _blocker(f, p)
		var blocker: Label = o.blocker
		blocker.text = why
		blocker.visible = why != ""
		# Compute progress toward the minimum this option needs; hidden once enough is held.
		var min_c: BigNum = p["min_compute"]
		var cur := s.cur("compute")
		var bar: ProgressBar = o.bar
		bar.visible = cur.compare(min_c) < 0
		bar.max_value = 1.0
		bar.value = 0.0 if cur.is_zero() else clampf(pow(10.0, cur.log10() - min_c.log10()), 0.0, 1.0)
		var text := "Spend %s · %s chance to fail · predicted score %.2f" % [
			(p["spend"] as BigNum).format(), PanelKit.pct(float(p["fail_chance"])), float(p["predicted_score"])]
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
