extends PanelBase
## Training: pick a run type (spend share, length, fail risk, score multiplier, cash burst). A success scores and pays
## its cash burst; a failure refunds half the spend. The rules live in the Help tab (Training topic); each row's
## tooltip has the numbers for that run.

var _cards: Dictionary = {}    # run id -> {btn, stat, bar}
var _runs: Array = []          # TrainingRunDef, by order then id
var _status: Label
var _bar: ProgressBar
var _best: Label
var _msg := ""                 # last start or result, shown on the status line while idle
var _msg_color := -1


func _build() -> void:
	result_line.visible = false  # the status line below takes its place (see report)
	_runs = Content.get_all("training_runs")
	_runs.sort_custom(func(a, b) -> bool: return a.order < b.order if a.order != b.order else a.id < b.id)
	page.add_theme_constant_override("separation", 6)

	_status = PanelKit.label("", PanelKit.TEXT, false)
	_status.theme_type_variation = &"MicroLabel"
	_status.clip_text = true
	page.add_child(_status)
	_bar = PanelKit.bar(PanelKit.CYAN)
	_bar.custom_minimum_size.y = 6
	page.add_child(_bar)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	page.add_child(rows)
	for d in _runs:
		rows.add_child(_row(d))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	page.add_child(foot)
	_best = PanelKit.label("", PanelKit.MUTED, false)
	_best.theme_type_variation = &"MicroLabel"
	_best.clip_text = true
	_best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tip.attach(_best, Callable(self, "_factors_tip"))
	foot.add_child(_best)
	foot.add_child(PanelHelp.button("training"))
	Game.training_finished.connect(_on_finished)


## Action results (start, or the finished run) go on the status line, in green or amber.
func report(r: Dictionary, ok_text: String) -> void:
	var ok: bool = r.get("ok", false)
	if not ok: Audio.play("cant_afford")
	else: Audio.play("training_start")
	_msg = ok_text if ok else str(r.get("reason", "Failed."))
	_msg_color = PanelKit.GREEN if ok else PanelKit.RED
	PanelKit.flash(_status)
	_refresh()


func wants_attention() -> bool:
	if not (Game.state.run["layers"][0]["training"] as Dictionary).is_empty():
		return false
	for d in _runs:
		if Game.training_preview(d.id)["ok"]:
			return true
	return false


## One full-width row per run type: name and Start button on top, a compact stat line under them.
## The stat line is "spend / seconds / fail chance / predicted score"; a run with a cash burst swaps the spend share
## for the burst ("+X"). A score above the best is marked with ^ in green.
func _row(d) -> PanelContainer:
	var id: String = d.id
	var c := PanelKit.card()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	c.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(PanelKit.label(d.title, PanelKit.BRIGHT, false))
	var stat := PanelKit.label("", PanelKit.MUTED)  # wraps at phone width rather than clipping a late-game burst
	stat.theme_type_variation = &"MicroLabel"
	left.add_child(stat)
	var bar := PanelKit.bar(PanelKit.TEAL)  # compute toward the minimum spend; only while short
	bar.custom_minimum_size.y = 6
	bar.visible = false
	left.add_child(bar)
	var btn := PanelKit.button("Start", Callable(), false)
	btn.theme_type_variation = &"MicroButton"
	btn.custom_minimum_size = Vector2(64, PanelKit.TOUCH_H)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(func() -> void: _start(id))
	h.add_child(btn)
	# The row and its button share one tooltip: the blocker reason, when there is one, is its second line.
	Tip.attach(c, Callable(self, "_tip").bind(id))
	Tip.attach(btn, Callable(self, "_tip").bind(id))
	_cards[id] = {"btn": btn, "stat": stat, "bar": bar}
	return c


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
	var why := _blocker(id, p)
	if why != "":
		lines.append("Blocked: " + why)
	lines.append(d.description)
	lines.append("Spends %s of your %s compute up front." % [(p["spend"] as BigNum).format(), s.cur("compute").format()])
	lines.append("Score = log10(spend) x multiplier x%.2f x run score x%.2f, rolled +/-%d%%. Predicted now: %.2f." % [
		total, d.score_mult, roundi(Sim.SCORE_ROLL * 100.0), float(p["predicted_score"])])
	lines.append("If it works: compute bonus x%.2f -> x%.2f." % [float(p["bonus_now"]), float(p["bonus_if_success"])])
	if float(d.revenue_seconds) > 0.0:
		lines.append("If it works: +%s cash burst (%ds of cash income now; half while away)." % [
			(p["revenue"] as BigNum).format(), int(d.revenue_seconds)])
	else:
		lines.append("No cash burst.")
	lines.append("Fail chance %s (base %s, Ops x%.2f). If it fails: no score or burst, %s (%s of spend) back to compute." % [
		PanelKit.pct(float(p["fail_chance"])), PanelKit.pct(float(p["base_fail"])), float(p["fail_factor"]),
		(p["spend"] as BigNum).mul_f(Sim.REFUND_SHARE).format(), PanelKit.pct(Sim.REFUND_SHARE)])
	lines.append("Each doubling of spend adds %.2f to the score. Bigger runs score more but fail more often." % (
		log(2.0) / log(10.0) * total * float(d.score_mult)))
	lines.append("Minimum spend is %d compute, so this needs %s compute." % [
		int(Sim.MIN_TRAIN_SPEND), (p["min_compute"] as BigNum).format()])
	if s.resets(3) > 0:
		lines.append("Also costs %d energy and %d data." % [int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)])
	return "\n".join(lines)


## Tooltip of the footer line: the multiplier breakdown and the score totals this generation.
func _factors_tip() -> String:
	var s: GameState = Game.state
	var fac: Dictionary = Sim.training_factors(s)
	var lines: Array[String] = []
	lines.append("Multiplier x%.2f" % float(fac["total"]))
	lines.append("Data x%.2f, architecture x%.2f, researchers x%.2f." % [
		fac["data"], fac["architecture"], fac["researcher"]])
	lines.append("Best this generation: %.2f. Best ever: %.2f. Runs: %d, failed: %d." % [
		float(s.run["layers"][2]["best"]), float(s.persist["best_all"]),
		int(s.persist["stats"]["trainings"]), int(s.persist["stats"]["failed"])])
	if s.resets(3) == 0:
		lines.append("Energy and data unlock after a Paradigm Shift. Each run then costs %d energy and %d data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)])
	else:
		lines.append("Each run costs %d energy and %d data. You have %s energy and %s data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA), s.cur("energy").format(), s.cur("data").format()])
	return "\n".join(lines)


func _start(id: String) -> void:
	var r: Dictionary = Game.start_training(id)
	report(r, "Started %s." % Sim.run_def(Game.state, id).title)
	if r.get("ok", false):
		PanelKit.pop(_cards[id]["btn"])


## Post-run result on the status line: green on a score (marked when it is a best), amber on a failure.
func _on_finished(r: Dictionary) -> void:
	if r.get("ok", false):
		var tag := ""
		if r["new_all_time"]:
			tag = " (all-time)"
		elif r["new_best"]:
			tag = " (best)"
		var cash := ""
		if (r["revenue"] as BigNum).compare(BigNum.new()) > 0:
			cash = ", +%s cash" % (r["revenue"] as BigNum).format()
		_msg = "Done: %.1f%s%s." % [float(r["score"]), tag, cash]
		_msg_color = PanelKit.GREEN
	else:
		_msg = "Failed: %s returned." % (r["refund"] as BigNum).format()
		_msg_color = PanelKit.AMBER
	PanelKit.flash(_status)
	_refresh()


func _refresh() -> void:
	var s: GameState = Game.state
	var t: Dictionary = s.run["layers"][0]["training"]
	var best := float(s.run["layers"][2]["best"])
	if t.is_empty():
		_status.text = _msg if _msg != "" else "Idle. Pick a run below."
		_status.add_theme_color_override("font_color", PanelKit.col(_msg_color if _msg != "" else PanelKit.TEXT))
		_bar.value = 0.0
	else:
		var d = Sim.run_def(s, t["type"])
		_status.text = "%s: %ds left" % [d.title, ceili(float(t["left"]))]
		_status.add_theme_color_override("font_color", PanelKit.col(PanelKit.CYAN))
		_bar.max_value = float(d.seconds)
		_bar.value = float(d.seconds) - float(t["left"])
	for d in _runs:
		var id: String = d.id
		var p: Dictionary = Game.training_preview(id)
		var c: Dictionary = _cards[id]
		c.btn.disabled = not p["ok"]
		var min_c: BigNum = p["min_compute"]
		var cur := s.cur("compute")
		var bar: ProgressBar = c.bar
		bar.visible = cur.compare(min_c) < 0
		bar.max_value = 1.0
		bar.value = 0.0 if cur.is_zero() else clampf(pow(10.0, cur.log10() - min_c.log10()), 0.0, 1.0)
		var score := float(p["predicted_score"])
		var beats := score > best
		var stat: Label = c.stat
		var mark := " ^" if beats else ""
		if float(d.revenue_seconds) > 0.0:  # short at phone width: the burst takes the spend share's place
			stat.text = "%ds fail %s -> %.1f%s +%s" % [int(d.seconds), PanelKit.pct(float(p["fail_chance"])),
				score, mark, (p["revenue"] as BigNum).format()]
		else:
			stat.text = "%s %ds fail %s -> %.1f%s" % [PanelKit.pct(d.spend_share), int(d.seconds),
				PanelKit.pct(float(p["fail_chance"])), score, mark]
		stat.add_theme_color_override("font_color", PanelKit.col(PanelKit.GREEN if beats else PanelKit.MUTED))
	_best.text = "Best %s / multiplier x%.2f" % [BigNum.from_float(best).format(), Sim.training_factors(s)["total"]]
