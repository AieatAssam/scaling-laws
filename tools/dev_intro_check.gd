extends SceneTree
## Dev: drives the first-run intro with real input (keys, mouse, Skip, auto-advance), Settings "Replay intro",
## and checks that nothing ticks behind it. Windowed, not --headless: $GODOT --path . -s tools/dev_intro_check.gd

var fails: Array[String] = []
var _main: Node
var _g: Node


func _initialize() -> void:
	await process_frame
	_g = root.get_node("/root/Game")
	_g.save_path = "user://dev_intro_check_save.json"
	root.get_node("/root/SaveSystem").delete(_g.save_path)  # a fresh first launch
	_g.state.persist["intro_seen"] = false
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	_main = current_scene

	# First launch: the intro is up, the sim is paused, and cash does not move behind it.
	var intro := _intro()
	_check(intro != null, "first launch shows the intro")
	if intro == null:
		quit(1)
		return
	_check(not _g.running, "intro pauses the simulation")
	var cash0: float = _g.state.cur("cash").to_float()
	await create_timer(1.0).timeout
	_check(is_equal_approx(_g.state.cur("cash").to_float(), cash0), "nothing ticks behind the intro")

	# Space ends the typing of beat 0, then advances to beat 1.
	await _key(KEY_SPACE)
	await create_timer(0.2).timeout
	_check(intro.get("_typing") == false, "Space finishes the typing of the first caption")
	await _key(KEY_SPACE)
	await create_timer(1.2).timeout
	_check(intro.get("_index") == 1, "Space advances to the second beat (index %s)" % str(intro.get("_index")))

	# A click advances too: finish typing, then advance.
	var center: Vector2 = intro.get_global_rect().get_center()
	await _click(center)
	await create_timer(0.2).timeout
	await _click(center)
	await create_timer(1.2).timeout
	_check(intro.get("_index") == 2, "a click advances to the third beat (index %s)" % str(intro.get("_index")))

	# Touch (emulated mouse) advances the same way.
	await _touch(center)
	await create_timer(0.2).timeout
	await _touch(center)
	await create_timer(1.2).timeout
	_check(intro.get("_index") == 3, "a tap advances to the fourth beat (index %s)" % str(intro.get("_index")))

	# Auto-advance: with no input, the beat moves on by itself after typing and the hold.
	var before: int = intro.get("_index")
	var moved := false
	for i in 40:
		await create_timer(0.5).timeout
		if intro.get("_index") != before:
			moved = true
			break
	_check(moved, "a beat auto-advances without input")

	# Esc (or Skip) ends the intro: it fades, marks itself seen, frees itself and resumes the sim.
	await _key(KEY_ESCAPE)
	await create_timer(1.5).timeout
	_check(_intro() == null, "Esc ends the intro and frees it")
	_check(bool(_g.state.persist["intro_seen"]), "the intro is marked seen")
	_check(_g.running, "the simulation resumes after the intro")
	_check(not bool(_main.get("_modal_busy")), "the modal queue is free after the intro")

	# Settings > Replay intro plays it again; Skip button ends it; the flag is unchanged.
	var settings: Node = _main.get("_panels")["settings"]
	settings.call("_replay_intro")
	await create_timer(0.5).timeout
	intro = _intro()
	_check(intro != null and not _g.running, "Replay intro plays the intro with the sim paused")
	var skip := _find_button(intro, "Skip")
	_check(skip != null, "the intro has a Skip button")
	if skip != null:
		skip.pressed.emit()
	await create_timer(1.5).timeout
	_check(_intro() == null and _g.running, "Skip ends the replayed intro and resumes the sim")

	# Boot with an unseen intro, a saved pending event and an old save time: the intro goes first, the event waits
	# behind it, and an old save earns no offline progress while the intro is up.
	_g.state.persist["intro_seen"] = false
	_g.state.persist["saved_at"] = Time.get_unix_time_from_system() - 3600.0
	_g.state.run["layers"][0]["pending"] = "bt_moe_scale"
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	_main = current_scene
	intro = _intro()
	_check(intro != null and not _g.running, "boot with an unseen intro shows it first, sim paused")
	var pop := _event_popup()
	var cash1: float = _g.state.cur("cash").to_float()
	await create_timer(1.0).timeout
	_check(pop == null or not pop.visible, "the saved event does not open over the intro")
	_check(is_equal_approx(_g.state.cur("cash").to_float(), cash1), "no offline progress behind the intro")
	await _key(KEY_ESCAPE)
	await create_timer(1.5).timeout
	_check(_intro() == null, "Esc ends the boot intro")
	_check(pop != null and pop.visible, "the saved event opens once the intro is closed")

	print("DEV INTRO %s" % ("OK" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)


func _intro() -> Node:
	return _main.get("_intro") if _main != null else null


func _event_popup() -> Control:
	for c in _main.get_children():
		if c.has_method("check_pending"):
			return c
	return null


func _check(ok: bool, what: String) -> void:
	if ok:
		print("DEV OK: " + what)
	else:
		fails.append(what)
		print("DEV FAIL: " + what)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _touch(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.pressed = pressed
		ev.position = pos
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var f := _find_button(c, text)
		if f != null:
			return f
	return null
