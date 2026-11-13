extends PanelBase
## Model Generation (layer 2): the reset that pays out insights, the alignment slider (unlocked by this reset), and research.

const PRESETS := [0.0, 0.3, 0.7, 1.0]

var _desk: VBoxContainer
var _desk_timer: Label
var _desk_cards: VBoxContainer
var _desk_signature := ""
var _card: PanelResetCard
var _slider_info: Label
var _slider: HSlider
var _presets: Array[Button] = []
var _insights: Label
var _tree: PanelResearchTree


func _build() -> void:
	_desk = PanelKit.section(page, "Research desk", "research")
	_desk_timer = PanelKit.label("")
	_desk.add_child(_desk_timer)
	_desk_cards = VBoxContainer.new()
	_desk_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desk.add_child(_desk_cards)
	_card = PanelResetCard.new().setup(2, Callable(self, "report"))
	page.add_child(_card)

	var a := PanelKit.section(page, "Alignment", "alignment")
	_slider_info = PanelKit.label("", PanelKit.TEXT)
	a.add_child(_slider_info)
	Tip.attach(_slider_info, Callable(self, "_slider_tip"))
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(0, PanelKit.TOUCH_H)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slider)
	a.add_child(_slider)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	a.add_child(row)
	for p in PRESETS:
		var b := action_button(PanelKit.pct(p), false,
			func() -> Dictionary: return Game.set_slider(p), "Alignment set to %s." % PanelKit.pct(p))
		row.add_child(b)
		_presets.append(b)

	var rb := PanelKit.section(page, "Research", "research")
	_insights = PanelKit.label("", PanelKit.TEXT)
	rb.add_child(_insights)
	_tree = PanelResearchTree.new()
	rb.add_child(_tree)
	_tree.build(Callable(self, "report"))


func is_unlocked() -> bool:
	return PanelResetCard.is_layer_unlocked(2)


func wants_attention() -> bool:
	var s: GameState = Game.state
	if not Desk.state(s)["slots"].is_empty():
		return true
	if Sim.reset_preview(s, 2)["highlight"]:
		return true
	for d in Content.get_all("research"):
		if Sim.research_blocker(s, d.id) == "":
			return true
	return false


## Alignment: what the slider trades. Attached to the label, because pressing the slider track changes its value.
func _slider_tip() -> String:
	var s: GameState = Game.state
	var sl := float(s.run["slider"])
	if s.resets(2) == 0:
		return "Alignment\nUnlocks after your first Model Generation.\nLow alignment buys raw capability (more compute) and adds debt."
	var lines: Array[String] = [
		"Alignment %s" % PanelKit.pct(sl),
		"Compute ×%.2f from capability: lower alignment, higher multiplier." % Rules.capability(s),
		"Debt ×%.2f on compute (debt %.1f): compute is divided by this." % [Rules.debt_factor(s), float(s.run["layers"][0]["debt"])],
		"Below %s alignment, debt grows every tick. Above it, debt stops growing." % PanelKit.pct(Sim.SLIDER_SAFE),
	]
	return "\n".join(lines)


func _on_slider(v: float) -> void:
	report(Game.set_slider(v), "Alignment set to %s." % PanelKit.pct(v))


func _refresh() -> void:
	_card.refresh()
	_refresh_desk()
	var s: GameState = Game.state
	var unlocked := s.resets(2) > 0
	var sl := float(s.run["slider"])
	_slider.editable = unlocked
	_slider.set_value_no_signal(sl)
	for b in _presets:
		b.disabled = not unlocked
	if unlocked:
		_slider_info.text = ("Alignment %s. Compute ×%.2f from capability, ×%.2f from debt (debt %.1f). " +
			"Below %s alignment, debt grows.") % [
			PanelKit.pct(sl), Rules.capability(s), Rules.debt_factor(s),
			float(s.run["layers"][0]["debt"]), PanelKit.pct(Sim.SLIDER_SAFE)]
	else:
		_slider_info.text = "Alignment unlocks after your first Model Generation. Low alignment buys raw capability and adds debt."
	_insights.text = "Insights: %s" % s.cur("insights").format()
	_tree.refresh()


func _refresh_desk() -> void:
	var s: GameState = Game.state
	var desk := Desk.state(s)
	if not Desk.unlocked(s):
		_desk_timer.text = "Unlocks after your first Model Generation."
	else:
		_desk_timer.text = "Desk full" if desk["slots"].size() >= Desk.cap(s) else "Next paper: %s" % PanelKit.hms(float(desk["timer"]))
	var signature := str(desk["slots"])
	if signature == _desk_signature:
		return
	_desk_signature = signature
	for node in _desk_cards.get_children():
		node.queue_free()
	for slot in desk["slots"].size():
		var card: Dictionary = desk["slots"][slot]
		var d = Content.get_def("papers", card["id"])
		if d == null:
			continue
		var panel := PanelKit.card()
		if card["landmark"]:
			var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
			style.border_color = PanelKit.col(PanelKit.GOLD)
			panel.add_theme_stylebox_override("panel", style)
		_desk_cards.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(PanelKit.label(("[Landmark] " if card["landmark"] else "") + d.title, PanelKit.BRIGHT))
		box.add_child(PanelKit.label(d.blurb, PanelKit.TEXT))
		for i in d.choices.size():
			var choice: Dictionary = d.choices[i]
			var button := PanelKit.button(choice["label"], func():
				report(Game.resolve_paper(slot, i), "Paper reviewed.")
				_refresh_desk())
			box.add_child(button)
			Tip.attach(button, _paper_tip(choice, bool(card["landmark"])))


func _paper_tip(choice: Dictionary, landmark: bool) -> String:
	var lines: Array[String] = [String(choice["label"])]
	var scale := 2.0 if landmark else 1.0
	for e in choice["effects"]:
		match e["type"]:
			"cash_seconds": lines.append("Cash: %.0f seconds of current income." % (float(e["value"]) * scale))
			"generation_mult": lines.append("Compute: +%.0f%% for this generation (cap +50%%)." % (float(e["value"]) * scale * 100.0))
			"timed_mod": lines.append("%s x%.2f for %.0f minutes." % [String(e["key"]).capitalize(), 1.0 + (float(e["value"]) - 1.0) * scale, float(e["seconds"]) / 60.0])
			"rival_progress": lines.append("Rival %s progress: %.1f%%." % [e["id"], float(e["value"]) * scale * 100.0])
	return "\n".join(lines)
