extends PanelBase
## Training: pick a run type (spend share, length, fail risk, score multiplier). A success scores; a failure refunds
## half the spend. Run history is session-only.

var _cards: Dictionary = {}    # run id -> {btn, blocker, bar, win, fail}
var _runs: Array = []          # TrainingRunDef, by order then id
var _status: Label
var _bar: ProgressBar
var _scores: Label
var _factors: Label
var _energy: Label
var _history: Label
var _log: Array[String] = []
var _how_toggle: Button
var _how_body: Label


## First time the panel is shown ever: open the explainer. After that the saved choice wins.
func _on_visibility_changed() -> void:
	if not visible:
		return
	var st: Dictionary = Game.state.persist["settings"]
	if not bool(st.get("training_help_seen", false)):
		st["training_help_seen"] = true
		_set_how(true)
		Game.save_now()


func _toggle_how() -> void:
	_set_how(not _how_body.visible)
	Game.state.persist["settings"]["training_help_open"] = _how_body.visible
	Game.save_now()


func _set_how(open: bool) -> void:
	_how_body.visible = open
	_how_toggle.text = ("v  " if open else ">  ") + "How it works"


func _build() -> void:
	_runs = Content.get_all("training_runs")
	_runs.sort_custom(func(a, b) -> bool: return a.order < b.order if a.order != b.order else a.id < b.id)

	# Collapsible explainer. Expanded the first time the panel is ever shown, then it keeps the player's last choice.
	var how_box := VBoxContainer.new()
	how_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how_box.add_theme_constant_override("separation", 6)
	page.add_child(how_box)
	var how_head := HBoxContainer.new()
	how_head.add_theme_constant_override("separation", 6)
	how_box.add_child(how_head)
	_how_toggle = Button.new()
	_how_toggle.custom_minimum_size = Vector2(0, 36)  # hit target: well above 28 px
	_how_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_how_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_how_toggle.clip_text = true
	_how_toggle.pressed.connect(_toggle_how)
	how_head.add_child(_how_toggle)
	how_head.add_child(PanelHelp.button("training"))
	_how_body = PanelKit.label(
		"1. Pick a run. It spends a share of your compute at once and runs for a set time.\n"
		+ "2. Success: score = log10(spend) x training multiplier x run score x a roll of +/-2%.\n"
		+ "3. Failure: no score, and half the spend comes back to compute.\n"
		+ "Only bests count. Your generation best sets the bonus; the all-time best adds a smaller one that survives resets. Hired Ops cut the fail chance.",
		PanelKit.TEXT)
	how_box.add_child(_how_body)
	_set_how(bool(Game.state.persist["settings"].get("training_help_open", false)))
	visibility_changed.connect(_on_visibility_changed)

	var run_box := PanelKit.section(page, "Training run", "training")
	_status = PanelKit.label("")
	run_box.add_child(_status)
	_bar = PanelKit.bar(PanelKit.CYAN)
	run_box.add_child(_bar)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	run_box.add_child(flow)
	for d in _runs:
		flow.add_child(_card(d))
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


## One card per run type: its header, a start button, why it is blocked, and the two outcomes.
func _card(d) -> PanelContainer:
	var id: String = d.id
	var c := PanelKit.card()
	c.custom_minimum_size.x = 260.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	c.add_child(v)
	v.add_child(PanelKit.label("%s: %s of compute, %ds, score x%.2f" % [
		d.title, PanelKit.pct(d.spend_share), int(d.seconds), d.score_mult], PanelKit.BRIGHT))
	var btn := PanelKit.button("", Callable(), false)
	btn.pressed.connect(func() -> void: _start(id))
	v.add_child(btn)
	var blocker := PanelKit.label("", PanelKit.GOLD)
	blocker.visible = false
	v.add_child(blocker)
	var bar := PanelKit.bar(PanelKit.TEAL)
	bar.visible = false
	v.add_child(bar)
	var win := PanelKit.label("", PanelKit.GREEN)
	v.add_child(win)
	var fail := PanelKit.label("", PanelKit.AMBER)
	v.add_child(fail)
	Tip.attach(c, Callable(self, "_tip").bind(id))
	_cards[id] = {"btn": btn, "blocker": blocker, "bar": bar, "win": win, "fail": fail}
	return c


func wants_attention() -> bool:
	if not (Game.state.run["layers"][0]["training"] as Dictionary).is_empty():
		return false
	for d in _runs:
		if Game.training_preview(d.id)["ok"]:
			return true
	return false


## Why run `id` is blocked right now, or "" when it can start: a run already going, compute short, energy/data short.
func _blocker(id: String, p: Dictionary) -> String:
	var s: GameState = Game.state
	if not (s.run["layers"][0]["training"] as Dictionary).is_empty():
		return "Already training. Wait for this run to finish."
	var min_c: BigNum = p["min_compute"]
	if s.cur("compute").compare(min_c) < 0:
		return "Needs %s compute for %s; you have %s." % [
			min_c.format(), Sim.run_def(s, id).title, s.cur("compute").format()]
	if not p["ok"]:
		return "Needs %d energy and %d data; you have %s energy and %s data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA), s.cur("energy").format(), s.cur("data").format()]
	return ""


## Full explanation of one run type: spend, outcome, fail chance and what a bigger run buys.
func _tip(id: String) -> String:
	var s: GameState = Game.state
	var p: Dictionary = Game.training_preview(id)
	var d = Sim.run_def(s, id)
	var fac: Dictionary = p["factors"]
	var total := float(fac["total"])
	var lines: Array[String] = []
	lines.append("%s: %s of your compute, %ds." % [d.title, PanelKit.pct(d.spend_share), int(d.seconds)])
	lines.append(d.description)
	lines.append("Spends %s of your %s compute up front." % [(p["spend"] as BigNum).format(), s.cur("compute").format()])
	lines.append("Score = log10(spend) x multiplier x%.2f x run score x%.2f, rolled +/-%d%%. Predicted now: %.2f." % [
		total, d.score_mult, roundi(Sim.SCORE_ROLL * 100.0), float(p["predicted_score"])])
	lines.append("Fail chance %s (base %s, Ops x%.2f). A failed run scores nothing; half the spend returns." % [
		PanelKit.pct(float(p["fail_chance"])), PanelKit.pct(float(p["base_fail"])), float(p["fail_factor"])])
	lines.append("Each doubling of spend adds %.2f to the score. Bigger runs score more but fail more often." % (
		log(2.0) / log(10.0) * total * float(d.score_mult)))
	lines.append("Minimum spend is %d compute, so this needs %s compute." % [
		int(Sim.MIN_TRAIN_SPEND), (p["min_compute"] as BigNum).format()])
	if s.resets(3) > 0:
		lines.append("Also costs %d energy and %d data." % [int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)])
	return "\n".join(lines)


func _start(id: String) -> void:
	var r: Dictionary = Game.start_training(id)
	report(r, "Started %s. Its result shows here when it ends." % Sim.run_def(Game.state, id).title)
	if r.get("ok", false):
		PanelKit.pop(_cards[id]["btn"])


## Post-run result line (green on a score, amber on a failure) and the session history.
func _on_finished(r: Dictionary) -> void:
	var title: String = Sim.run_def(Game.state, r["id"]).title
	var line: String
	if r.get("ok", false):
		var tags := ""
		if r["new_all_time"]:
			tags = " (new all-time best)"
		elif r["new_best"]:
			tags = " (new best)"
		line = "%s finished: score %.2f%s." % [title, float(r["score"]), tags]
		result_line.add_theme_color_override("font_color", PanelKit.col(PanelKit.GREEN))
	else:
		line = "%s failed: no score, %s returned to compute." % [title, (r["refund"] as BigNum).format()]
		result_line.add_theme_color_override("font_color", PanelKit.col(PanelKit.AMBER))
	result_line.text = line
	PanelKit.flash(result_line)
	_log.push_front(line)
	if _log.size() > 8:
		_log.resize(8)
	_history.text = "\n".join(_log)


func _refresh() -> void:
	var s: GameState = Game.state
	var t: Dictionary = s.run["layers"][0]["training"]
	if t.is_empty():
		_status.text = "Idle. Pick a run below."
		_bar.value = 0.0
	else:
		var d = Sim.run_def(s, t["type"])
		_status.text = "Training: %s, %ds left." % [d.title, ceili(float(t["left"]))]
		_bar.max_value = float(d.seconds)
		_bar.value = float(d.seconds) - float(t["left"])
	for d in _runs:
		var id: String = d.id
		var p: Dictionary = Game.training_preview(id)
		var c: Dictionary = _cards[id]
		c.btn.text = "Start %s" % d.title
		c.btn.disabled = not p["ok"]
		var why := _blocker(id, p)
		c.blocker.text = why
		c.blocker.visible = why != ""
		# Compute progress toward the minimum this run needs; hidden once enough is held.
		var min_c: BigNum = p["min_compute"]
		var cur := s.cur("compute")
		var bar: ProgressBar = c.bar
		bar.visible = cur.compare(min_c) < 0
		bar.max_value = 1.0
		bar.value = 0.0 if cur.is_zero() else clampf(pow(10.0, cur.log10() - min_c.log10()), 0.0, 1.0)
		c.win.text = "If it works: score %.2f, compute bonus x%.2f -> x%.2f." % [
			float(p["predicted_score"]), float(p["bonus_now"]), float(p["bonus_if_success"])]
		c.fail.text = "Fail %s (base %s, Ops x%.2f): no score, %s back to compute." % [
			PanelKit.pct(float(p["fail_chance"])), PanelKit.pct(float(p["base_fail"])), float(p["fail_factor"]),
			(p["spend"] as BigNum).mul_f(Sim.REFUND_SHARE).format()]
	var fac: Dictionary = Sim.training_factors(s)
	_factors.text = "Multiplier: data x%.2f, architecture x%.2f, researchers x%.2f, total x%.2f." % [
		fac["data"], fac["architecture"], fac["researcher"], fac["total"]]
	_scores.text = "Best this generation: %.2f. Best ever: %.2f. Runs: %d, failed: %d." % [
		float(s.run["layers"][2]["best"]), float(s.persist["best_all"]),
		int(s.persist["stats"]["trainings"]), int(s.persist["stats"]["failed"])]
	if s.resets(3) == 0:
		_energy.text = "Energy and data unlock after a Paradigm Shift. Each run then costs %d energy and %d data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)]
	else:
		_energy.text = "Each run costs %d energy and %d data. You have %s energy and %s data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA), s.cur("energy").format(), s.cur("data").format()]
