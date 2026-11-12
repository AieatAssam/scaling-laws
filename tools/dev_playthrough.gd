extends SceneTree
## Dev playthrough of the REAL main scene (res://src/ui/main.tscn) driven through the Game API. Not shipped.
## Run with a window (screenshots need a renderer):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/dev_playthrough.gd
## Uses its own save file, never the player's. Writes PNGs to SHOTS, prints "DEV OK" or "DEV FAIL: ..." lines,
## exits 0 only when every check passes. Script errors/warnings show in the engine log (grep it).
##
## CHEAT (dev only): granting currencies, filling layer life, setting clocks and pending events directly, because
## the real game needs hours to reach these states. Everything else is a G().* action or a UI press.

# Screenshots go to $SL_SHOTS if set, else a dev_shots folder in the OS temp dir.
var SHOTS := (OS.get_environment("SL_SHOTS") if OS.get_environment("SL_SHOTS") != "" else OS.get_temp_dir().path_join("scaling-laws-dev-shots")).path_join("play")
const SAVE := "user://dev_playthrough_save.json"
const MAIN := "res://src/ui/main.tscn"
const SIZES := {"desk": Vector2i(1280, 720), "phone": Vector2i(390, 844)}
const TABS := ["producers", "training", "funding", "generation", "paradigm", "singularity", "benchmarks", "settings"]

var _fails: Array[String] = []
var _main: Node
var _shots := 0


func _initialize() -> void:
	await _run()
	print("DEV %s (%d screenshots)" % ["OK" if _fails.is_empty() else "FAIL: %d checks" % _fails.size(), _shots])
	quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	await process_frame  # autoloads are added on the first frame
	DirAccess.make_dir_recursive_absolute(SHOTS)
	S().delete(SAVE)
	G().save_path = SAVE
	G().state.persist["intro_seen"] = true  # skip the first-run intro
	await _boot()

	# Phase 0: fresh save, nothing bought. Desktop and phone.
	await _shots_all("00_fresh")

	# Phase 1: about five minutes in. Buy producers with each amount.
	_cheat("cash", 1e4)
	_cheat("compute", 1e4)
	_play(300.0)
	for amount in [1, 10, -1]:
		_call("producers", "_set_amount", [amount])
		await _settle()
		_press_buy(_first_id("producers"))
		await _settle()
	_check(_any_owned(), "bought producers")
	_call("producers", "_set_amount", [1])
	await _shots_all("01_five_minutes")

	# Phase 2: first Funding Round (layer 1), then a training run.
	await _reset(1, "02_funding")
	_check(G().state.resets(1) >= 1, "first funding round done")
	_play(90.0)
	await _shots_all("03_after_funding")

	# Phase 3: first Model Generation (layer 2), then Paradigm Shift (3) and Singularity (4).
	await _reset(2, "04_model_generation")
	await _reset(3, "05_paradigm_shift")
	await _reset(4, "06_singularity")
	await _shots_all("07_all_layers")
	await _tooltip_phase()

	# Phase 4: event popup. Pending event on layer 0, then the popup shows it.
	G().state.run["layers"][0]["pending"] = _first_id("events")
	_popup_check()
	await _settle()
	_check(_popup_visible(), "event popup shows")
	await _shot("08_event_popup_desk")
	DisplayServer.window_set_size(SIZES["phone"])
	await _settle()
	await _shot("08_event_popup_phone")
	DisplayServer.window_set_size(SIZES["desk"])
	await _settle()
	_click_event_choice(0)
	await _settle()
	_check(not _popup_visible(), "event popup closes after a choice")

	# Phase 5: offline. Three hours away, then 30 hours away (capped at 24).
	await _offline_check(3.0 * 3600.0, "09_offline_3h", "Away 3h")
	await _offline_check(30.0 * 3600.0, "10_offline_cap", "capped at 24h")

	# Phase 6: import and export round-trip, then hard reset.
	await _export_import_check()
	await _hard_reset_check()

	# Phase 7: autosave and reload restore the exact state.
	_cheat("cash", 500.0)
	_play(12.0)
	G().running = false  # no real-time ticks between the snapshot and the reload
	G().save_now()
	var before: Dictionary = G().state.to_dict()
	# Round trip through the file: what the autosave wrote must load back as the same save.
	var loaded: Dictionary = S().load_data(SAVE)
	var a := _strip(before)
	var b := _strip(loaded)
	var at := 0
	while at < min(a.length(), b.length()) and a[at] == b[at]:
		at += 1
	_check(a == b, "autosave file loads back as the same state (diff at %d: [%s] vs [%s])" % [at, a.substr(maxi(at - 30, 0), 60), b.substr(maxi(at - 30, 0), 60)])
	await _boot()
	# Frames run after the reload tick the sim again, so only the restored totals are compared.
	_check(G().state.persist["stats"]["runs"] == before["persist"]["stats"]["runs"], "reload restores run count")
	_check(G().state.persist["stats"]["time"] >= float(before["persist"]["stats"]["time"]), "reload restores play time")

	# Phase 8: reduce motion. Pops and attention pulses must not start tweens.
	G().set_setting("reduce_motion", true)
	var probe := Control.new()
	_main.add_child(probe)
	probe.size = Vector2(40, 40)
	Fx.pop(probe)
	_check(not probe.has_meta("pop_tween") and probe.scale == Vector2.ONE, "reduce motion: pop is skipped")
	var dot := ColorRect.new()
	_main.add_child(dot)
	Fx.set_attention(dot, true)
	_check(not dot.has_meta("pulse") and dot.visible, "reduce motion: attention dot is steady")
	G().set_setting("reduce_motion", false)
	Fx.set_attention(dot, true)
	_check(dot.has_meta("pulse"), "motion on: attention dot pulses")
	probe.queue_free()
	dot.queue_free()

	# Phase 9: endings. Each ends the run; the overlay shows; the first new legacy frees it; a second ending shows again.
	for id in ["open_sourced", "rushed", "aligned"]:
		await _ending(id)

	# Phase 10: a run that ended before the game closed is shown on startup.
	G().state.run["run_over"] = "aligned"
	G().save_now()
	await _boot()
	_check(_ending_node() != null, "startup shows a finished run")
	await _shot("11_ending_startup_phone")
	_ending_node().call("_close")  # "Back to the lab": the queue frees and play carries on
	await _settle()
	_check(_ending_node() == null and not bool(_main.get("_modal_busy")), "back to the lab frees the ending and the queue")

	await _shots_all("12_final")


# ---------------------------------------------------------------- flow helpers

## Loads the real main scene and waits for it to build and start.
func _boot() -> void:
	G().running = false
	var err := change_scene_to_file(MAIN)
	_check(err == OK, "main scene loads")
	await process_frame
	await process_frame
	await process_frame
	_main = current_scene
	_check(_main != null and _main.get_script() != null, "main scene is running")


## Autoloads are looked up at runtime: identifiers do not resolve in a -s SceneTree script.
func G() -> Node:
	return root.get_node("/root/Game")


func C() -> Node:
	return root.get_node("/root/Content")


func S() -> Node:
	return root.get_node("/root/SaveSystem")


func _settle() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw


## After a deferred reload_current_scene (settings import/reset): picks up the new main scene.
func _reloaded() -> void:
	for i in 3:
		await process_frame
	_main = current_scene


## Advances the simulation by `seconds` in one-second steps (as G()._process would).
func _play(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(1.0, left)
		G().call("_dispatch", Sim.tick(G().state, dt))
		left -= dt
	_dismiss_events()


## Natural events open the popup during play; close them the way the player does (their first choice).
func _dismiss_events() -> void:
	for c in _main.get_children():
		if c.has_method("check_pending") and c.visible:
			c.call("_pick", 0)


func _cheat(cur: String, v: float) -> void:
	G().state.add_cur(cur, BigNum.from_float(v))


## Fills a layer's life so the reset is allowed, then performs it through the core.
func _reset(layer: int, shot_name: String) -> void:
	var ld = Sim.layer_def(G().state, layer)
	G().state.run["layers"][layer]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)
	var r: Dictionary = G().reset_layer(layer)
	_check(r.get("ok", false), "reset layer %d: %s" % [layer, str(r.get("reason", ""))])
	_play(20.0)
	await _settle()
	await _shot(shot_name + "_transition", 0.15)
	await _shots_all(shot_name)


## Waits for the shell's modal queue to empty (a transition or card in front of the panels), so tab shots show the panels.
func _wait_modals() -> void:
	for i in 600:
		if not bool(_main.get("_modal_busy")):
			return
		await process_frame
	_check(false, "modal queue drains before a screenshot")


func _shots_all(name: String) -> void:
	await create_timer(0.3).timeout  # HUD rates refresh on a 0.25s real-time tick
	await _wait_modals()
	for key in SIZES:
		DisplayServer.window_set_size(SIZES[key])
		await _settle()
		for id in TABS:
			if not _tab_visible(id):
				continue
			_main.call("_select", id)
			await _settle()
			await _shot("%s_%s_%s" % [name, key, id])
	DisplayServer.window_set_size(SIZES["desk"])
	await _settle()


func _shot(name: String, wait := 0.0) -> void:
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOTS, name])
	_shots += 1


func _tab_visible(id: String) -> bool:
	var tabs: Dictionary = _main.get("_tabs")
	return tabs.has(id) and (tabs[id] as Button).visible


func _call(panel_id: String, method: String, args: Array) -> void:
	var p: Node = _main.get("_panels")[panel_id]
	p.callv(method, args)


func _any_owned() -> bool:
	for d in C().get_all("producers"):
		if G().state.owned(d.id) > 0:
			return true
	return false


## Presses a producer row's own Buy button.
func _press_buy(id: String) -> void:
	var rows: Dictionary = _main.get("_panels")["producers"].get("_rows")
	(rows[id]["buy"] as Button).pressed.emit()


func _first_id(kind: String) -> String:
	var all: Array = C().get_all(kind)
	return all[0].id if not all.is_empty() else ""


func _popup_check() -> void:
	for c in _main.get_children():
		if c.has_method("check_pending"):
			c.check_pending()


func _popup_visible() -> bool:
	for c in _main.get_children():
		if c.has_method("check_pending"):
			return c.visible
	return false


func _click_event_choice(i: int) -> void:
	for c in _main.get_children():
		if c.has_method("check_pending"):
			c.call("_pick", i)


func _ending_node() -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.has_method("show_ending"):
			return c
	return null


func _ending(id: String) -> void:
	G().state.run["run_over"] = id
	G().ending_reached.emit(id)
	await _settle()
	var node := _ending_node()
	_check(node != null and node.visible, "ending %s shows" % id)
	await _shot("13_ending_%s" % id)
	node.call("_new_run")
	await _settle()
	_check(_ending_node() == null, "ending %s frees itself after a new legacy" % id)


# ---------------------------------------------------------------- tooltips

## Hover and long-press through real input events; tooltip shots and checks at both sizes.
func _tooltip_phase() -> void:
	G().running = false
	_cheat("cash", 1e6)
	_cheat("compute", 1e4)
	var id := _first_id("producers")
	for key in SIZES:
		DisplayServer.window_set_size(SIZES[key])
		await _settle()

		await _hover(_main.get("_cash")["box"])
		_check(_tip_showing() and _tip_text().contains("Cash"), "%s: HUD cash chip shows a tip" % key)
		_check(_inside_view(), "%s: HUD tip inside the visible rect" % key)
		await _shot("tip_hud_%s" % key)

		_main.call("_select", "producers")
		await _settle()
		var row: Control = _panel("producers").get("_rows")[id]["row"]
		await _reveal(row)
		await _hover(row)
		_check(_tip_showing() and _tip_title() == str(C().get_def("producers", id).title), "%s: producer row shows its tip" % key)
		_check(_inside_view(), "%s: producer tip inside the visible rect" % key)
		await _shot("tip_producer_%s" % key)

		G().state.set_cur("compute", BigNum.from_float(137.0))
		_main.call("_select", "training")
		await _settle()
		var opt: Control = _panel("training").get("_cards")["fine_tune"]["btn"]
		await _reveal(opt)
		await _hover(opt)
		_check(_tip_showing() and _tip_text().contains("Needs 400.00 compute for Fine-tune"), "%s: disabled training option says what it needs" % key)
		_check(_tip_showing() and _inside_view(), "%s: disabled training tip shows inside the view" % key)
		await _shot("tip_training_disabled_%s" % key)
		G().state.set_cur("compute", BigNum.from_float(1e4))
		await create_timer(0.3).timeout  # the panel's refresh timer re-enables the option
		await _hover(opt)
		_check(_tip_showing() and _tip_text().contains("Minimum spend"), "%s: enabled training tip explains the run" % key)
		await _shot("tip_training_enabled_%s" % key)

		_main.call("_select", "generation")
		await _settle()
		var tree = _panel("generation").get("_tree")
		var rbuy: Control = tree.get("_rows")[_first_id("research")]["buy"]
		await _reveal(rbuy)
		await _hover(rbuy)
		_check(_tip_showing() and _tip_text().contains("Cost"), "%s: research node shows its tip" % key)
		await _shot("tip_research_%s" % key)

		_main.call("_select", "benchmarks")
		await _settle()
		var brow: Dictionary = _panel("benchmarks").get("_rows")[_first_id("benchmarks")]
		var slot: Control = (brow["badge"] as Control).get_parent()
		await _reveal(slot)
		await _hover(slot)
		_check(_tip_showing(), "%s: benchmark badge shows its tip" % key)
		await _shot("tip_benchmark_%s" % key)
		await _leave()

	# Long-press on Buy opens the tip and releasing it buys nothing; a quick tap still buys.
	_main.call("_select", "producers")
	await _settle()
	var buy: Button = _panel("producers").get("_rows")[id]["buy"]
	await _reveal(buy)
	var at := _center(buy)
	var before: int = G().state.owned(id)
	_touch(at, true)
	await create_timer(0.6).timeout
	await _settle()
	_check(_tip_showing(), "long-press on Buy opens the tip")
	_touch(at, false)
	await _settle()
	_check(G().state.owned(id) == before, "releasing a long-press on Buy does not buy")
	_check(not _tip_showing(), "releasing a long-press hides the tip")
	_touch(at, true)
	await create_timer(0.05).timeout
	_touch(at, false)
	await _settle()
	_check(G().state.owned(id) > before, "quick tap on Buy still buys")

	# Reduce motion: the tip appears at full opacity at once. Motion on: it fades in.
	await _leave()
	G().set_setting("reduce_motion", true)
	await _hover_until_shown(_main.get("_cash")["box"])
	_check(_tip_alpha() == 1.0, "reduce motion: tip is opaque immediately")
	await _leave()
	G().set_setting("reduce_motion", false)
	await _hover_until_shown(_main.get("_cash")["box"])
	_check(_tip_alpha() < 1.0, "motion on: tip fades in")
	await _leave()
	DisplayServer.window_set_size(SIZES["desk"])
	await _settle()


func _panel(id: String) -> Node:
	return _main.get("_panels")[id]


func _tip() -> Tip:
	for c in _main.get_children():
		if c is Tip:
			return c
	return null


func _tip_showing() -> bool:
	var t := _tip()
	return t != null and (t.get("_panel") as Control).visible


func _tip_title() -> String:
	return (_tip().get("_title") as Label).text


func _tip_text() -> String:
	var t := _tip()
	return "%s\n%s" % [(t.get("_title") as Label).text, (t.get("_body") as Label).text]


func _tip_alpha() -> float:
	return (_tip().get("_panel") as Control).modulate.a


## The tip's panel must sit fully inside the visible rect (canvas coordinates, same space as the panel).
func _inside_view() -> bool:
	var r := (_tip().get("_panel") as Control).get_global_rect()
	return root.get_visible_rect().encloses(r)


## Window position of a control's centre, for input events.
func _center(c: Control) -> Vector2:
	return root.get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)


func _touch(p: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = p
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _leave() -> void:
	_move(Vector2(-50, -50))
	await _settle()


func _hover_until_shown(c: Control) -> void:
	# Leave first so a tip still open for another control is closed and cannot satisfy the wait.
	_move(Vector2(-50, -50))
	await process_frame
	await process_frame
	_move(_center(c))
	for i in 120:
		if _tip_showing():
			return
		await process_frame
	print("DEV DIAG: hover missed at %s, hovered=%s" % [str(_center(c)), str(root.gui_get_hovered_control())])


func _hover(c: Control) -> void:
	await _hover_until_shown(c)
	await _settle()


## Scrolls the enclosing ScrollContainer so the control is on screen before it is hovered.
func _reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(c)
	await _settle()


# ---------------------------------------------------------------- offline, save and reset

func _offline_check(away: float, shot_name: String, needle: String) -> void:
	G().state.persist["saved_at"] = Time.get_unix_time_from_system() - away
	S().save(G().state.to_dict(), SAVE)
	await _boot()
	await _settle()
	var found := _text_has(_main, needle)
	_check(found, "offline card shows '%s'" % needle)
	await _shot(shot_name)
	# Dismiss the card so later steps can click.
	for c in _main.get_children():
		if c.has_method("show_offline"):
			c.call("_close")


func _text_has(node: Node, needle: String) -> bool:
	if (node is Label or node is Button) and needle in str(node.text):
		return true
	for c in node.get_children():
		if _text_has(c, needle):
			return true
	return false


func _export_import_check() -> void:
	_play(5.0)
	G().save_now()
	var cash_before: String = G().state.cur("cash").format()
	_call("settings", "_export", [])
	var clip := DisplayServer.clipboard_get()
	_check(clip.contains("\"state\""), "export copies the save to the clipboard")
	G().state.set_cur("cash", BigNum.from_float(1.0))
	_main.get("_panels")["settings"].get("_paste").text = clip
	_call("settings", "_import", [])
	await _reloaded()
	_check(G().state.cur("cash").format() == cash_before, "import restores the exported save")
	_main.get("_panels")["settings"].get("_paste").text = "{not json"
	_call("settings", "_import", [])
	_check(_text_has(_main, "Not a valid save"), "import rejects bad text without changing progress")
	await _shot("14_settings_import_desk")


func _hard_reset_check() -> void:
	_call("settings", "_hard_reset", [])
	await _reloaded()
	_check(G().state.cur("compute").is_zero() and G().state.resets(1) == 0, "hard reset clears progress")
	_check(G().state.persist["stats"]["runs"] == 1, "hard reset starts a fresh save")
	# A fresh save replays the intro over the shell. Nothing ticks behind it; Skip ends it and marks it seen.
	var intro = _main.get("_intro")
	_check(intro != null and not G().running, "hard reset replays the intro with the sim paused")
	await _shot("14_intro_open")
	intro.call("_finish")
	await create_timer(1.5).timeout
	await _settle()
	_check(_main.get("_intro") == null and G().state.persist["intro_seen"], "skipping the intro marks it seen")
	_check(_main.get("_modal_busy") == false, "modal queue is free after the intro")


## Save data without the wall-clock field, so two snapshots can be compared.
func _strip(d: Dictionary) -> String:
	var copy := d.duplicate(true)
	copy["persist"].erase("saved_at")
	# Through JSON both ways: the file turns every number into a float.
	var json := JSON.new()
	json.parse(JSON.stringify(copy))
	return JSON.stringify(json.data)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("DEV OK: %s" % what)
	else:
		print("DEV FAIL: %s" % what)
		_fails.append(what)
