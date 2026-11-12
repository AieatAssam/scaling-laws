extends PanelBase
## Paradigm Shift (layer 3): the reset that pays out breakthroughs, plus automation bought with breakthroughs.
## Energy and data start here; training spends them (see the Training panel).

var _card: PanelResetCard
var _stock: Label
var _rates: Label
var _autos: Dictionary = {}   # id -> {buy: Button, status: Label, cost: float}


func _build() -> void:
	_card = PanelResetCard.new().setup(3, Callable(self, "report"))
	page.add_child(_card)

	var box := PanelKit.section(page, "Energy and data", "energy")
	_stock = PanelKit.label("", PanelKit.TEXT)
	box.add_child(_stock)
	_rates = PanelKit.label("", PanelKit.MUTED)
	box.add_child(_rates)

	var ab := PanelKit.section(page, "Automation", "automation")
	ab.add_child(PanelKit.label(
		"Automation only buys things for you. Each one is bought once and then runs on every tick.", PanelKit.MUTED))
	for d in Content.get_all("automation"):
		var id: String = d.id
		var c := PanelKit.card()
		ab.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(PanelKit.label(d.description, PanelKit.MUTED))
		var status := PanelKit.label("", PanelKit.MUTED)
		v.add_child(status)
		var buy := action_button("", false,
			func() -> Dictionary: return Game.buy_automation(id), "Automation bought: %s." % d.title)
		v.add_child(buy)
		_autos[id] = {"buy": buy, "status": status, "cost": float(d.cost)}


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(3)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if Sim.reset_preview(s, 3)["highlight"]:
		return true
	for id in _autos:
		if Sim.automation_blocker(s, id) == "":
			return true
	return false


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
