extends Control
## Shell: HUD, lab view, icon tab bar, panel area and overlays. Calls Game.start() once.
## Wider than tall: lab left, panels right. Taller than wide: lab top, panels below.

const PANEL_IDS := ["producers", "training", "funding", "generation", "paradigm", "singularity", "benchmarks", "settings", "help"]
const PANEL_ICONS := {
	"producers": "compute", "training": "training", "funding": "hiring", "generation": "research",
	"paradigm": "automation", "singularity": "agi", "benchmarks": "benchmarks", "settings": "settings",
	"help": "events",
}
const TAB_LABELS := {
	"producers": "Compute", "training": "Train", "funding": "Funding", "generation": "Models",
	"paradigm": "Paradigm", "singularity": "AGI", "benchmarks": "Bench", "settings": "Settings",
	"help": "Help",
}
const TAB_TIPS := {
	"producers": "Buy producers. Each one makes compute, the raw output everything else scales from.",
	"training": "Train models: Fine-tune for cash, Frontier for score, Standard for both. A success scores and pays a cash burst.",
	"funding": "Hire staff with equity. Each hire multiplies a bonus to cash or compute.",
	"generation": "Ship models: the alignment slider, Model Generation resets and the research tree.",
	"paradigm": "Breakthroughs, data and energy, and the automation that runs the rest.",
	"singularity": "Final reset for legacy, regulation challenges, rivals, the AGI road and endings.",
	"benchmarks": "Benchmarks unlock as you reach milestones and give permanent effects.",
	"settings": "Motion, UI scale, saves and resets.",
	"help": "How the game works: resets, training, events, offline progress and the icon legend.",
}
const TAB_LABEL_MIN_WIDTH := 96.0   # tabs narrower than this (phones) show only the icon
## Currencies beyond compute/cash, shown in the HUD once their layer has been reset (or they are held).
const HUD_EXTRA := ["equity", "insights", "breakthroughs", "data", "energy", "legacy"]
const LAB_SCENE := "res://src/lab/lab_view.tscn"
## Ending screen: instanced per ending, frees itself when the player continues.
const ENDING_SCENE := "res://src/ui/ending_screen.tscn"
## First-run story cutscene (also Settings > Replay intro). Pauses the simulation while it plays.
const INTRO_SCENE := "res://src/ui/intro.tscn"

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
var _hud_row: HBoxContainer
var _hud_flow: GridContainer
var _headline: BoxContainer
var _head_row: HBoxContainer       # phones: headline and Stats button side by side under the currency grid
var _headline_scale: TickLabel
var _headline_stage: Label
var _headline_icon: TextureRect
var _headline_line: Label
var _extras := {}              # currency -> {box: Control, value: TickLabel}
var _saved: Label
var _stats_btn: Button             # HUD "Stats / 12%" button: one tap opens the Statistics overlay
var _saved_t := 0.0
var _rate_tick := 0.0
var _ending_shown := false
var _intro: Control
var _intro_requested := false
## Modal dialogs (offline card, event, prestige transition, ending, intro) take turns: one open, the rest wait here.
var _modal_queue: Array[Callable] = []
var _modal_busy := false
var _column: VBoxContainer        # the whole shell; padded by the safe-area insets on phones
var _notices: Notices             # offline card and save notice (Back closes it)
var _ending: Node                 # the ending screen while it is up (Back closes it)
var _tip: Tip
var _reveal_card: RevealCard       # one-time "New: ..." cards (see Reveals)
var _stats: StatsPanel            # Settings > Statistics overlay, built on first open


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().gui_embed_subwindows = true
	add_to_group("shell")
	resized.connect(_on_resized)
	get_window().size_changed.connect(_fit_base)
	RenderingServer.set_default_clear_color(Fx.col(Fx.BG))  # the inset strips on phones show this, not Godot's grey
	_build_shell()
	_build_panels()
	_fit_base()  # after the panels exist: a base change resizes the root and fires _on_resized
	# Overlays connect to Game signals in their _ready, so they must exist before Game.start().
	# Modal ones share one queue (see _request_modal): each gets the gate and reports `closed` back to it.
	_notices = Notices.new()
	_reveal_card = RevealCard.new()
	for overlay in [_notices, EventPopup.new(), PrestigeOverlay.new(), _reveal_card]:
		overlay.gate = _request_modal
		overlay.closed.connect(_on_modal_closed)
		add_child(overlay)
	_tip = Tip.new()
	add_child(_tip)
	Game.saved.connect(_on_saved)
	Game.settings_changed.connect(_on_settings_changed)
	Game.ending_reached.connect(_on_ending)
	if not Game.running:
		Game.start()
	_apply_ui_scale(float(Game.state.persist["settings"].get("ui_scale", 1.0)))
	_refresh_tabs()
	_select(_first_unlocked())
	_on_resized()
	# Queue order matters: the intro goes first, so a saved event or ending waits behind it.
	if not bool(Game.state.persist.get("intro_seen", true)):
		play_intro()
	for c in get_children():
		if c is EventPopup:
			c.check_pending()
	# A run that finished before the game was closed is shown again until a new legacy starts.
	var over := String(Game.state.run["run_over"])
	if over != "":
		_on_ending(over)


func _build_shell() -> void:
	_column = VBoxContainer.new()
	var col := _column
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 2)
	add_child(col)
	col.add_child(_build_hud())
	col.add_child(GoalRail.new())

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
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	hud.add_child(stack)
	_hud_row = HBoxContainer.new()
	_hud_row.add_theme_constant_override("separation", 8)
	stack.add_child(_hud_row)
	var flow := GridContainer.new()
	_hud_flow = flow
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.columns = 4
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 0)
	_hud_row.add_child(flow)
	_cash = _chip("cash", true, true)
	(_cash["value"] as TickLabel).theme_type_variation = &"MicroValue"
	Tip.attach(_cash["box"], Callable(self, "_cash_tip"))
	flow.add_child(_cash["box"])
	_compute = _chip("compute", true, true)
	(_compute["value"] as TickLabel).theme_type_variation = &"MicroValue"
	Tip.attach(_compute["box"], Callable(self, "_compute_tip"))
	flow.add_child(_compute["box"])
	for c in HUD_EXTRA:
		var ch := _chip(c, false, true)
		ch["box"].visible = false
		Tip.attach(ch["box"], Callable(self, "_extra_tip").bind(c))
		flow.add_child(ch["box"])
		_extras[c] = ch
	_headline = BoxContainer.new()
	_headline.vertical = true
	_headline.add_theme_constant_override("separation", 0)
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scale_part := HBoxContainer.new()
	scale_part.add_theme_constant_override("separation", 4)
	var scale_icon := TextureRect.new()
	scale_icon.texture = Fx.tex_fit("res://assets/icons/compute.png", Vector2i(16, 16))
	scale_icon.custom_minimum_size = Vector2(16, 16)
	scale_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	scale_part.add_child(scale_icon)
	var scale_title := Label.new()
	scale_title.text = "Scale"
	scale_title.theme_type_variation = &"MicroLabel"
	scale_part.add_child(scale_title)
	_headline_scale = TickLabel.new()
	_headline_scale.theme_type_variation = &"Value"
	_headline_scale.suffix = "/s"
	scale_part.add_child(_headline_scale)
	Tip.attach(scale_part, "Lab scale\nCurrent compute rate (FLOP/s), after all multipliers.")
	_headline.add_child(scale_part)
	_headline_stage = Label.new()
	_headline_stage.theme_type_variation = &"MicroLabel"
	Tip.attach(_headline_stage, "Lab stage\nThe lab's current location, based on its highest producer tier.")
	var stage_part := HBoxContainer.new()
	stage_part.add_theme_constant_override("separation", 4)
	stage_part.add_child(_headline_stage)
	var metric := HBoxContainer.new()
	metric.add_theme_constant_override("separation", 3)
	_headline_icon = TextureRect.new()
	_headline_icon.custom_minimum_size = Vector2(16, 16)
	_headline_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	metric.add_child(_headline_icon)
	_headline_line = Label.new()
	_headline_line.theme_type_variation = &"MicroDim"
	metric.add_child(_headline_line)
	Tip.attach(metric, Callable(self, "_headline_tip"))
	stage_part.add_child(metric)
	_headline.add_child(stage_part)
	Tip.attach(_headline, "The current stage score or AGI road progress.")
	_head_row = HBoxContainer.new()
	_head_row.add_theme_constant_override("separation", 8)
	_head_row.visible = false
	stack.add_child(_head_row)
	_head_row.add_child(_headline)
	_stats_btn = Button.new()
	_stats_btn.theme_type_variation = &"MicroButton"
	_stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats_btn.pressed.connect(open_stats)
	Tip.attach(_stats_btn, "Statistics\nCompletion, this run, the reset layers and all time. Also in Settings.")
	_hud_row.add_child(_stats_btn)
	_saved = Label.new()
	_saved.theme_type_variation = &"MicroDim"
	_saved.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_hud_row.add_child(_saved)
	return hud


func _headline_tip() -> String:
	if int(Game.state.resets(4)) > 0:
		return "AGI road\nStage requirements progress and the current ending trajectory."
	return "Frontier reset\nCurrent layer currency and the gain available on reset. Highlighted when the gain is at least twice your holding."


func _refresh_headline() -> void:
	var h := Rules.headline(Game.state)
	_headline_scale.set_target(h["scale"])
	_headline_stage.text = str(h["stage_name"])
	_headline_icon.texture = Fx.tex_fit("res://assets/icons/%s.png" % h["currency"], Vector2i(16, 16))
	_headline_line.text = str(h["line"])
	_headline_line.add_theme_color_override("font_color", Fx.col(Fx.ACCENT if h["highlight"] else Fx.MUTED))


## One HUD chip: icon + value on top, per-second rate underneath (hero chips only).
## compact: 12 px icon and 8 px value for the currency grid.
func _chip(icon_name: String, with_rate: bool, compact := false) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # grid columns share the free width
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6 if not compact else 4)
	box.add_child(head)
	var px: int = 12 if compact else 32
	var ic := TextureRect.new()
	ic.texture = Fx.tex_fit("res://assets/icons/%s.png" % icon_name, Vector2i(px, px))
	ic.custom_minimum_size = Vector2(px, px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(ic)
	var value := TickLabel.new()
	value.theme_type_variation = &"MicroValue" if compact else &"Value"
	value.clip_text = true  # a chip may shrink below its text: the currency grid must fit 360 px
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(value)
	var rate: Label = null
	if with_rate:
		rate = Label.new()
		rate.theme_type_variation = &"MicroDim"
		rate.clip_text = true
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
		b.icon = Fx.tex_fit("res://assets/icons/%s.png" % PANEL_ICONS[id], Vector2i(16, 16))  # 16 px: nine tabs fit 360 px
		b.add_theme_font_size_override("font_size", 8)
		b.custom_minimum_size = Vector2(0, 34)  # width comes from the theme: nine icon tabs must fit 360 px
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		Tip.attach(b, Callable(self, "_tab_tip").bind(id))
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


## Tooltip text for a HUD currency or a tab. First line is the title; the rest is the body.
func _tab_tip(id: String) -> String:
	return "%s\n%s" % [TAB_LABELS.get(id, id), TAB_TIPS.get(id, "")]


func _cash_tip() -> String:
	var s: GameState = Game.state
	return "Cash\nEarned from compute: %s/s. Multiplier ×%.2f: %s.\nSpent on producers, staff and research." % [
		Game.cash_per_second().format(), Rules.mult(s, "cash"), _mult_text("cash")]


func _compute_tip() -> String:
	var s: GameState = Game.state
	return "Compute\nMade by producers: %s/s. Multiplier ×%.2f: %s.\nSpent on training runs." % [
		Game.compute_per_second().format(), Rules.mult(s, "compute"), _mult_text("compute")]


func _extra_tip(id: String) -> String:
	var s: GameState = Game.state
	var k: int = GameState.CURRENCY_LAYER.get(id, 0)
	var layer: Variant = Sim.layer_def(s, k)
	var lines: Array[String] = ["%s: %s held" % [PanelText.cur_name(id), s.cur(id).format()]]
	if layer != null:
		lines.append("Earned by a %s reset. %s" % [layer.title, layer.description])
		var rp := Sim.reset_preview(s, k)
		if rp["allowed"]:
			lines.append("Resetting now would add %s." % (rp["gain"] as BigNum).format())
		else:
			lines.append(str(rp["reason"]))
	return "\n".join(lines)


## Which factors make up a multiplier, leaving out the ones at ×1.
func _mult_text(key: String) -> String:
	var parts: Array[String] = []
	for p in Rules.mult_parts(Game.state, key):
		if absf(float(p["value"]) - 1.0) > 0.0001:
			parts.append("%s ×%.2f" % [p["name"], p["value"]])
	return "none yet" if parts.is_empty() else ", ".join(parts)


func _panel_flag(id: String, method: String) -> bool:
	var p: Control = _panels[id]
	return p.has_method(method) and bool(p.call(method))


func _refresh_tabs() -> void:
	for id in _tabs:
		var b: Button = _tabs[id]
		b.visible = _panel_flag(id, "is_unlocked") or not _panels[id].has_method("is_unlocked")
		Fx.set_attention(_dots[id], _panel_flag(id, "wants_attention") and id != _current)
	_layout_tabs()


## Tab labels show only where the tab is wide enough; the icon is always shown. The width is the bar's share per
## shown tab, not the button's own width: a button sized by its label could never shrink back (a feedback loop).
func _layout_tabs() -> void:
	if _tabs.is_empty():
		return
	var shown := 0
	for id in _tabs:
		if (_tabs[id] as Button).visible:
			shown += 1
	var bar := (_tabs.values()[0] as Button).get_parent() as Control
	var slot := bar.size.x / maxf(shown, 1.0)
	for id in _tabs:
		var b: Button = _tabs[id]
		b.text = TAB_LABELS.get(id, "") if slot >= TAB_LABEL_MIN_WIDTH else ""


func _first_unlocked() -> String:
	for id in PANEL_IDS:
		if _tabs.has(id) and (_tabs[id] as Button).visible:
			return id
	return ""


## Shows the Help tab on `topic` (the "?" buttons call this through the "shell" group).
func open_help(topic: String) -> void:
	_select("help")
	var p: Variant = _panels.get("help")
	if p != null and p.has_method("open_topic"):
		p.open_topic(topic)


func _select(id: String) -> void:
	if id == "" or not _panels.has(id):
		return
	_current = id
	for k in _panels:
		_panels[k].visible = k == id
	(_tabs[id] as Button).button_pressed = true
	_refresh_tabs()


## Keeps the UI at least 1:1 with the window: below the 360x640 base in a dimension, the base shrinks to the window
## (so a 390-tall phone landscape is not scaled to 0.6). Larger windows keep the 360x640 base.
func _fit_base() -> void:
	var w := get_window().size
	get_window().content_scale_size = Vector2i(mini(360, w.x), mini(640, w.y))


## Portrait below ~1:1 aspect; switches the body between row and column.
func _on_resized() -> void:
	var portrait := size.y > size.x
	_body.vertical = portrait
	_lab_slot.size_flags_stretch_ratio = 0.75 if portrait else 1.0   # portrait: keep the lab visible while leaving room for panel rows
	_panel_area.size_flags_stretch_ratio = 1.5 if portrait else 1.0
	_hud_flow.columns = 4 if portrait else (9 if size.x >= 1000.0 else 4)
	var target: Node = _head_row if portrait else _hud_flow
	_headline.vertical = portrait
	_headline.add_theme_constant_override("separation", 0 if portrait else 8)
	if _headline != null and _headline.get_parent() != target:
		_headline.get_parent().remove_child(_headline)
		target.add_child(_headline)
	_head_row.visible = portrait
	var stats_home: Node = _head_row if portrait else _hud_row
	if _stats_btn.get_parent() != stats_home:
		_stats_btn.get_parent().remove_child(_stats_btn)
		stats_home.add_child(_stats_btn)
	if not portrait:
		_hud_row.move_child(_stats_btn, 1)
	_apply_safe_area()


## Phones: pads the shell clear of the notch, rounded corners and gesture bar. Desktop reports the screen minus the
## menu bar and dock as its "safe area", so it is not used there.
func _apply_safe_area() -> void:
	if _column == null or not OS.has_feature("mobile") or get_window().size.x <= 0 or get_window().size.y <= 0:
		return
	var win := get_window()
	var px := safe_insets_px(DisplayServer.get_display_safe_area(), Rect2i(win.position, win.size))
	var k := get_viewport_rect().size / Vector2(win.size)  # window pixels -> viewport units
	_column.offset_left = px.x * k.x
	_column.offset_top = px.y * k.y
	_column.offset_right = -px.z * k.x
	_column.offset_bottom = -px.w * k.y


## Insets of the safe area `safe` inside the window `win` (both in screen pixels), as (left, top, right, bottom).
## An empty or non-overlapping safe area gives no insets.
static func safe_insets_px(safe: Rect2i, win: Rect2i) -> Vector4:
	var r := safe.intersection(win)
	if safe.size.x <= 0 or safe.size.y <= 0 or r.size.x <= 0 or r.size.y <= 0:
		return Vector4.ZERO
	return Vector4(
		r.position.x - win.position.x,
		r.position.y - win.position.y,
		win.end.x - r.end.x,
		win.end.y - r.end.y)


## Android back (WM_GO_BACK_REQUEST; the app does not quit on it, see project.godot): closes the topmost dialog,
## else goes to the first tab, else saves and quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


## Escape on desktop closes the topmost dialog. (The intro handles Escape itself, before this.)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _dismiss_top():
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and _hotkey(event as InputEventKey):
		get_viewport().set_input_as_handled()


## Desktop keys (listed in Settings and the Keyboard shortcuts help topic). 1-9 pick a tab, B cycles the producer buy
## amount, Space or Enter confirms the open card. Ignored while typing in a text field, with Ctrl/Alt/Cmd, and behind a dialog.
func _hotkey(ev: InputEventKey) -> bool:
	if ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	if ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		return _confirm_top()
	if _modal_busy or (_stats != null and _stats.visible):
		return false
	if ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
		var id: String = PANEL_IDS[ev.keycode - KEY_1]
		if _tabs.has(id) and (_tabs[id] as Button).visible:
			_select(id)
			return true
	if ev.keycode == KEY_B and _panels.get("producers") != null:
		(_panels["producers"] as Control).call("cycle_amount")
		return true
	return false


## Space or Enter: the open card's OK, the reveal card or the offline and save card. False when none is open.
func _confirm_top() -> bool:
	return _reveal_card.dismiss() or _notices.dismiss()


## Settings > Statistics: the overlay over the shell. Close and Back hide it (see _dismiss_top).
func open_stats() -> void:
	if _stats == null:
		_stats = StatsPanel.new()
		add_child(_stats)
	_stats.visible = true


func _back() -> void:
	if _dismiss_top():
		return
	var first := _first_unlocked()
	if first != "" and first != _current:
		_select(first)
		return
	Game.save_now()
	get_tree().quit()


## Closes the topmost thing that can be dismissed: a sub-window (settings confirm), a tip, the offline or save card,
## the ending or the intro. Returns false when nothing is open. An event choice or the prestige transition must be
## answered, so while one is up this returns true and leaves it open.
func _dismiss_top() -> bool:
	var subs := get_viewport().get_embedded_subwindows()
	for i in range(subs.size() - 1, -1, -1):
		if subs[i].visible:
			subs[i].hide()
			return true
	if _tip != null and bool(_tip.get("_shown")):
		_tip.call("_hide")
		return true
	if _intro != null and not _intro.is_queued_for_deletion():
		_intro.call("_finish")
		return true
	if _ending != null and not _ending.is_queued_for_deletion():
		_ending.call("_close")
		return true
	if _stats != null and _stats.visible:
		_stats.hide()
		return true
	if _reveal_card.dismiss():
		return true
	if _notices.dismiss():
		return true
	return _modal_busy


func _process(delta: float) -> void:
	Game.news_held = _modal_busy
	(_cash["value"] as TickLabel).set_target(Game.cash())
	(_compute["value"] as TickLabel).set_target(Game.compute())
	_rate_tick += delta
	if _rate_tick >= 0.25:
		_rate_tick = 0.0
		_stats_btn.text = "Stats %d%%" % roundi(float(Records.completion(Game.state)["percent"]))
		(_cash["rate"] as Label).text = "+%s/s" % Game.cash_per_second().format()
		(_compute["rate"] as Label).text = "+%s/s" % Game.compute_per_second().format()
		_refresh_headline()
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
	_request_modal(_open_ending.bind(id))


func _open_ending(id: String) -> bool:
	var scene: Node = load(ENDING_SCENE).instantiate()
	add_child(scene)
	_ending = scene
	scene.closed.connect(_on_modal_closed)
	scene.tree_exited.connect(func() -> void:
		_ending_shown = false
		_ending = null)
	scene.call("show_ending", id)
	return true


## Plays the intro over the shell and pauses the simulation until it ends. Called on first launch and by Settings.
func play_intro() -> void:
	if _intro_requested or not ResourceLoader.exists(INTRO_SCENE):
		return
	_intro_requested = true
	_request_modal(_open_intro)


func _open_intro() -> bool:
	var was_running := Game.running
	Game.running = false
	_intro = load(INTRO_SCENE).instantiate()
	add_child(_intro)  # Back/Escape end it through _finish, see _dismiss_top
	_intro.finished.connect(_on_intro_done.bind(was_running))
	_intro.tree_exited.connect(func() -> void: _intro = null)
	return true


## The story ended or was skipped: remember it (saved, so it never replays) and resume the simulation.
func _on_intro_done(was_running: bool) -> void:
	Game.state.persist["intro_seen"] = true
	Game.save_now()
	Game.running = was_running
	_intro_requested = false
	_on_modal_closed()


## Modal dialogs take turns. `open` shows its dialog and returns true, or returns false to skip it. Each dialog
## emits `closed` when dismissed, which runs the next queued one. Focus is released so a panel button under the
## dialog cannot be activated from the keyboard.
func _request_modal(open: Callable) -> void:
	_modal_queue.append(open)
	_pump_modals()


func _pump_modals() -> void:
	while not _modal_busy and not _modal_queue.is_empty():
		var open: Callable = _modal_queue.pop_front()
		get_viewport().gui_release_focus()
		_modal_busy = true
		if not open.call():
			_modal_busy = false


func _on_modal_closed() -> void:
	_modal_busy = false
	_pump_modals()
