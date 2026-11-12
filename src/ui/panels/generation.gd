extends PanelBase
## Model Generation (layer 2): the reset that pays out insights, the alignment slider (unlocked by this reset), and research.

const PRESETS := [0.0, 0.3, 0.7, 1.0]

var _card: PanelResetCard
var _slider_info: Label
var _slider: HSlider
var _presets: Array[Button] = []
var _insights: Label
var _tree: PanelResearchTree


func _build() -> void:
	_card = PanelResetCard.new().setup(2, Callable(self, "report"))
	page.add_child(_card)

	var a := PanelKit.section(page, "Alignment", "alignment")
	_slider_info = PanelKit.label("", PanelKit.TEXT)
	a.add_child(_slider_info)
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
	if Sim.reset_preview(s, 2)["highlight"]:
		return true
	for d in Content.get_all("research"):
		if Sim.research_blocker(s, d.id) == "":
			return true
	return false


func _on_slider(v: float) -> void:
	report(Game.set_slider(v), "Alignment set to %s." % PanelKit.pct(v))


func _refresh() -> void:
	_card.refresh()
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
