class_name Notices
extends Control
## "While you were away" card (blocks input until OK) and the benchmark toast (click-through).
## The card is a modal: it opens through `gate` (the shell's modal queue) and emits `closed` on OK.

signal closed

var gate: Callable   # shell: runs an open Callable now or after the dialog in front closes

var _shade: ColorRect
var _card: PanelContainer
var _head: Label
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
	_toast_icon.custom_minimum_size = Vector2(48, 48)   # badge art is 48x48, shown 1:1
	_toast_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_toast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_toast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_toast_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_head = Label.new()
	_head.theme_type_variation = &"Heading"
	box.add_child(_head)
	_offline = Label.new()
	_offline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_offline)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0, 28)
	ok.pressed.connect(_close)
	box.add_child(ok)

	Game.offline_progress.connect(func(s: Dictionary) -> void: _request(show_offline.bind(s)))
	Game.save_notice.connect(func(text: String) -> void: _request(show_save_notice.bind(text)))
	Game.benchmark_unlocked.connect(show_benchmark)


func _request(open: Callable) -> void:
	if gate.is_valid():
		gate.call(open)
	else:
		open.call()


func show_offline(s: Dictionary) -> bool:
	# Real time away (the sim only credits up to the cap); Game puts it in the summary as "away".
	var secs := float(s.get("away", 0.0))
	var h := int(secs) / 3600
	var m := (int(secs) % 3600) / 60
	var lines := PackedStringArray()
	lines.append("Away %dh %02dm" % [h, m])
	if s["capped"]:
		lines.append("Offline progress is capped at 24h.")
	lines.append("Cash +%s" % (s["cash"] as BigNum).format())
	lines.append("Compute +%s" % (s["compute"] as BigNum).format())
	lines.append("(earned at 50% efficiency)")
	# What happened while away, counted by kind (these are sim happenings, not only random events).
	var names := {"reset": "resets", "training_done": "training runs", "benchmark": "benchmarks", "rival_launched": "rival launches",
		"challenge_done": "challenges", "agi_advanced": "AGI stages"}
	var counts := {}
	for e in s["events"] as Array:
		var k := str((e as Dictionary).get("kind", ""))
		if names.has(k):
			counts[k] = int(counts.get(k, 0)) + 1
	for k in counts:
		lines.append("%s: %d" % [str(names[k]).capitalize(), counts[k]])
	return _show("While you were away", "\n".join(lines))


## Save file trouble (a damaged save was set aside or a backup was used). Same card, different heading.
func show_save_notice(text: String) -> bool:
	return _show("Save file", text)


func _show(heading: String, body: String) -> bool:
	_head.text = heading
	_offline.text = body
	_shade.visible = true
	_card.visible = true
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	return true


func show_benchmark(id: String, badge: String) -> void:
	var d = Content.get_def("benchmarks", id)
	_toast_icon.texture = Fx.tex("res://assets/badges/%s.png" % badge, Vector2i(48, 48))  # fallback at logical size
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
	closed.emit()


## Back button / Escape: closes the card if it is open. Returns true when it was.
func dismiss() -> bool:
	if not _card.visible:
		return false
	_close()
	return true
