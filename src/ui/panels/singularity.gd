extends PanelBase
## Singularity (layer 4): the final reset, which pays out legacy. Also legacy perks, regulation challenges,
## rival launches, the AGI stage ladder and the run's ending.

const LEGACY_KEYS := {"compute": "Compute", "cash": "Cash", "training": "Training score"}

var _card: PanelResetCard
var _legacy: Label
var _perks: Dictionary = {}     # key -> {buy: Button, info: Label}

var _ch_status: Label
var _ch_bar: ProgressBar
var _ch_abandon: Button
var _challenges: Dictionary = {}   # id -> {buy: Button, info: Label, def}

var _rivals: Dictionary = {}    # id -> {status: Label, def}
var _stages: Array[Label] = []
var _stage_defs: Array = []
var _ending_info: Label
var _endings: Array[Label] = []
var _new_run: Button


func _build() -> void:
	_card = PanelResetCard.new().setup(4, Callable(self, "report"))
	page.add_child(_card)

	var lb := PanelKit.section(page, "Legacy", "legacy")
	_legacy = PanelKit.label("", PanelKit.TEXT)
	lb.add_child(_legacy)
	lb.add_child(PanelKit.label(
		"Each perk multiplies its target by ×%s forever. Every purchase of the same perk costs double." % PanelText.num(Sim.LEGACY_MULT),
		PanelKit.MUTED))
	for key in LEGACY_KEYS:
		var c := PanelKit.card()
		lb.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(LEGACY_KEYS[key], PanelKit.BRIGHT))
		var info := PanelKit.label("", PanelKit.MUTED)
		v.add_child(info)
		var buy := action_button("", false,
			func() -> Dictionary: return Game.buy_legacy(key), "Legacy perk bought: %s." % LEGACY_KEYS[key])
		v.add_child(buy)
		_perks[key] = {"buy": buy, "info": info}

	var cb := PanelKit.section(page, "Regulation challenges", "regulation")
	cb.add_child(PanelKit.label(
		"One challenge at a time. Each has a goal checked when its time runs out: a reward if met, a penalty if not. " +
		"A completed challenge can't be entered again. Abandoning gives neither.", PanelKit.MUTED))
	var running := PanelKit.card()
	cb.add_child(running)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 4)
	running.add_child(rv)
	_ch_status = PanelKit.label("", PanelKit.TEXT)
	rv.add_child(_ch_status)
	_ch_bar = PanelKit.bar(PanelKit.TEAL)
	rv.add_child(_ch_bar)
	_ch_abandon = action_button("Abandon challenge", false,
		func() -> Dictionary: return Game.abandon_challenge(), "Challenge abandoned. No reward, no penalty.")
	rv.add_child(_ch_abandon)
	for d in Content.get_all("challenges"):
		var id: String = d.id
		var c := PanelKit.card()
		cb.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
		var info := PanelKit.label("", PanelKit.MUTED)
		v.add_child(info)
		var buy := action_button("", false,
			func() -> Dictionary: return Game.start_challenge(id), "Entered: %s." % d.title)
		v.add_child(buy)
		_challenges[id] = {"buy": buy, "info": info, "def": d}

	var rb := PanelKit.section(page, "Rivals", "rivals")
	rb.add_child(PanelKit.label("Rival labs launch on the Singularity clock. Their progress only moves with events.", PanelKit.MUTED))
	for d in Content.get_all("rivals"):
		var c := PanelKit.card()
		rb.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
		var status := PanelKit.label("", PanelKit.TEXT)
		v.add_child(status)
		_rivals[d.id] = {"status": status, "def": d}

	var ab := PanelKit.section(page, "AGI road", "agi")
	_stage_defs = Content.get_all("agi_stages")
	for d in _stage_defs:
		var c := PanelKit.card()
		ab.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
		var st := PanelKit.label("", PanelKit.TEXT)
		v.add_child(st)
		_stages.append(st)

	var eb := PanelKit.section(page, "Endings", "agi")
	_ending_info = PanelKit.label("", PanelKit.TEXT)
	eb.add_child(_ending_info)
	for d in Content.get_all("endings"):
		var l := PanelKit.label("", PanelKit.MUTED)
		eb.add_child(l)
		_endings.append(l)
	_new_run = action_button("Start a new legacy", false,
		func() -> Dictionary: return Game.new_run(), "New run started. Legacy kept.")
	eb.add_child(_new_run)


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(4)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if Sim.reset_preview(s, 4)["highlight"]:
		return true
	for key in LEGACY_KEYS:
		if Sim.legacy_blocker(s, key) == "":
			return true
	return false


func _refresh() -> void:
	_card.refresh()
	var s: GameState = Game.state
	_legacy.text = "Legacy: %s" % s.cur("legacy").format()
	for key in _perks:
		var o: Dictionary = _perks[key]
		var n := int(s.persist["legacy_perks"].get(key, 0))
		var reason := Sim.legacy_blocker(s, key)
		o.info.text = "Bought %d · now ×%.2f%s" % [n, float(s.persist["perm_mult"].get(key, 1.0)),
			"" if reason == "" else "\n" + reason]
		o.buy.text = "Buy for %s legacy" % Sim.legacy_cost(s, key).format()
		o.buy.disabled = reason != ""

	_refresh_challenges(s)
	_refresh_rivals(s)
	_refresh_agi(s)

	var over := String(s.run["run_over"])
	if over == "":
		_ending_info.text = "The run ends when the AGI road is finished. Reaching an ending shows its screen."
	else:
		var d = Content.get_def("endings", over)
		_ending_info.text = "This run ended: %s." % (d.title if d != null else over)
	_new_run.disabled = over == ""
	for i in _endings.size():
		var d = Content.get_all("endings")[i]
		var met := Rules.check_all(s, d.conditions)
		_endings[i].text = "%s: %s%s" % [d.title, PanelText.conditions(d.conditions), "  (met now)" if met else ""]


func _refresh_challenges(s: GameState) -> void:
	var c: Dictionary = s.run["layers"][4]["challenge"]
	if c.is_empty():
		_ch_status.text = "No challenge running."
		_ch_bar.value = 0.0
		_ch_abandon.disabled = true
	else:
		var d = Content.get_def("challenges", c["id"])
		_ch_bar.max_value = float(d.duration)
		_ch_bar.value = float(d.duration) - float(c["left"])
		_ch_status.text = "Running: %s · %s left" % [d.title, PanelKit.hms(float(c["left"]))]
		_ch_abandon.disabled = false
	for id in _challenges:
		var o: Dictionary = _challenges[id]
		var d = o["def"]
		var text := "Goal: %s\nReward: %s\nPenalty: %s\nTime: %s" % [
			PanelText.conditions(d.goal), PanelText.effects(d.reward), PanelText.effects(d.penalty),
			PanelKit.hms(float(d.duration))]
		var done: bool = id in s.run["challenges_done"]
		var reason := Sim.challenge_blocker(s, id)
		if done:
			var passed: bool = bool(s.run.get("challenge_passed", {}).get(id, false))
			text += "\nCompleted: " + ("passed." if passed else "failed.")
		elif reason != "" and reason != "a challenge is already running":
			text += "\n" + reason
		o.info.text = text
		o.buy.text = "Completed" if done else "Enter challenge"
		o.buy.disabled = reason != ""


func _refresh_rivals(s: GameState) -> void:
	var clock := float(s.run["layers"][4]["clock"])
	for id in _rivals:
		var o: Dictionary = _rivals[id]
		var d = o["def"]
		if bool(s.run["flags"].get("rival_%s_launched" % id, false)):
			o.status.text = "Launched."
		elif s.resets(4) == 0:
			o.status.text = "Waits for the Singularity. Launch at %s on the clock." % PanelKit.hms(Sim.rival_launch_time(s, id))
		else:
			var left := Sim.rival_launch_time(s, id) - clock
			o.status.text = "Launches in %s (progress %+d%%)." % [PanelKit.hms(left), roundi(float(s.run["rivals"].get(id, 0.0)) * 100.0)]


func _refresh_agi(s: GameState) -> void:
	var stage := int(s.run["stage"])
	for i in _stage_defs.size():
		var d = _stage_defs[i]
		var head := "Done." if i < stage else ("Next." if i == stage else "Locked.")
		var lines: Array[String] = []
		for c in d.conditions:
			if c["type"] == "compute_rate_gte":
				lines.append(("[x] " if Rules.check(s, c) else "[ ] ") + "Sustain %s FLOP/s (now %s/s)" % [
					BigNum.from_float(float(c["value"])).format(), Sim.compute_per_second(s).format()])
				continue
			var cn := PanelText.condition_now(s, c)
			lines.append(("[x] " if cn["met"] else "[ ] ") + cn["text"])
		_stages[i].text = head + "\n" + "\n".join(lines)
