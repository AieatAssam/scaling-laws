extends GutTest
## Drag-to-scroll on every scroll page. Real input: events are pushed into a SubViewport (its own GUI, so buttons
## get presses, releases and the engine's touch-to-mouse emulation exactly as in the game). A drag scrolls and
## clicks nothing; a tap clicks the button under the finger.

const Support := preload("res://tests/support.gd")

var content: Node
var host: SubViewport
var scroll: DragScroll
var clicks := 0


func before_each() -> void:
	content = autofree(Support.make_content())
	clicks = 0
	# GUT's output panel covers the test window, so the scroll lives in its own viewport.
	host = SubViewport.new()
	host.size = Vector2i(360, 640)
	host.handle_input_locally = true
	add_child_autofree(host)


## A DragScroll of `n` full-width buttons (52 px apart) at (20, 20), 300x300, laid out and ready.
func _scroll_with_buttons(n: int) -> DragScroll:
	var sc := DragScroll.new()
	sc.position = Vector2(20, 20)
	sc.size = Vector2(300, 300)
	host.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	for i in n:
		var b := Button.new()
		b.text = "Buy %d" % i
		b.custom_minimum_size = Vector2(260, 44)
		b.pressed.connect(func() -> void: clicks += 1)
		list.add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	scroll = sc
	return sc


func _center(i: int) -> Vector2:
	return ((scroll.get_child(0) as VBoxContainer).get_child(i) as Control).get_global_rect().get_center()


func _push(ev: InputEvent) -> void:
	host.push_input(ev)
	await get_tree().process_frame


func _touch(pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = at
	return e


func _finger(at: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	e.relative = rel
	return e


func _mouse(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return e


func _mouse_move(at: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


## A finger from `from` to `to` in `steps` moves, then lifted.
func _touch_drag(from: Vector2, to: Vector2, steps := 8) -> void:
	await _push(_touch(true, from))
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		await _push(_finger(p, p - prev))
		prev = p
	await _push(_touch(false, to))


func _mouse_drag(from: Vector2, to: Vector2, steps := 8) -> void:
	await _push(_mouse(true, from))
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		await _push(_mouse_move(p, p - prev))
		prev = p
	await _push(_mouse(false, to))


func test_touch_drag_from_a_button_scrolls_and_clicks_nothing() -> void:
	await _scroll_with_buttons(20)
	await _touch_drag(_center(2), _center(2) + Vector2(0, -120))
	assert_gt(scroll.scroll_vertical, 0, "content scrolled")
	assert_eq(clicks, 0, "the drag did not click")


func test_touch_tap_clicks_the_button_under_the_finger() -> void:
	await _scroll_with_buttons(20)
	await _push(_touch(true, _center(0)))
	await _push(_touch(false, _center(0)))
	assert_eq(clicks, 1, "a tap clicks")
	assert_eq(scroll.scroll_vertical, 0, "a tap does not scroll")


func test_mouse_drag_from_a_button_scrolls_and_clicks_nothing() -> void:
	await _scroll_with_buttons(20)
	await _mouse_drag(_center(3), _center(3) + Vector2(0, -120))
	assert_gt(scroll.scroll_vertical, 0, "content scrolled")
	assert_eq(clicks, 0, "the drag did not click")


func test_mouse_click_clicks_the_button() -> void:
	await _scroll_with_buttons(20)
	await _push(_mouse(true, _center(1)))
	await _push(_mouse(false, _center(1)))
	assert_eq(clicks, 1, "a click clicks")


func test_tap_after_a_drag_clicks_what_it_lands_on() -> void:
	await _scroll_with_buttons(20)
	await _touch_drag(_center(4), _center(4) + Vector2(0, -100))
	assert_gt(scroll.scroll_vertical, 0, "content scrolled")
	await get_tree().create_timer(3.0).timeout  # let the fling run out
	var top := scroll.get_global_rect().position + Vector2(150, 22)
	await _push(_touch(true, top))
	await _push(_touch(false, top))
	assert_eq(clicks, 1, "a tap after the drag clicks")


func test_a_press_during_a_fling_stops_it_and_does_not_click() -> void:
	await _scroll_with_buttons(20)
	await _touch_drag(_center(4), _center(4) + Vector2(0, -100))
	var top := scroll.get_global_rect().position + Vector2(150, 22)
	await _push(_touch(true, top))
	var stopped := scroll.scroll_vertical
	await get_tree().create_timer(0.5).timeout
	assert_eq(scroll.scroll_vertical, stopped, "the fling stopped at the press")
	await _push(_touch(false, top))
	assert_eq(clicks, 0, "the press that stopped the fling is not a tap")


## The real panels, in a phone-sized viewport with the live Game state. Each one is dragged from a button in its
## scroll and tapped on a button; the buttons count their presses.

const PANEL_SAVE := "user://test_drag_scroll.json"


## Hosts `panel` in the test viewport at 360x640 and waits until it has built and laid out.
func _host_panel(panel: Control) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # fills the 360x640 host
	host.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


## The panel's scroll container (the DragScroll every page builds).
func _panel_scroll(panel: Control) -> DragScroll:
	for n in panel.find_children("*", "DragScroll", true, false):
		return n
	return null


## The first visible, enabled button fully inside the scroll's view.
func _visible_button(sc: DragScroll) -> BaseButton:
	var view := sc.get_global_rect()
	for n in sc.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled and view.encloses(b.get_global_rect()):
			return b
	return null


## Drags up from a button in `sc`, lets the fling end, then taps a button still in view. Returns
## [the scroll moved, presses during the drag, presses from the tap], counting presses on every button in `sc`.
func _drag_then_tap(sc: DragScroll, b: BaseButton) -> Array:
	var presses := [0]
	for n in sc.find_children("*", "BaseButton", true, false):
		(n as BaseButton).pressed.connect(func() -> void: presses[0] += 1)
	var from := b.get_global_rect().get_center()
	scroll = sc
	await _touch_drag(from, from + Vector2(0, -90))
	var moved := sc.scroll_vertical > 0
	var drag_presses: int = presses[0]
	await get_tree().create_timer(3.0).timeout  # let the fling run out
	var t := _visible_button(sc)
	var at := t.get_global_rect().get_center()
	await _push(_touch(true, at))
	await _push(_touch(false, at))
	return [moved, drag_presses, presses[0] - drag_presses]


func _set_up_game() -> void:
	Game.save_path = PANEL_SAVE
	Game.running = false
	Game.state.persist["intro_seen"] = true
	Game.state.add_cur("cash", BigNum.from_float(1e12))  # producer buttons are enabled, so a tap can click one


func after_each() -> void:
	Support.remove_save_files(PANEL_SAVE)


func test_producers_panel_drag_scrolls_and_tap_buys() -> void:
	_set_up_game()
	for _i in 3:  # unlock the tiers so the list is taller than the view
		for d in Content.get_all("producers"):
			Game.buy_producer(d.id, -1)
	Game.state.add_cur("cash", BigNum.from_float(1e30))  # the buys above spent the cash: the buy buttons need some
	var panel := ProducersPanel.new()
	await _host_panel(panel)
	await get_tree().create_timer(0.3).timeout  # the panel refreshes on a timer: enable the buy buttons
	var sc := _panel_scroll(panel)
	assert_not_null(sc, "producers page is a DragScroll")
	var b := _visible_button(sc)
	assert_not_null(b, "a buy button is in view")
	var r := await _drag_then_tap(sc, b)
	assert_true(r[0], "the drag scrolled the producers list")
	assert_eq(r[1], 0, "the drag did not press the buy button")
	assert_eq(r[2], 1, "a tap pressed a button in view")


func test_benchmarks_panel_drag_scrolls() -> void:
	_set_up_game()
	var panel := BenchmarksPanel.new()
	await _host_panel(panel)
	var sc := _panel_scroll(panel)
	assert_not_null(sc, "benchmarks page is a DragScroll")
	var from := sc.get_global_rect().get_center()
	await _touch_drag(from, from + Vector2(0, -90))
	assert_gt(sc.scroll_vertical, 0, "the drag scrolled the benchmark list")


func test_help_panel_drag_scrolls_and_tap_opens_a_topic() -> void:
	_set_up_game()
	var panel := HelpPanel.new()
	await _host_panel(panel)
	var sc := _panel_scroll(panel)
	assert_not_null(sc, "help page is a DragScroll")
	var b := _visible_button(sc)
	assert_not_null(b, "a topic header is in view")
	var r := await _drag_then_tap(sc, b)
	assert_true(r[0], "the drag scrolled the help topics")
	assert_eq(r[1], 0, "the drag did not open or close a topic")
	assert_eq(r[2], 1, "a tap on a topic header in view toggles it")
