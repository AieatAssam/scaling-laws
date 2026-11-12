extends Control
## Shell: HUD, lab view, icon tab bar, panel area and overlays. Calls Game.start() once.
## Wider than tall: lab left, panels right. Taller than wide: lab top, panels below.

const PANEL_IDS := ["producers", "training", "funding", "generation", "paradigm", "singularity", "benchmarks", "settings"]
const PANEL_ICONS := {
	"producers": "compute", "training": "training", "funding": "hiring", "generation": "research",
	"paradigm": "automation", "singularity": "agi", "benchmarks": "benchmarks", "settings": "settings",
}
const TAB_LABELS := {
	"producers": "Compute", "training": "Train", "funding": "Funding", "generation": "Models",
	"paradigm": "Paradigm", "singularity": "AGI", "benchmarks": "Bench", "settings": "Settings",
}
const TAB_LABEL_MIN_WIDTH := 96.0   # tabs narrower than this (phones) show only the icon
## Currencies beyond compute/cash, shown in the HUD once their layer has been reset (or they are held).
const HUD_EXTRA := ["equity", "insights", "breakthroughs", "data", "energy", "legacy"]
const LAB_SCENE := "res://src/lab/lab_view.tscn"
## Ending screen: instanced per ending, frees itself when the player continues.
const ENDING_SCENE := "res://src/ui/ending_screen.tscn"

var _body: BoxContainer
var _lab_slot: PanelContainer
var _panel_area: PanelContainer
var _tab_bar: HBoxContainer
var _tab_group := ButtonGroup.new()
var _tabs := {}    # id -> Button
var _dots := {}    # id -> ColorRect (attention dot)
var _panels := {}  # id -> Control
var _current := ""
var _cash: Dictionary = {}     # chip: {value: TickLabel, rate: Label}
var _compute: Dictionary = {}
var _extras := {}              # currency -> {box: Control, value: TickLabel}
var _saved: Label
var _saved_t := 0.0
var _rate_tick := 0.0
var _ending_shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	_build_shell()
	_build_panels()
	# Overlays connect to Game signals in their _ready, so they must exist before Game.start().
	add_child(Notices.new())
	add_child(EventPopup.new())
	add_child(PrestigeOverlay.new())
	Game.saved.connect(_on_saved)
	Game.settings_changed.connect(_on_settings_changed)
	Game.ending_reached.connect(_on_ending)
	if not Game.running:
		Game.start()
	_apply_ui_scale(float(Game.state.persist["settings"].get("ui_scale", 1.0)))
	_refresh_tabs()
	_select(_first_unlocked())
	_on_resized()
	for c in get_children():
		if c is EventPopup:
			c.check_pending()
	# A run that finished before the game was closed is shown again until a new legacy starts.
	var over := String(Game.state.run["run_over"])
	if over != "":
		_on_ending(over)


func _build_shell() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	col.add_child(_build_hud())

	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	col.add_child(_body)
	_lab_slot = PanelContainer.new()
	_lab_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lab_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ResourceLoader.exists(LAB_SCENE):
		_lab_slot.add_child(load(LAB_SCENE).instantiate())
	else:
		var fill := ColorRect.new()
		fill.color = Fx.col(Fx.BG)
		_lab_slot.add_child(fill)
	_body.add_child(_lab_slot)
	_panel_area = PanelContainer.new()
	_panel_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_panel_area)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 2)
	_tab_bar.resized.connect(_layout_tabs)
	col.add_child(_tab_bar)


## Top bar: cash and compute are the hero numbers (value with its per-second rate under it);
## later currencies appear as they unlock. Chips wrap to a second row on narrow screens.
func _build_hud() -> PanelContainer:
	var hud := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hud.add_child(row)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 2)
	row.add_child(flow)
	_cash = _chip("cash", true)
	flow.add_child(_cash["box"])
	_compute = _chip("compute", true)
	flow.add_child(_compute["box"])
	for c in HUD_EXTRA:
		var ch := _chip(c, false)
		ch["box"].visible = false
		flow.add_child(ch["box"])
		_extras[c] = ch
	_saved = Label.new()
	_saved.theme_type_variation = &"MicroDim"
	_saved.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_saved)
	return hud


## One HUD chip: icon + value on top, per-second rate underneath (hero chips only).
func _chip(icon_name: String, with_rate: bool) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var ic := TextureRect.new()
	ic.texture = Fx.tex_x("res://assets/icons/%s.png" % icon_name, 2)
	ic.custom_minimum_size = Vector2(32, 32)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(ic)
	var value := TickLabel.new()
	value.theme_type_variation = &"Value"
	head.add_child(value)
	var rate: Label = null
	if with_rate:
		rate = Label.new()
		rate.theme_type_variation = &"MicroDim"
		box.add_child(rate)
	return {"box": box, "value": value, "rate": rate}


## Instances each panel that exists on disk and adds its tab. Missing panels get no tab.
func _build_panels() -> void:
	for id in PANEL_IDS:
		var path := "res://src/ui/panels/%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var p: Control = load(path).instantiate()
		p.visible = false
		_panel_area.add_child(p)
		_panels[id] = p
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = _tab_group
		b.icon = Fx.tex_x("res://assets/icons/%s.png" % PANEL_ICONS[id], 2)
		b.add_theme_font_size_override("font_size", 8)
		b.custom_minimum_size = Vector2(40, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.tooltip_text = TAB_LABELS.get(id, id)
		b.pressed.connect(_select.bind(id))
		_tab_bar.add_child(b)
		_tabs[id] = b
		var dot := ColorRect.new()
		dot.color = Fx.col(Fx.GOLD)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(8, 8)
		dot.anchor_left = 1.0
		dot.anchor_right = 1.0
		dot.offset_left = -12
		dot.offset_right = -4
		dot.offset_top = 4
		dot.offset_bottom = 12
		dot.visible = false
		b.add_child(dot)
		_dots[id] = dot


func _panel_flag(id: String, method: String) -> bool:
	var p: Control = _panels[id]
	return p.has_method(method) and bool(p.call(method))


func _refresh_tabs() -> void:
	for id in _tabs:
		var b: Button = _tabs[id]
		b.visible = _panel_flag(id, "is_unlocked") or not _panels[id].has_method("is_unlocked")
		Fx.set_attention(_dots[id], _panel_flag(id, "wants_attention") and id != _current)
	_layout_tabs()


## Tab labels show only where the tab is wide enough; the icon is always shown.
func _layout_tabs() -> void:
	for id in _tabs:
		var b: Button = _tabs[id]
		b.text = TAB_LABELS.get(id, "") if b.size.x >= TAB_LABEL_MIN_WIDTH else ""


func _first_unlocked() -> String:
	for id in PANEL_IDS:
		if _tabs.has(id) and (_tabs[id] as Button).visible:
			return id
	return ""


func _select(id: String) -> void:
	if id == "" or not _panels.has(id):
		return
	_current = id
	for k in _panels:
		_panels[k].visible = k == id
	(_tabs[id] as Button).button_pressed = true
	_refresh_tabs()


## Portrait below ~1:1 aspect; switches the body between row and column.
func _on_resized() -> void:
	var portrait := size.y > size.x
	_body.vertical = portrait
	_lab_slot.size_flags_stretch_ratio = 0.9 if portrait else 1.0
	_panel_area.size_flags_stretch_ratio = 1.1 if portrait else 1.0


func _process(delta: float) -> void:
	(_cash["value"] as TickLabel).set_target(Game.cash())
	(_compute["value"] as TickLabel).set_target(Game.compute())
	_rate_tick += delta
	if _rate_tick >= 0.25:
		_rate_tick = 0.0
		(_cash["rate"] as Label).text = "+%s/s" % Game.cash_per_second().format()
		(_compute["rate"] as Label).text = "+%s/s" % Game.compute_per_second().format()
		_refresh_extras()
		_refresh_tabs()
	if _saved_t > 0.0:
		_saved_t -= delta
		if _saved_t <= 0.0:
			_saved.text = ""


func _refresh_extras() -> void:
	var s: GameState = Game.state
	for c in _extras:
		var ch: Dictionary = _extras[c]
		var layer := int(GameState.CURRENCY_LAYER.get(c, 0))
		var held := s.cur(c)
		var shown := s.resets(layer) > 0 or not held.is_zero()
		(ch["box"] as Control).visible = shown
		if shown:
			(ch["value"] as TickLabel).set_target(held)


func _on_saved(ok: bool) -> void:
	_saved.text = "saved" if ok else "SAVE FAILED"
	_saved.add_theme_color_override("font_color", Fx.col(Fx.GREEN if ok else Fx.RED))
	_saved_t = 2.0


func _on_settings_changed(key: String, value) -> void:
	if key == "ui_scale":
		_apply_ui_scale(float(value))


func _apply_ui_scale(s: float) -> void:
	get_window().content_scale_factor = clampf(s, 1.0, 1.5)


func _on_ending(id: String) -> void:
	if _ending_shown or not ResourceLoader.exists(ENDING_SCENE):
		return
	_ending_shown = true
	var scene: Node = load(ENDING_SCENE).instantiate()
	add_child(scene)
	scene.tree_exited.connect(func() -> void: _ending_shown = false)
	scene.call("show_ending", id)
