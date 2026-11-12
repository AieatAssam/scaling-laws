extends Control
## First-run intro: five illustrated beats with typed captions, shown over the shell. Pointer-first: a tap or click
## finishes the typing, then the next tap advances. Skip, Enter, Space or Esc ends it. Emits `finished` once, when the
## story ends or is skipped (main.gd sets persist.intro_seen and resumes the simulation), then fades out and frees itself.
## reduce_motion: no pan, zoom, twinkle, typing or fades; each beat is a cut.

signal finished

const DIR := "res://assets/intro/%s.png"
const BEATS := [
	{"art": "01_idea", "pivot": Vector2(0.42, 0.3), "stars": true, "glow": Vector2(0.42, 0.29),
		"caption": "3:07 AM. You wake up with an idea: what if you just... made the model bigger?"},
	{"art": "02_pizza_box", "pivot": Vector2(0.5, 0.5),
		"caption": "You sketch it on the back of a pizza box. The loss curve only goes down. Probably."},
	{"art": "03_phone_call", "pivot": Vector2(0.5, 0.45),
		"caption": "You call your best friend. \"I have a laptop and no plan.\" - \"I'm in.\""},
	{"art": "04_garage_deal", "pivot": Vector2(0.4, 0.55), "stars": true,
		"caption": "Your parents agree to lend you the garage, on one condition: the car still fits."},
	{"art": "05_open_for_business", "pivot": Vector2(0.5, 0.6), "glow": Vector2(0.5, 0.57),
		"caption": "One intern laptop. One extension cord. Scaling Laws Labs is open for business."},
]
const CPS := 40.0            # typed characters per second
const HOLD := 4.0            # seconds a finished caption stays up before the next beat
const FADE := 0.35           # seconds per fade (out, then in); the final fade takes twice this
const PAN_ZOOM := 1.08       # art scale reached at the end of a beat
const PAN_SECONDS := 9.0
const CAPTION_MIN_H := 120.0 # room for the wrapped caption on a phone-width screen
const SKIP_SIZE := Vector2(72, 32)
const STAR_COUNT := 10

var _art: TextureRect
var _fx: Control             # ambient layer, child of _art so it pans and zooms with the art
var _content: Control        # everything but the Skip button; faded between beats
var _box: PanelContainer
var _caption: Label
var _dots: Array[ColorRect] = []
var _cursor: ColorRect       # blinking marker at the caption box's bottom-right corner
var _index := -1
var _pivot := Vector2(0.5, 0.5)
var _pan: Tween
var _typed := 0.0
var _typing := false
var _busy := false           # a fade is running; taps are ignored
var _done := false
var _hold := 0.0
var _blink := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Fx.col(Fx.BG)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(top)
	var skip := Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = SKIP_SIZE
	skip.pressed.connect(_finish)
	top.add_child(skip)

	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_content.modulate.a = 0.0
	col.add_child(_content)

	var ratio := AspectRatioContainer.new()
	ratio.ratio = 16.0 / 9.0
	ratio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(ratio)
	var stage := Control.new()
	stage.clip_contents = true
	ratio.add_child(stage)
	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.resized.connect(func() -> void: _art.pivot_offset = _art.size * _pivot)
	stage.add_child(_art)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.add_child(_fx)

	_box = PanelContainer.new()
	_box.custom_minimum_size.y = CAPTION_MIN_H
	var sb := StyleBoxFlat.new()
	sb.bg_color = Fx.col(Fx.PANEL)
	sb.border_color = Fx.col(Fx.BORDER)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	_box.add_theme_stylebox_override("panel", sb)
	_content.add_child(_box)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_color_override("font_color", Fx.col(Fx.TEXT))
	_box.add_child(_caption)

	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 8)
	_content.add_child(dots)
	for i in BEATS.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(8, 8)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(d)
		_dots.append(d)

	_cursor = ColorRect.new()
	_cursor.color = Fx.col(Fx.GOLD)
	_cursor.size = Vector2(8, 8)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)
	_show(0)


func _process(delta: float) -> void:
	if _done:
		return
	_blink += delta
	_place_cursor()
	if _typing:
		_typed += delta * CPS
		var total := _caption.get_total_character_count()
		_caption.visible_characters = mini(int(_typed), total)
		if _caption.visible_characters >= total:
			_end_typing()
	elif not _busy:
		_hold += delta
		if _hold >= HOLD:
			_advance()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _done or key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_tap()
		KEY_ESCAPE:
			_finish()
		_:
			return
	get_viewport().set_input_as_handled()  # so a focused panel button underneath does not also fire


## Mouse clicks; touch arrives here as emulated mouse clicks (project default), so one path serves both.
func _gui_input(event: InputEvent) -> void:
	var btn := event as InputEventMouseButton
	if btn != null and btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_tap()


func _tap() -> void:
	if _done or _busy:
		return
	if _typing:
		_end_typing()
	else:
		_advance()


func _end_typing() -> void:
	_typing = false
	_caption.visible_characters = -1
	_hold = 0.0


func _advance() -> void:
	if _index + 1 >= BEATS.size():
		_finish()
	else:
		_show(_index + 1)


func _show(i: int) -> void:
	_busy = true
	_typing = false
	_hold = 0.0
	if Fx.reduce_motion():
		_content.modulate.a = 1.0
		_apply(i)
		_on_shown()
		return
	var t := create_tween()
	if i > 0:
		t.tween_property(_content, "modulate:a", 0.0, FADE)
	t.tween_callback(_apply.bind(i))
	t.tween_property(_content, "modulate:a", 1.0, FADE)
	t.tween_callback(_on_shown)


func _apply(i: int) -> void:
	_index = i
	var b: Dictionary = BEATS[i]
	_art.texture = Fx.tex(DIR % b["art"], Vector2i(320, 180))
	_pivot = b["pivot"]
	_art.pivot_offset = _art.size * _pivot
	_art.scale = Vector2.ONE
	if _pan != null:
		_pan.kill()
	if not Fx.reduce_motion():
		_pan = _art.create_tween()
		_pan.tween_property(_art, "scale", Vector2.ONE * PAN_ZOOM, PAN_SECONDS)
	_caption.text = b["caption"]
	_caption.visible_characters = 0
	for k in _dots.size():
		_dots[k].color = Fx.col(Fx.GOLD if k == i else Fx.BORDER)
	_fill_fx(b)


func _on_shown() -> void:
	_busy = false
	_hold = 0.0
	if Fx.reduce_motion():
		_caption.visible_characters = -1
	else:
		_typed = 0.0
		_typing = true


## Ambient touches for one beat: twinkling stars and a pulsing glow. Skipped under reduce_motion.
func _fill_fx(b: Dictionary) -> void:
	for c in _fx.get_children():
		c.queue_free()
	if Fx.reduce_motion():
		return
	if b.get("stars", false):
		for n in STAR_COUNT:
			var s := _spot(Vector2(randf_range(0.04, 0.96), randf_range(0.04, 0.42)), Vector2(2, 2), Fx.col(Fx.TEXT))
			_pulse(s, 0.2, 1.0, 1.6)
	if b.has("glow"):
		var g := _spot(b["glow"], Vector2(12, 8), Fx.col(Fx.GOLD))
		_pulse(g, 0.1, 0.5, 1.4)


func _spot(p: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = p.x
	r.anchor_right = p.x
	r.anchor_top = p.y
	r.anchor_bottom = p.y
	r.offset_left = -size.x / 2.0
	r.offset_right = size.x / 2.0
	r.offset_top = -size.y / 2.0
	r.offset_bottom = size.y / 2.0
	_fx.add_child(r)
	return r


func _pulse(r: ColorRect, lo: float, hi: float, period: float) -> void:
	var t := r.create_tween().set_loops()
	t.tween_interval(randf() * period)
	t.tween_property(r, "modulate:a", lo, period / 2.0)
	t.tween_property(r, "modulate:a", hi, period / 2.0)


## Blinking marker, tracked to the caption box's bottom-right corner each frame.
func _place_cursor() -> void:
	var r := _box.get_global_rect()
	_cursor.position = r.end - global_position - Vector2(18, 16)
	_cursor.visible = not _busy and (Fx.reduce_motion() or fmod(_blink, 0.9) < 0.5)


func _finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	finished.emit()
	if Fx.reduce_motion():
		queue_free()
		return
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE * 2.0)
	t.tween_callback(queue_free)
