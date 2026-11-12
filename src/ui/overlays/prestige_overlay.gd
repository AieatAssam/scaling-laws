class_name PrestigeOverlay
extends Control
## Full-screen transition when a layer resets: layer colour, layer name, gain. Click-through.
## Under reduce_motion it cuts in and out without fading.

var _bg: ColorRect
var _title: Label
var _gain: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # children default to STOP and would swallow clicks
	add_child(_bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_gain = Label.new()
	_gain.theme_type_variation = &"Value"
	_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gain)
	Game.layer_reset.connect(play)


func play(layer: int, gain) -> void:
	var def = Fx.layer_def(layer)
	_bg.color = Fx.col(Fx.LAYER_COLORS[clampi(layer, 0, 4)])
	_title.text = "%s reset" % (def.title if def else "Layer %d" % layer)
	_gain.text = "+%s" % Fx.num(float(gain))
	if _tween:
		_tween.kill()
	visible = true
	var calm := Fx.reduce_motion()
	_tween = create_tween()
	if calm:
		modulate.a = 1.0
	else:
		modulate.a = 0.0
		_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(1.0)
	if not calm:
		_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(hide)
