class_name EventPopup
extends Control
## Modal card for the pending random event. Opens on Game.event_offered; choices go through Game.resolve_event.
## Opening goes through `gate` (the shell's modal queue) so it never stacks on another dialog.

signal closed

var gate: Callable   # shell: runs an open Callable now or after the dialog in front closes

var _icon: TextureRect
var _title: Label
var _desc: Label
var _choices: VBoxContainer
var _result: Label
var _card: PanelContainer
var _scroll: ScrollContainer   # only scrolls when a phone is too short for the whole card (3 choices, long text)

const ART := Vector2(192, 128)  # event art, 2x: drawn 1 texel per logical px, so it stays crisp
const DIALOG_MAX := 420.0       # desktop dialog width; the art fills its content width
const SIDE := 16.0              # gutter kept clear on each side
const TITLE_PX := 24            # heading: one step above the body
const BODY_PX := 16


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
	_card = PanelContainer.new()
	center.add_child(_card)
	_scroll = DragScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	_scroll.add_child(box)
	box.resized.connect(_fit_height)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_icon)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.add_theme_font_size_override("font_size", TITLE_PX)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", BODY_PX)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	box.add_child(_choices)
	_result = Label.new()
	_result.theme_type_variation = &"MicroDim"
	box.add_child(_result)
	resized.connect(_fit_card)
	Game.event_offered.connect(func(id: String) -> void: _request(show_event.bind(id)))


func _request(open: Callable) -> void:
	if gate.is_valid():
		gate.call(open)
	else:
		open.call()


## Shows the pending event if one was left over from a save.
func check_pending() -> void:
	var pend: String = Game.state.run["layers"][0]["pending"]
	if pend != "":
		_request(show_event.bind(pend))


## Returns false when the event is unknown (nothing opened).
func show_event(id: String) -> bool:
	var d = Content.get_def("events", id)
	if d == null:
		return false
	_icon.texture = Fx.tex("res://assets/events/%s.png" % d.category, Vector2i(ART))
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
	_fit_card()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	return true


## Desktop: a DIALOG_MAX card. Phone: the full width minus the gutters. The art fills the content width at its aspect.
func _fit_card() -> void:
	var w := minf(DIALOG_MAX, size.x - 2.0 * SIDE)
	_card.custom_minimum_size.x = w
	var sb := _card.get_theme_stylebox("panel")
	var inner := w - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT)
	_icon.custom_minimum_size = Vector2(floorf(inner), floorf(inner * ART.y / ART.x))
	_fit_height()


## The card is as tall as its content, up to the screen minus the gutters; past that the body scrolls.
func _fit_height() -> void:
	var box := _scroll.get_child(0) as Control
	var sb := _card.get_theme_stylebox("panel")
	var max_h := size.y - 2.0 * SIDE - sb.get_margin(SIDE_TOP) - sb.get_margin(SIDE_BOTTOM)
	var want := minf(box.get_combined_minimum_size().y, max_h)
	if not is_equal_approx(_scroll.custom_minimum_size.y, want):
		_scroll.custom_minimum_size.y = want


func _pick(i: int) -> void:
	var r: Dictionary = Game.resolve_event(i)
	if r.get("ok", false):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		closed.emit()
		return
	_result.text = str(r.get("reason", "Failed."))
	_result.add_theme_color_override("font_color", Fx.col(Fx.RED))
