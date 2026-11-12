extends PanelBase
## Funding Round (layer 1): the reset that pays out equity, and staff hiring, which is paid in equity.
## One x1 / x5 / MAX row (AmountPicker, as on the producers panel) sets how many each role's Hire button hires.

const AMOUNTS := [1, 5, -1]   # -1 = max affordable

var _card: PanelResetCard
var _equity: Label
var _hint: Label
var _picker: AmountPicker
var _staff: Dictionary = {}   # role -> {hire: Button, info: Label, def}


func _build() -> void:
	_card = PanelResetCard.new().setup(1, Callable(self, "report"))
	page.add_child(_card)
	var box := PanelKit.section(page, "Staff", "hiring")
	_equity = PanelKit.label("", PanelKit.TEXT)
	box.add_child(_equity)
	_hint = PanelKit.label("", PanelKit.MUTED)
	box.add_child(_hint)
	_picker = AmountPicker.new().setup("Hire", AMOUNTS, "Hire")
	_picker.changed.connect(func(_a: int) -> void: _refresh())
	box.add_child(_picker)
	for d in Content.get_all("staff"):
		var role: String = d.id
		var c := PanelKit.card()
		Tip.attach(c, Callable(self, "_staff_tip").bind(role))
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
		var hire := PanelKit.button("", Callable(), false)
		hire.custom_minimum_size = Vector2(120, PanelKit.TOUCH_H)
		hire.size_flags_horizontal = Control.SIZE_SHRINK_END
		hire.pressed.connect(_hire.bind(role, hire))
		row.add_child(hire)
		_staff[role] = {"hire": hire, "info": info, "def": d}


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


## B hotkey and the shared row: the number of hires a role's button makes right now (MAX → most affordable, may be 0).
func _count_for(role: String) -> int:
	return Hiring.max_count(Game.state, role) if _picker.amount < 0 else _picker.amount


## Hires `role` with the picker's amount and reports the result.
func _hire(role: String, btn: Button) -> void:
	var n := _count_for(role)
	var r := Game.hire(role, n)
	report(r, "Hired %d %s." % [n, Content.get_def("staff", role).title])
	if r.get("ok", false):
		PanelKit.pop(btn)


## Staff role: what the hire does, what it costs, and what it adds right now.
func _staff_tip(role: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("staff", role)
	var hired := int(s.run["layers"][1]["staff"].get(role, 0))
	var lines: Array[String] = [
		d.title,
		d.description,
		"Each hire adds +%s %s. Now %d hired, ×%.2f in total." % [
			PanelKit.pct(float(d.bonus_per_hire)), d.bonus_key, hired, 1.0 + float(d.bonus_per_hire) * hired],
		"Cost: %s equity for 1, %s for 5." % [Sim.staff_cost(s, role, 1).format(), Sim.staff_cost(s, role, 5).format()],
	]
	var why := Sim.hire_blocker(s, role, 1)
	if why != "":
		lines.append(why)
	return "\n".join(lines)


func _refresh() -> void:
	_card.refresh()
	var s: GameState = Game.state
	_equity.text = "Equity: %s" % s.cur("equity").format()
	_hint.text = "" if s.resets(1) > 0 else "Hiring unlocks after your first Funding Round."
	for role in _staff:
		var o: Dictionary = _staff[role]
		var d = o["def"]
		var hired := int(s.run["layers"][1]["staff"].get(role, 0))
		var n := _count_for(role)
		var shown := maxi(n, 1)
		var text := "+%s %s per hire · %d hired" % [PanelKit.pct(float(d.bonus_per_hire)), d.bonus_key, hired]
		text += "\nCost: %s equity for %d." % [Sim.staff_cost(s, role, shown).format(), shown]
		var why := Sim.hire_blocker(s, role, shown)
		if why != "" and s.resets(1) > 0:
			text += "\n" + why
		o.info.text = text
		var hire: Button = o["hire"]
		hire.text = "Hire max (%d)" % n if _picker.amount < 0 else "Hire x%d" % n
		hire.disabled = n < 1 or why != ""
