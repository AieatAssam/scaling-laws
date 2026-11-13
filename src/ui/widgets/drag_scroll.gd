class_name DragScroll
extends ScrollContainer
## A ScrollContainer that scrolls by dragging from anywhere inside it (cards, labels, bars, buttons), with touch and
## with a dragging mouse. Use it for every scroll page. A press becomes a scroll once it moves DEAD_ZONE px: the button
## under it drops its press, so the release cannot click it. A release while moving fast flings. A press that never
## moves is an ordinary tap. A press during a fling only stops the fling (it does not click).
## Works in _input, before the GUI routes events to the buttons.

const DEAD_ZONE := 8.0          # px a press may move before it is a scroll
const FLING_MIN := 150.0        # px/s at release below which the content just stops
const FLING_FRICTION := 0.05    # speed left after one second of fling
const FLING_STOP := 25.0        # px/s below which a fling ends

var _armed := false             # a press is down inside this scroll
var _scrolling := false         # the press became a scroll (or stopped a fling): its events are swallowed
var _touch_index := -1          # finger being tracked; -1 for a mouse press
var _from := Vector2.ZERO       # press position (view px)
var _last := Vector2.ZERO       # last pointer position seen
var _last_ms := 0               # time of the last movement
var _speed := 0.0               # px/s, vertical, smoothed while scrolling
var _fling := 0.0               # px/s still to coast after a release
var _victim: BaseButton = null  # the button under the press, cancelled when the press becomes a scroll
var clock_ms: Callable = Time.get_ticks_msec  # time source for fling speed; the tests replace it to drive time


func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		# Touch screens: the bar is an indicator only, the whole page is the grab area. Mice keep a grabbable bar.
		get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(ev: InputEvent) -> void:
	var pointer := ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventMouse
	if not pointer:
		return
	# Moves of a scroll never reach the buttons under the finger (they would hover them again). The release is
	# passed on so the GUI clears its mouse focus; the victim already dropped its press, so it does not click.
	var release: bool = (ev is InputEventScreenTouch or ev is InputEventMouseButton) and not ev.pressed
	var was_scrolling := _scrolling
	_handle_pointer(ev)
	if (was_scrolling or _scrolling) and not release:
		get_viewport().set_input_as_handled()


func _handle_pointer(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			if not _armed and _touch_index == -1 and _owns(t.position):
				_press(t.position, t.index)
		elif t.index == _touch_index:
			_release()
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		if _armed and d.index == _touch_index:
			_move(d.position)
	elif ev is InputEventMouseButton:
		var b := ev as InputEventMouseButton
		if b.device == InputEvent.DEVICE_ID_EMULATION or b.button_index != MOUSE_BUTTON_LEFT:
			return
		if b.pressed:
			if not _armed and _touch_index == -1 and _owns(b.position):
				_press(b.position, -1)
		elif _armed and _touch_index == -1:
			_release()
	elif ev is InputEventMouseMotion:
		var m := ev as InputEventMouseMotion
		if _armed and _touch_index == -1 and m.device != InputEvent.DEVICE_ID_EMULATION and (m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move(m.position)


func _process(delta: float) -> void:
	if _fling == 0.0:
		return
	var before := scroll_vertical
	scroll_vertical = before + int(roundf(_fling * delta))
	_fling *= pow(FLING_FRICTION, delta)
	if absf(_fling) < FLING_STOP or scroll_vertical == before:
		_fling = 0.0


## Starts tracking a press at `at`. A press during a fling stops the fling and is swallowed: it is not a tap.
func _press(at: Vector2, index: int) -> void:
	_armed = true
	_touch_index = index
	_from = at
	_last = at
	_last_ms = clock_ms.call()
	_speed = 0.0
	_victim = _button_at(at)
	if _fling != 0.0:
		_fling = 0.0
		_begin_scroll()


## Pointer moved to `at`. Past the dead zone the press is a scroll: the content follows the pointer.
func _move(at: Vector2) -> void:
	if not _scrolling:
		if at.distance_to(_from) <= DEAD_ZONE:
			return
		_begin_scroll()
		_last = _from
	var now: int = clock_ms.call()
	var dt := maxf((now - _last_ms) / 1000.0, 0.008)
	var step := at - _last
	scroll_vertical -= int(roundf(step.y))
	_speed = lerpf(_speed, -step.y / dt, 0.5)
	_last = at
	_last_ms = now


## The press becomes a scroll: the button under it drops its press, so the release does not click it.
func _begin_scroll() -> void:
	_scrolling = true
	if _victim != null and is_instance_valid(_victim):
		_victim.notification(Control.NOTIFICATION_MOUSE_EXIT)


func _release() -> void:
	if _scrolling and int(clock_ms.call()) - _last_ms < 120 and absf(_speed) >= FLING_MIN:
		_fling = _speed
	if _scrolling and _victim != null and is_instance_valid(_victim):
		# The release the GUI sends next must not click the victim. Its signals are muted until the end of the
		# frame (disabling it instead left it unclickable after the next tap).
		var v := _victim
		v.set_block_signals(true)
		_unmute(v).call_deferred()
	_armed = false
	_scrolling = false
	_touch_index = -1
	_victim = null


## Callable that unmutes a button muted by _release.
static func _unmute(v: BaseButton) -> Callable:
	return func() -> void:
		if is_instance_valid(v):
			v.set_block_signals(false)


## True when a press at `at` lands on this scroll's page, not on a bar the mouse can grab.
func _owns(at: Vector2) -> bool:
	if not is_visible_in_tree() or not get_global_rect().has_point(at):
		return false
	var bar := get_v_scroll_bar()
	return not (bar.is_visible_in_tree() and bar.mouse_filter != Control.MOUSE_FILTER_IGNORE and bar.get_global_rect().has_point(at))


## The innermost visible button under `at` inside this scroll, or null.
func _button_at(at: Vector2) -> BaseButton:
	var best: BaseButton = null
	for n in find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b == null or not b.is_visible_in_tree() or not b.get_global_rect().has_point(at):
			continue
		if best == null or b.get_global_rect().get_area() < best.get_global_rect().get_area():
			best = b
	return best
