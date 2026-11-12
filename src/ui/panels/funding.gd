extends PanelBase
## Funding Round (layer 1): the reset that pays out equity, and staff hiring, which is paid in equity.

var _card: PanelResetCard
var _equity: Label
var _hint: Label
var _staff: Dictionary = {}   # role -> {h1: Button, h5: Button, info: Label, def}


func _build() -> void:
	_card = PanelResetCard.new().setup(1, Callable(self, "report"))
	page.add_child(_card)
	var box := PanelKit.section(page, "Staff", "hiring")
	_equity = PanelKit.label("", PanelKit.TEXT)
	box.add_child(_equity)
	_hint = PanelKit.label("", PanelKit.MUTED)
	box.add_child(_hint)
	for d in Content.get_all("staff"):
		var role: String = d.id
		var c := PanelKit.card()
		box.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		c.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(PanelKit.icon(role, 2.0, PanelKit.WORKER))
		head.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
		v.add_child(head)
		var info := PanelKit.label("", PanelKit.MUTED)
		v.add_child(info)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var h1 := action_button("", false, func() -> Dictionary: return Game.hire(role, 1), "Hired 1 %s." % d.title)
		row.add_child(h1)
		var h5 := action_button("", false, func() -> Dictionary: return Game.hire(role, 5), "Hired 5 %s." % d.title)
		row.add_child(h5)
		_staff[role] = {"h1": h1, "h5": h5, "info": info, "def": d}


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(1)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if Sim.reset_preview(s, 1)["highlight"]:
		return true
	for role in _staff:
		if Sim.hire_blocker(s, role, 1) == "":
			return true
	return false


func _refresh() -> void:
	_card.refresh()
	var s: GameState = Game.state
	_equity.text = "Equity: %s" % s.cur("equity").format()
	_hint.text = "" if s.resets(1) > 0 else "Hiring unlocks after your first Funding Round."
	for role in _staff:
		var o: Dictionary = _staff[role]
		var d = o["def"]
		var hired := int(s.run["layers"][1]["staff"].get(role, 0))
		var text := "+%s %s per hire · %d hired" % [PanelKit.pct(float(d.bonus_per_hire)), d.bonus_key, hired]
		text += "\nCost: %s equity for 1, %s for 5." % [Sim.staff_cost(s, role, 1).format(), Sim.staff_cost(s, role, 5).format()]
		var why1 := Sim.hire_blocker(s, role, 1)
		var why5 := Sim.hire_blocker(s, role, 5)
		if why1 != "" and s.resets(1) > 0:
			text += "\n" + why1
		o.info.text = text
		o.h1.text = "Hire 1"
		o.h1.disabled = why1 != ""
		o.h5.text = "Hire 5"
		o.h5.disabled = why5 != ""
