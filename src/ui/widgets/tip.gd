class_name Tip
extends CanvasLayer
## One tooltip for mouse and touch. Controls opt in with Tip.attach(ctrl, source).
## source: a String, or a Callable returning one (re-read while the tip is open). First line is the title.
## Mouse: shows after HOVER_DELAY over the control, hides when the pointer leaves.
## Touch: a press held LONG_PRESS seconds shows it; releasing the finger, or tapping anywhere, dismisses it
## and swallows that input so a Buy button under the finger does not fire.

const HOVER_DELAY := 0.35
const LONG_PRESS := 0.4
const SLOP := DragScroll.DEAD_ZONE  # finger movement (px) that turns a press into a scroll
const TOUCH_GRACE_MS := 700   # emulated mouse hover right after a touch is ignored
const WIDTH := 300.0
const EDGE_GAP := 8.0
const REFRESH := 0.25
const FADE := 0.12

var _panel: PanelContainer
var _title: Label
var _body: Label
var _ctrl: Control = null     # control the tip is open for
var _src: Variant = ""
var _touch := false           # open because of a long-press (sticky until release or tap)
var _shown := false
var _hover_owner: Control = null
var _hover_t := 0.0
var _touch_down := false
var _last_touch := -100000
var _press_armed := false
var _swallow_until := 0       # ms: the next mouse release (a long-press's emulated click) is swallowed before this
var _press_t := 0.0
var _press_at := Vector2.ZERO
var _refresh_t := 0.0
var _fade: Tween


## Registers a tip. Labels and containers default to MOUSE_FILTER_IGNORE, so they are switched to PASS to receive hover.
static func attach(ctrl: Control, source: Variant) -> void:
	ctrl.set_meta("tip", source)
	ctrl.add_to_group(&"tip_owners")
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.tooltip_text = ""


func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = _line(Fx.ACCENT)
	v.add_child(_title)
	_body = _line(Fx.TEXT)
	v.add_child(_body)


func _line(color: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MicroLabel"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Fx.col(color))
	return l


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touch_down = true
			_last_touch = Time.get_ticks_msec()
			_press_armed = true
			_press_t = 0.0
			_press_at = ev.position
			if _shown and _touch:
				_hide()
				get_viewport().set_input_as_handled()
		else:
			_touch_down = false
			_last_touch = Time.get_ticks_msec()
			_press_armed = false
			if _shown and _touch:
				_hide()
				get_viewport().set_input_as_handled()
	elif ev is InputEventScreenDrag and _press_armed:
		if ev.position.distance_to(_press_at) > SLOP:
			_press_armed = false
	elif ev is InputEventMouseButton and not ev.pressed and Time.get_ticks_msec() < _swallow_until:
		# The emulated mouse release of a long-press must not click the button under the finger.
		_swallow_until = 0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _shown and _ctrl != null and (not is_instance_valid(_ctrl) or not _ctrl.is_visible_in_tree()):
		_hide()
	if _press_armed:
		_press_t += delta
		if _press_t >= LONG_PRESS:
			_press_armed = false
			# By where the finger is: a touch does not reliably move the hover state.
			# A held finger is a hold, not a click: a button under it drops its press so the release does not fire it.
			var btn := _button_at(_press_at)
			if btn != null:
				btn.notification(Control.NOTIFICATION_MOUSE_EXIT)
				_swallow_until = Time.get_ticks_msec() + 500
			var target := _owner_at(_press_at)
			if target != null:
				_show(target, true)
	# Mouse hover, ignored while a finger is down or just lifted (touch emulates the mouse).
	var hover_ok := not _touch_down and Time.get_ticks_msec() - _last_touch > TOUCH_GRACE_MS
	var hit: Control = _owner_of(get_viewport().gui_get_hovered_control()) if hover_ok else null
	if not _touch:
		if hit != _hover_owner:
			_hover_owner = hit
			_hover_t = 0.0
			if _shown:
				_hide()
		elif hit != null and not _shown:
			_hover_t += delta
			if _hover_t >= HOVER_DELAY:
				_show(hit, false)
	if _shown:
		_refresh_t += delta
		if _refresh_t >= REFRESH:
			_refresh_t = 0.0
			_fill()
		_place()


## The innermost visible tip owner whose rect holds the viewport position `pos`.
func _owner_at(pos: Vector2) -> Control:
	return _innermost_at(get_tree().get_nodes_in_group(&"tip_owners"), pos)


## The innermost visible button whose rect holds `pos`.
func _button_at(pos: Vector2) -> BaseButton:
	return _innermost_at(get_tree().root.find_children("*", "BaseButton", true, false), pos) as BaseButton


static func _innermost_at(nodes: Array, pos: Vector2) -> Control:
	var best: Control = null
	for n in nodes:
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or not c.get_global_rect().has_point(pos):
			continue
		if best == null or c.get_global_rect().get_area() < best.get_global_rect().get_area():
			best = c
	return best


## Innermost ancestor-or-self of `c` that has a tip.
static func _owner_of(c: Control) -> Control:
	var n: Node = c
	while n != null:
		if n is Control and n.has_meta("tip"):
			return n
		n = n.get_parent()
	return null


func _show(ctrl: Control, touch: bool) -> void:
	_ctrl = ctrl
	_touch = touch
	_src = ctrl.get_meta("tip")
	_shown = true
	_refresh_t = 0.0
	_fill()
	_panel.visible = true
	if _fade != null:
		_fade.kill()
	if Fx.reduce_motion() or touch:
		_panel.modulate.a = 1.0
	else:
		_panel.modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(_panel, "modulate:a", 1.0, FADE)
	_place()


func _hide() -> void:
	_shown = false
	_touch = false
	_ctrl = null
	_panel.visible = false


func _fill() -> void:
	var text: String = str(_src.call()) if _src is Callable else str(_src)
	if text == "":
		_hide()
		return
	var lines := text.split("\n")
	_title.text = lines[0]
	var rest := PackedStringArray(lines.slice(1))
	_body.text = "\n".join(rest)
	_body.visible = not rest.is_empty()


## Places the tip beside its control, inside the visible rect. Touch prefers above the finger.
func _place() -> void:
	if _ctrl == null or not is_instance_valid(_ctrl):
		return
	var vp := get_viewport().get_visible_rect()
	var w := minf(WIDTH, vp.size.x - EDGE_GAP * 2.0)
	_panel.custom_minimum_size.x = w
	_panel.size = _panel.get_combined_minimum_size()
	var sz := _panel.size
	var r := _ctrl.get_global_rect()
	var above := r.position.y - sz.y - 4.0
	var below := r.end.y + 4.0
	var fits_above := above >= EDGE_GAP
	var fits_below := below + sz.y <= vp.end.y - EDGE_GAP
	var y := below
	if _touch:
		y = above if fits_above or not fits_below else below
	else:
		y = below if fits_below or not fits_above else above
	var x := r.get_center().x - sz.x * 0.5
	_panel.position = Vector2(
		clampf(x, EDGE_GAP, maxf(EDGE_GAP, vp.end.x - sz.x - EDGE_GAP)),
		clampf(y, EDGE_GAP, maxf(EDGE_GAP, vp.end.y - sz.y - EDGE_GAP)))
