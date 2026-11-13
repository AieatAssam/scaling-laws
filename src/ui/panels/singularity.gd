extends PanelBase
## Singularity (layer 4): the final reset, which pays out legacy. Also legacy perks, the AGI road (one safety
## choice per stage; the most common choice sets the ending), the rival race and regulation challenges in three tiers.

const LEGACY_KEYS := {"compute": "Compute", "cash": "Cash", "training": "Training score"}
const TIER_NUMERALS := ["I", "II", "III"]
const METHODS := ["full", "redteam", "ship"]

var _card: PanelResetCard
var _legacy: Label
var _perks: Dictionary = {}     # key -> {buy: Button, info: Label}

var _counters: Label
var _trajectory: Label
var _decision: Label
var _eval_bar: ProgressBar
var _eval_status: Label
var _choices: Dictionary = {}   # method -> {buy: Button, info: Label}
var _stages: Array[Label] = []
var _stage_defs: Array = []

var _rivals: Dictionary = {}    # id -> {bar, status, outship: {buy, info}, acqui: {buy, info}, def}

var _ch_status: Label
var _ch_bar: ProgressBar
var _ch_abandon: Button
var _challenges: Dictionary = {}   # id -> {buy: Button, info: Label, def}

var _endings: Array[Label] = []
var _new_run: Button


func _build() -> void:
	_card = PanelResetCard.new().setup(4, Callable(self, "report"))
	page.add_child(_card)

	var lb := PanelKit.section(page, "Legacy", "legacy")
	_legacy = PanelKit.label("", PanelKit.TEXT)
	lb.add_child(_legacy)
	lb.add_child(PanelKit.label(
		"Each perk multiplies its target by x%s forever. Every purchase of the same perk costs double." % PanelText.num(Sim.LEGACY_MULT),
		PanelKit.MUTED))
	for key in LEGACY_KEYS:
		var c := PanelKit.card()
		Tip.attach(c, Callable(self, "_perk_tip").bind(key))
		lb.add_child(c)
		var v := _column(c)
		v.add_child(PanelKit.label(LEGACY_KEYS[key], PanelKit.BRIGHT))
		var info := PanelKit.label("", PanelKit.MUTED)
		v.add_child(info)
		var buy := action_button("", false,
			func() -> Dictionary: return Game.buy_legacy(key), "Legacy perk bought: %s." % LEGACY_KEYS[key])
		v.add_child(buy)
		_perks[key] = {"buy": buy, "info": info}

	_build_agi()
	_build_rivals()
	_build_challenges()

	var eb := PanelKit.section(page, "Endings", "agi")
	for d in Content.get_all("endings"):
		var l := PanelKit.label("", PanelKit.MUTED)
		eb.add_child(l)
		_endings.append(l)
	_new_run = action_button("Start a new legacy", false,
		func() -> Dictionary: return Game.new_run(), "New run started. Legacy kept.")
	eb.add_child(_new_run)


func _build_agi() -> void:
	var ab := PanelKit.section(page, "AGI road", "agi")
	ab.add_child(PanelKit.label(
		"Each AGI stage needs a safety decision. Clear it with one method. Most choices across the five stages set the ending; a tie goes to the latest method.",
		PanelKit.MUTED))
	_counters = PanelKit.label("", PanelKit.TEXT)
	ab.add_child(_counters)
	_trajectory = PanelKit.label("", PanelKit.BRIGHT)
	ab.add_child(_trajectory)

	var dc := PanelKit.card()
	ab.add_child(dc)
	var dv := _column(dc)
	_decision = PanelKit.label("", PanelKit.TEXT)
	dv.add_child(_decision)
	_eval_bar = PanelKit.bar(PanelKit.CYAN)
	dv.add_child(_eval_bar)
	_eval_status = PanelKit.label("", PanelKit.MUTED)
	dv.add_child(_eval_status)
	for m in METHODS:
		var info := PanelKit.label("", PanelKit.MUTED)
		dv.add_child(info)
		var buy := action_button(Endgame.TITLES[m], false,
			func() -> Dictionary: return Game.agi_choose(m), "Stage cleared: %s." % Endgame.TITLES[m])
		dv.add_child(buy)
		_choices[m] = {"buy": buy, "info": info}

	for d in Content.get_all("agi_stages"):
		_stage_defs.append(d)
		var c := PanelKit.card()
		Tip.attach(c, Callable(self, "_stage_tip").bind(d.id))
		ab.add_child(c)
		var v := _column(c)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
		var st := PanelKit.label("", PanelKit.TEXT)
		v.add_child(st)
		_stages.append(st)


func _build_rivals() -> void:
	var rb := PanelKit.section(page, "Rival race", "rivals")
	rb.add_child(PanelKit.label(
		"Each rival races toward its own launch from the AGI stage it targets. Outship delays it with compute; " +
		"acqui-hiring slows it. Clearing a stage before a rival is outpaced.", PanelKit.MUTED))
	for d in Content.get_all("rivals"):
		var c := PanelKit.card()
		Tip.attach(c, Callable(self, "_rival_tip").bind(d.id))
		rb.add_child(c)
		var v := _column(c)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		var bar := PanelKit.bar(PanelKit.GOLD)
		bar.max_value = 1.0
		v.add_child(bar)
		var status := PanelKit.label("", PanelKit.TEXT)
		v.add_child(status)
		var id: String = d.id
		var outship := _race_action(v, "Outship", Callable(self, "_outship_pressed").bind(id))
		var acqui := _race_action(v, "Acqui-hire", Callable(self, "_acqui_pressed").bind(id))
		_rivals[id] = {"bar": bar, "status": status, "outship": outship, "acqui": acqui, "def": d}


func _build_challenges() -> void:
	var cb := PanelKit.section(page, "Regulation challenges", "regulation")
	cb.add_child(PanelKit.label(
		"One challenge at a time. Each has a goal checked when its time runs out: a reward if met, a penalty if not. " +
		"A completed challenge can't be entered again. Abandoning gives neither. Tier II needs tier I passed; tier III needs tier II.",
		PanelKit.MUTED))
	var running := PanelKit.card()
	cb.add_child(running)
	var rv := _column(running)
	_ch_status = PanelKit.label("", PanelKit.TEXT)
	rv.add_child(_ch_status)
	_ch_bar = PanelKit.bar(PanelKit.TEAL)
	rv.add_child(_ch_bar)
	_ch_abandon = action_button("Abandon challenge", false,
		func() -> Dictionary: return Game.abandon_challenge(), "Challenge abandoned. No reward, no penalty.")
	rv.add_child(_ch_abandon)
	for t in TIER_NUMERALS.size():
		cb.add_child(PanelKit.label("Tier %s" % TIER_NUMERALS[t], PanelKit.BRIGHT))
		for d in Content.get_all("challenges"):
			if int(d.tier) != t + 1:
				continue
			var id: String = d.id
			var c := PanelKit.card()
			Tip.attach(c, Callable(self, "_challenge_tip").bind(id))
			cb.add_child(c)
			var v := _column(c)
			v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
			v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
			var info := PanelKit.label("", PanelKit.MUTED)
			v.add_child(info)
			var buy := action_button("", false,
				func() -> Dictionary: return Game.start_challenge(id), "Entered: %s." % d.title)
			v.add_child(buy)
			_challenges[id] = {"buy": buy, "info": info, "def": d}


## A vertical stack inside a card, with the panel's usual spacing.
func _column(c: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	c.add_child(v)
	return v


## One race action: an info line and its button. Returns {buy, info}.
func _race_action(parent: VBoxContainer, title: String, action: Callable) -> Dictionary:
	var info := PanelKit.label("", PanelKit.MUTED)
	parent.add_child(info)
	var buy := action_button(title, false, action, "%s done." % title)
	parent.add_child(buy)
	return {"buy": buy, "info": info}


func _outship_pressed(id: String) -> Dictionary:
	return Game.outship(id)


func _acqui_pressed(id: String) -> Dictionary:
	return Game.acqui_hire(id)


## Legacy perk: what it multiplies, how often it has been bought, and what the next one costs.
func _perk_tip(key: String) -> String:
	var s: GameState = Game.state
	var n := int(s.persist["legacy_perks"].get(key, 0))
	var lines: Array[String] = [
		"Legacy perk: %s" % LEGACY_KEYS[key],
		"Multiplies %s x%s forever. Bought %d, now x%.2f." % [
			key, PanelText.num(Sim.LEGACY_MULT), n, float(s.persist["perm_mult"].get(key, 1.0))],
		"Each purchase of the same perk costs double. Next: %s legacy." % Sim.legacy_cost(s, key).format(),
	]
	var reason := Sim.legacy_blocker(s, key)
	if reason != "":
		lines.append(reason)
	return "\n".join(lines)


func _challenge_tip(id: String) -> String:
	var d = _challenges[id]["def"]
	var lines: Array[String] = [
		d.title,
		d.description,
		"Goal: %s" % PanelText.conditions(d.goal),
		"Reward: %s" % PanelText.effects(d.reward),
		"Penalty: %s" % PanelText.effects(d.penalty),
		"Time: %s" % PanelKit.hms(float(d.duration)),
	]
	return "\n".join(lines)


func _rival_tip(id: String) -> String:
	var d = _rivals[id]["def"]
	return "%s\n%s\n%s" % [d.title, d.description, (_rivals[id]["status"] as Label).text]


func _stage_tip(id: String) -> String:
	for i in _stage_defs.size():
		if _stage_defs[i].id == id:
			return "%s\n%s\n%s" % [_stage_defs[i].title, _stage_defs[i].description, _stages[i].text]
	return ""


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(4)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if Sim.reset_preview(s, 4)["highlight"]:
		return true
	if Endgame.pending_index(s) >= 0 and String(s.run["run_over"]) == "":
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
		o.info.text = "Bought %d, now x%.2f%s" % [n, float(s.persist["perm_mult"].get(key, 1.0)),
			"" if reason == "" else "\n" + reason]
		o.buy.text = "Buy for %s legacy" % Sim.legacy_cost(s, key).format()
		o.buy.disabled = reason != ""

	_refresh_agi(s)
	_refresh_rivals(s)
	_refresh_challenges(s)

	var over := String(s.run["run_over"])
	_new_run.disabled = over == ""
	for i in _endings.size():
		var d = Content.get_all("endings")[i]
		var line := "%s: reached when most choices are %s." % [d.title, Endgame.TITLES.get(String(d.method), "")]
		if over == String(d.id):
			line += "  (this run)"
		_endings[i].text = line


func _refresh_agi(s: GameState) -> void:
	var choices: Array = s.run["agi_choices"]
	var c: Dictionary = Endgame.counts(choices)
	_counters.text = "Assurance %d  |  Openness %d  |  Recklessness %d" % [c["full"], c["redteam"], c["ship"]]
	var traj := Endgame.trajectory(s)
	_trajectory.text = "Current trajectory: %s" % (traj if traj != "" else "undecided")

	var over := String(s.run["run_over"])
	var idx := Endgame.pending_index(s)
	if over != "":
		_decision.text = "The run is over. Its ending is shown on the endings list."
	elif idx >= 0:
		_decision.text = "Stage %d waits: %s. Choose how to clear it." % [idx + 1, _stage_defs[idx].title]
	else:
		_decision.text = "No stage is waiting. The next one unlocks when its conditions are met."

	var ev: Dictionary = s.run["eval"]
	if not ev.is_empty():
		var total := Endgame.seconds(String(ev["method"]))
		_eval_bar.max_value = total
		_eval_bar.value = total - float(ev["left"])
		_eval_status.text = "%s running: %s left." % [Endgame.TITLES[ev["method"]], PanelKit.hms(float(ev["left"]))]
	elif float(s.run["eval_cooldown"]) > 0.0:
		_eval_bar.max_value = 1.0
		_eval_bar.value = 0.0
		_eval_status.text = "Full eval suite cooling down: %s." % PanelKit.hms(float(s.run["eval_cooldown"]))
	else:
		_eval_bar.max_value = 1.0
		_eval_bar.value = 0.0
		_eval_status.text = "No evaluation running."

	for m in METHODS:
		var o: Dictionary = _choices[m]
		var reason := Endgame.choice_blocker(s, m)
		o.info.text = _choice_text(s, m) + ("" if reason == "" else "\n" + reason)
		o.buy.disabled = reason != ""

	var stage := int(s.run["stage"])
	for i in _stage_defs.size():
		var d = _stage_defs[i]
		var head: String
		if i < choices.size():
			head = "Cleared: %s." % Endgame.TITLES[choices[i]]
		elif i < stage:
			head = "Waiting for a choice."
		elif i == stage:
			head = "Next."
		else:
			head = "Locked."
		var lines: Array[String] = []
		for cond in d.conditions:
			if cond["type"] == "compute_rate_gte":
				lines.append(("[x] " if Rules.check(s, cond) else "[ ] ") + "Sustain %s FLOP/s (now %s/s)" % [
					BigNum.from_float(float(cond["value"])).format(), Sim.compute_per_second(s).format()])
				continue
			var cn := PanelText.condition_now(s, cond)
			lines.append(("[x] " if cn["met"] else "[ ] ") + cn["text"])
		_stages[i].text = head + "\n" + "\n".join(lines)


## One line on what a method does, with the live pass chance.
func _choice_text(s: GameState, m: String) -> String:
	match m:
		"full":
			return "Pass %s. 4 h. Fail: 1 h cooldown. +1 Assurance." % PanelKit.pct(Endgame.pass_chance(s, "full"))
		"redteam":
			return "Pass %s. 2 h. +1 Openness. Rivals +5%% speed for good." % PanelKit.pct(Endgame.RED_PASS)
	return "Instant. +1 Recklessness: more and worse bad events this run."


func _refresh_rivals(s: GameState) -> void:
	var race: Dictionary = s.run["race"]
	for id in _rivals:
		var o: Dictionary = _rivals[id]
		var d = o["def"]
		var outpaced := bool(s.run["flags"].get("outpaced_%s" % id, false))
		var launched := bool(s.run["flags"].get("rival_%s_launched" % id, false))
		var acquired: bool = id in race["acqui"]
		var status: String
		if outpaced:
			status = "Outpaced: you cleared AGI stage %d first." % int(d.outpace_stage)
		elif launched:
			status = "Launched."
		elif Endgame.racing(s, d):
			status = "Launches in %s." % PanelKit.hms(Endgame.race_eta(s, id))
		else:
			status = "Starts when AGI stage %d unlocks." % int(d.outpace_stage)
		if acquired:
			status += " Researcher acquired."
		o.status.text = status
		o.bar.value = Endgame.race_progress(s, id)

		var race_ok := Endgame.race_blocker(s, id) == ""
		var n := int(race["outships"].get(id, 0))
		var cost := BigNum.from_float(Endgame.OUTSHIP_COST * pow(Endgame.OUTSHIP_COST_GROWTH, n))
		var cool_out := float(race["cool"].get("outship:" + id, 0.0))
		var out_text := "Compute %s. Delay +%s now (max +100%%)." % [cost.format(), PanelKit.pct(float(race["delay"].get(id, 0.0)))]
		if cool_out > 0.0:
			out_text += "\nCooling down: %s." % PanelKit.hms(cool_out)
		o.outship.info.text = out_text
		o.outship.buy.disabled = not race_ok or cool_out > 0.0 or s.cur("compute").compare(cost) < 0

		var gain: String = Sim.cash_per_second(s).mul_f(Endgame.ACQUI_CASH_SECONDS).format()
		var acqui_text := "Cash %s (2 h of income). +1 researcher. Rival x0.75 speed. Once per rival." % gain
		if acquired:
			acqui_text = "Acquired. Rival at x0.75 speed."
		elif float(race["cool"].get("acqui", 0.0)) > 0.0:
			acqui_text += "\nCooling down: %s." % PanelKit.hms(float(race["cool"]["acqui"]))
		o.acqui.info.text = acqui_text
		o.acqui.buy.disabled = not race_ok or acquired or float(race["cool"].get("acqui", 0.0)) > 0.0


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
		_ch_status.text = "Running: %s | %s left" % [d.title, PanelKit.hms(float(c["left"]))]
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
		o.buy.disabled = done or reason != ""
