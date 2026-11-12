class_name EventPopup
extends Control
## Modal card for the pending random event. Opens on Game.event_offered; choices go through Game.resolve_event.

var _icon: TextureRect
var _title: Label
var _desc: Label
var _choices: VBoxContainer
var _result: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(Fx.col(Fx.BG), 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 300
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(96, 64)   # logical size; the event art may be 2x
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_icon)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	box.add_child(_choices)
	_result = Label.new()
	_result.theme_type_variation = &"MicroDim"
	box.add_child(_result)
	Game.event_offered.connect(show_event)


## Shows the pending event if one was left over from a save.
func check_pending() -> void:
	var pend: String = Game.state.run["layers"][0]["pending"]
	if pend != "":
		show_event(pend)


func show_event(id: String) -> void:
	var d = Content.get_def("events", id)
	if d == null:
		return
	_icon.texture = Fx.tex("res://assets/events/%s.png" % d.category, Vector2i(96, 64))
	_title.text = str(d.title)
	_desc.text = str(d.description)
	for c in _choices.get_children():
		c.queue_free()
	for i in d.choices.size():
		var ch: Dictionary = d.choices[i]
		var col := VBoxContainer.new()
		# Button text cannot wrap, so the label is a child that does. Two lines fit the 44px height.
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(_pick.bind(i))
		var lbl := Label.new()
		lbl.text = str(ch["label"])
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.offset_left = 8.0
		lbl.offset_right = -8.0
		b.add_child(lbl)
		col.add_child(b)
		var eff := Label.new()
		eff.theme_type_variation = &"MicroDim"
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff.text = Fx.effects_text(ch["effects"])
		col.add_child(eff)
		_choices.add_child(col)
	_result.text = ""
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _pick(i: int) -> void:
	var r: Dictionary = Game.resolve_event(i)
	if r.get("ok", false):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_result.text = str(r.get("reason", "Failed."))
	_result.add_theme_color_override("font_color", Fx.col(Fx.RED))
