extends PanelBase
## Paradigm Shift (layer 3): the reset that pays out breakthroughs, plus automation bought with breakthroughs.
## Energy and data start here; training spends them (see the Training panel).

var _card: PanelResetCard
var _stock: Label
var _rates: Label
var _autos: Dictionary = {}   # id -> {buy: Button, status: Label, cost: float}
var _slots: Array = []        # running project slots: {label: Label, bar: ProgressBar}
var _moons: Dictionary = {}   # moonshot id -> {card: Control, meta: Label, btn: Button}
var _done: Label


func _build() -> void:
	_card = PanelResetCard.new().setup(3, Callable(self, "report"))
	page.add_child(_card)

	var box := PanelKit.section(page, "Energy and data", "energy")
	_stock = PanelKit.label("", PanelKit.TEXT)
	box.add_child(_stock)
	Tip.attach(_stock, Callable(self, "_meter_tip"))
	_rates = PanelKit.caption()
	box.add_child(_rates)

	var ab := PanelKit.section(page, "Automation", "automation")
	ab.add_child(PanelKit.caption(
		"Automation only buys things for you. Each one is bought once and then runs on every tick."))
	for d in Content.get_all("automation"):
		var id: String = d.id
		var c := PanelKit.card()
		ab.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.caption(d.description))
		var status := PanelKit.caption()
		v.add_child(status)
		var buy := action_button("", false,
			func() -> Dictionary: return Game.buy_automation(id), "Automation bought: %s." % d.title)
		v.add_child(buy)
		buy.theme_type_variation = &"MicroButton"
		_autos[id] = {"buy": buy, "status": status, "cost": float(d.cost)}
		Tip.attach(c, Callable(self, "_auto_tip").bind(id))

	var mb := PanelKit.section(page, "Moonshots", "breakthroughs")
	mb.add_child(PanelKit.caption("Long projects, one at a time. A project runs in real time, even offline, and its reward lasts through every reset."))
	for i in 2:
		var sl := PanelKit.label("", PanelKit.TEXT)
		var sb := PanelKit.bar(PanelKit.TEAL)
		mb.add_child(sl)
		mb.add_child(sb)
		_slots.append({"label": sl, "bar": sb})
	_done = PanelKit.caption()
	mb.add_child(_done)
	Tip.attach(_done, Callable(self, "_done_tip"))
	for d in Content.get_all("moonshots"):
		var id: String = d.id
		var c := PanelKit.card()
		mb.add_child(c)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		c.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		var meta := PanelKit.caption()
		text.add_child(meta)
		var btn := action_button("Start", false,
			func() -> Dictionary: return Game.start_moonshot(id), "Moonshot started: %s." % d.title)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn.custom_minimum_size.x = 56.0
		btn.theme_type_variation = &"MicroButton"
		row.add_child(btn)
		_moons[id] = {"card": c, "meta": meta, "btn": btn}
		Tip.attach(c, Callable(self, "_moon_tip").bind(id))


## Energy and data: what training spends and how fast each refills. Energy and data are what training runs need.
func _meter_tip() -> String:
	var s: GameState = Game.state
	var lines: Array[String] = [
		"Energy and data\nAfter a Paradigm Shift, each training run needs %d energy and %d data." % [
			int(Sim.TRAIN_ENERGY), int(Sim.TRAIN_DATA)],
		"Energy: %s / %d, +%d/s." % [s.cur("energy").format(), int(Sim.ENERGY_CAP), int(Sim.ENERGY_RATE)],
		"Data: %s, +%s/s." % [s.cur("data").format(), PanelText.num(Sim.DATA_RATE)],
	]
	if s.resets(3) == 0:
		lines[1] = "Energy and data start after your first Paradigm Shift."
	return "\n".join(lines)


## Automation: what it does and whether it can be bought now.
func _auto_tip(id: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("automation", id)
	var lines: Array[String] = [d.title, d.description, "Cost %s breakthroughs. Bought once, then runs every tick." % PanelText.num(d.cost)]
	if id in s.persist["automation"]:
		lines.append("Owned.")
	else:
		var reason := Sim.automation_blocker(s, id)
		if reason.begins_with("requires "):
			reason = "Needs " + PanelText.title_of("automation", reason.substr(9))
		lines.append(reason if reason != "" else "Available now.")
	return "\n".join(lines)


## Moonshots: what a project does and whether it can start now.
func _moon_tip(id: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("moonshots", id)
	var lines: Array[String] = [d.title, d.description,
		"Runs %sh of game time. Costs %s BT." % [PanelText.num(d.hours), PanelText.num(d.breakthroughs)]]
	if d.prereqs.size() > 0:
		var names: Array[String] = []
		for p in d.prereqs:
			names.append(PanelText.title_of("moonshots", p))
		lines.append("Needs: " + ", ".join(names))
	var reason := Moonshots.blocker(s, id)
	lines.append(reason if reason != "" else "Available now.")
	return "\n".join(lines)


## Completed moonshots, listed.
func _done_tip() -> String:
	var lines: Array[String] = ["Completed moonshots"]
	for id in Game.state.persist["moonshots"]["done"]:
		lines.append(PanelText.title_of("moonshots", id))
	if lines.size() == 1:
		lines.append("None yet.")
	return "\n".join(lines)


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(3)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if Sim.reset_preview(s, 3)["highlight"]:
		return true
	for id in _autos:
		if Sim.automation_blocker(s, id) == "":
			return true
	for id in _moons:
		if Moonshots.blocker(s, id) == "":
			return true
	return false


func _refresh_moonshots(s: GameState) -> void:
	var cap := Moonshots.slots(s)
	var run: Array = Moonshots.running(s)
	for i in _slots.size():
		var sl: Dictionary = _slots[i]
		if i >= cap:
			sl.label.text = "Second slot: Second Bay (locked)" if i == 1 else ""
			sl.bar.visible = false
			continue
		sl.bar.visible = i < run.size()
		if i < run.size():
			var d = s.db.get_def("moonshots", run[i]["id"])
			var total: float = d.hours * 3600.0
			sl.bar.max_value = total
			sl.bar.value = total - float(run[i]["left"])
			sl.label.text = "%s: %s left" % [d.title, PanelKit.hms(float(run[i]["left"]))]
		else:
			sl.label.text = "Project slot free"
	var n_done: int = s.persist["moonshots"]["done"].size()
	_done.text = "Completed: %d of %d" % [n_done, Moonshots.all(s).size()]
	for id in _moons:
		var o: Dictionary = _moons[id]
		var d = s.db.get_def("moonshots", id)
		var shown := not Moonshots.done(s, id) and not Moonshots.is_running(s, id) and Rules.check_all(s, d.conditions)
		o.card.visible = shown
		if not shown:
			continue
		var reason := Moonshots.blocker(s, id)
		o.meta.text = "%sh, %s BT%s" % [PanelText.num(d.hours), PanelText.num(d.breakthroughs),
			"" if reason == "" else " | " + reason]
		o.btn.disabled = reason != ""


func _refresh() -> void:
	_card.refresh()
	var s: GameState = Game.state
	_stock.text = "Breakthroughs: %s · Data: %s · Energy: %s / %d" % [
		s.cur("breakthroughs").format(), s.cur("data").format(), s.cur("energy").format(), int(Sim.ENERGY_CAP)]
	if s.resets(3) == 0:
		_rates.text = "Energy and data start after your first Paradigm Shift."
	else:
		_rates.text = "Data +%s/s · Energy +%d/s, capped at %d." % [
			PanelText.num(Sim.DATA_RATE), int(Sim.ENERGY_RATE), int(Sim.ENERGY_CAP)]
	var owned: Array = s.persist["automation"]
	for id in _autos:
		var o: Dictionary = _autos[id]
		var done: bool = id in owned
		var reason := Sim.automation_blocker(s, id)
		if reason.begins_with("requires "):
			reason = "Needs " + PanelText.title_of("automation", reason.substr(9))
		o.status.text = "Owned." if done else reason
		o.buy.text = "Owned" if done else "Buy for %s breakthroughs" % PanelText.num(o.cost)
		o.buy.disabled = done or reason != ""
	_refresh_moonshots(s)
