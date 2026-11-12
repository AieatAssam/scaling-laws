class_name Notices
extends Control
## "While you were away" card (blocks input until OK) and the benchmark toast (click-through).

var _shade: ColorRect
var _card: PanelContainer
var _offline: Label
var _toast: PanelContainer
var _toast_icon: TextureRect
var _toast_title: Label
var _toast_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_toast = PanelContainer.new()
	# Bottom centre, above the tab bar, so it never covers the HUD or a panel's result line.
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	# Grow both ways from centre and upward from the bottom edge; a bare preset at _ready has zero size and drifts right/down.
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -56
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_toast.add_child(row)
	_toast_icon = TextureRect.new()
	_toast_icon.custom_minimum_size = Vector2(24, 24)
	_toast_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(_toast_icon)
	_toast_title = Label.new()
	_toast_title.theme_type_variation = &"MicroLabel"
	row.add_child(_toast_title)

	_shade = ColorRect.new()
	_shade.color = Color(Fx.col(Fx.BG), 0.8)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	add_child(_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size.x = 300
	_card.visible = false
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	var head := Label.new()
	head.text = "While you were away"
	head.theme_type_variation = &"Heading"
	box.add_child(head)
	_offline = Label.new()
	_offline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_offline)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0, 28)
	ok.pressed.connect(_close)
	box.add_child(ok)

	Game.offline_progress.connect(show_offline)
	Game.benchmark_unlocked.connect(show_benchmark)


func show_offline(s: Dictionary) -> void:
	# Real time away (the sim only credits up to the cap); saved_at is the last write, before this session.
	var secs := maxf(0.0, Time.get_unix_time_from_system() - float(Game.state.persist.get("saved_at", 0.0)))
	var h := int(secs) / 3600
	var m := (int(secs) % 3600) / 60
	var lines := PackedStringArray()
	lines.append("Away %dh %02dm" % [h, m])
	if s["capped"]:
		lines.append("Offline progress is capped at 24h.")
	lines.append("Cash +%s" % (s["cash"] as BigNum).format())
	lines.append("Compute +%s" % (s["compute"] as BigNum).format())
	lines.append("Events while away: %d" % (s["events"] as Array).size())
	_offline.text = "\n".join(lines)
	_shade.visible = true
	_card.visible = true
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP


func show_benchmark(id: String, badge: String) -> void:
	var d = Content.get_def("benchmarks", id)
	_toast_icon.texture = Fx.tex("res://assets/badges/%s.png" % badge, Vector2i(24, 24))
	_toast_title.text = "Benchmark: %s" % (d.title if d else id)
	_toast.visible = true
	_toast_t = 3.0
	Fx.pop(_toast_icon, 1.25)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false


func _close() -> void:
	_card.visible = false
	_shade.visible = false
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
