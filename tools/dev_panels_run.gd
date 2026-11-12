extends Node
## Dev harness for the progression panels and the ending screen. Not shipped.
## Run (needs a window, so screenshots render):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/dev_panels.gd
## Instances each panel at 340x600 and 900x500, drives the game through the panels' own buttons and sliders,
## writes PNGs to SHOTS and prints "DEV OK" or "DEV FAIL: ..." lines. Exit code 0 only on DEV OK.
##
## Cheats (dev only, every one is marked CHEAT): writing currencies, layer life, owned counts and flags
## directly, because the real game needs hours of play to reach these states. Everything the player can
## do is clicked, not called: buttons are pressed and sliders set through their own signals.
## Resets, hires, research, automation, legacy, challenges and rival launches all run through the core.

# Screenshots go to $SL_SHOTS if set, else a dev_shots folder in the OS temp dir.
var SHOTS := (OS.get_environment("SL_SHOTS") if OS.get_environment("SL_SHOTS") != "" else OS.get_temp_dir().path_join("scaling-laws-dev-shots")).path_join("panels")
const SIZES := [Vector2i(340, 600), Vector2i(900, 500)]
const PANELS := ["training", "funding", "generation", "paradigm", "singularity"]
const GUTTER := 12

var _views: Dictionary = {}          # "name@WxH" -> {vp: SubViewport, panel: Control}
var _fails: Array[String] = []
var _endings_seen: Array[String] = []
var _challenges_abandoned := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS)
	Game.save_path = "user://dev_panels_save.json"   # never touch the player's save
	Game.state.persist["intro_seen"] = true          # skip the first-run intro
	Game.running = false
	Game.ending_reached.connect(func(id: String) -> void: _endings_seen.append(id))
	Game.challenge_abandoned.connect(func(_id: String) -> void: _challenges_abandoned += 1)
	_make_views()
	await _settle()

	# Phase 1: a little income on layer 0, then a training run through the panel.
	_cheat_add("cash", 1e4)
	_cheat_add("compute", 1e6)
	for d in Content.get_all("producers"):
		Game.buy_producer(d.id, -1)
	_tick(120.0, 5.0)
	await _press_each("training", "Start Fine-tune")
	_tick(61.0)
	_check(Game.state.persist["stats"]["trainings"] >= 1, "a training run finished")

	# Phase 2: Funding Round (layer 1), then hiring with the equity it paid out.
	_cheat_life(1)
	await _reset("funding", 1)
	_cheat_add("equity", 200.0)
	await _press_each("funding", "Hire 1")
	await _press_each("funding", "Hire 5")
	_check(_staff_total() >= 1, "at least one hire")
	_cheat_add("compute", 1e6)
	await _press_each("training", "Start Standard run")
	_tick(61.0)

	# Phase 3: Model Generation (layer 2): alignment slider, presets, research.
	_cheat_life(2)
	await _reset("generation", 2)
	_cheat_add("insights", 1e6)
	await _set_slider("generation", 0.2)
	await _press_each("generation", "%")
	await _set_slider("generation", 0.2)
	_tick(30.0)
	_check(Game.state.run["layers"][0]["debt"] > 0.0, "debt accrues below safe alignment")
	for _pass in 6:
		await _press_each("generation", "Buy for")
	_check(Game.state.run["layers"][2]["research"].size() >= 2, "research bought")

	# Phase 4: Paradigm Shift (layer 3): automation, energy and data.
	_cheat_life(3)
	await _reset("paradigm", 3)
	_cheat_add("breakthroughs", 100.0)
	_cheat_add("energy", 50.0)
	_cheat_add("data", 20.0)
	_cheat_add("compute", 1e6)
	for _pass in 4:
		await _press_each("paradigm", "Buy for")
	_check(Game.state.persist["automation"].size() >= 1, "automation bought")
	await _press_each("training", "Start Frontier push")
	_tick(61.0)

	# Phase 5: Singularity (layer 4): legacy perks, challenges, rivals.
	_cheat_life(4)
	await _reset("singularity", 4)
	_cheat_add("legacy", 100.0)
	for _pass in 3:
		await _press_each("singularity", "Buy for")
	_check(Game.state.persist["legacy_perks"].size() >= 1, "legacy perk bought")
	for i in 6:
		var p := _p("singularity")
		if _enabled_buttons(p, "Enter challenge").is_empty() and Game.state.run["layers"][4]["challenge"].is_empty():
			break
		if Game.state.run["layers"][4]["challenge"].is_empty():
			await _press_first("singularity", "Enter challenge")
		if i == 1:
			await _press_first("singularity", "Abandon challenge")
			await _press_first("singularity", "Enter challenge")
		var c: Dictionary = Game.state.run["layers"][4]["challenge"]
		if not c.is_empty():
			_tick(float(Content.get_def("challenges", c["id"]).duration), 30.0)
	_check(Game.state.run["challenges_done"].size() >= 1, "a challenge completed")
	_check(_challenges_abandoned >= 1, "a challenge was abandoned")
	_tick(130000.0, 200.0)   # nimbus launches at 36 h on the clock
	for id in ["aurora", "helix", "kestrel", "monolith", "nimbus"]:
		_check(bool(Game.state.run["flags"].get("rival_%s_launched" % id, false)), "rival %s launched" % id)

	# Re-populate after the last reset, which wipes everything below layer 4.
	_cheat_add("compute", 1e6)
	_cheat_add("insights", 1e6)
	_cheat_add("equity", 200.0)
	# Training may already be running: the bought auto_train runs it on every tick.
	for _pass in 4:
		await _press_each("generation", "Buy for")
	await _settle()
	await _shoot_all("populated")

	for n in PANELS:
		_check(_p(n).is_unlocked(), "%s panel unlocked" % n)

	# Phase 6: three endings through the core. Each run gets its own AGI push.
	await _drive_ending_aligned()
	await _drive_ending_open_sourced()
	await _drive_ending_rushed()

	_check(_endings_seen == ["aligned", "open_sourced", "rushed"], "endings in order: %s" % str(_endings_seen))
	_check_layout()
	await _shoot_all("final")

	if _fails.is_empty():
		print("DEV OK")
		get_tree().quit(0)
	else:
		for f in _fails:
			printerr("DEV FAIL: " + f)
		get_tree().quit(1)


# ---------------------------------------------------------------- endings

func _drive_ending_aligned() -> void:
	# Aligned needs alignment >= 70%. The slider is still unlocked: this run has its resets.
	await _set_slider("generation", 0.8)
	_cheat_agi()
	_tick(1.0)
	await _settle()
	_check(_endings_seen.has("aligned"), "aligned ending reached")
	await _shoot_all("ending_aligned", "ending@")
	# Dismiss from the overlay's own button, then start a new legacy from the Singularity panel.
	var ov := _ending_view()
	await _press_first("ending", "Back to the lab")
	await _settle()
	_check(not is_instance_valid(ov), "overlay dismissed")
	_restore_ending_views()
	await _press_first("singularity", "Start a new legacy")
	_check(Game.state.run["run_over"] == "", "new legacy started")
	_check(Game.state.persist["stats"]["runs"] >= 2, "run counter advanced")


func _drive_ending_open_sourced() -> void:
	# CHEAT: put the Aurora launch event on the pending slot (its flag check is skipped), then pick the real choice.
	Game.state.run["layers"][0]["pending"] = "rival_launch_aurora"
	var r: Dictionary = Game.resolve_event(1)   # "Open-source our weights" sets flag open_sourced
	_check(r.get("ok", false), "resolve open-source event")
	_cheat_agi()
	_tick(1.0)
	await _settle()
	_check(_endings_seen.has("open_sourced"), "open_sourced ending reached")
	await _shoot_all("ending_open_sourced", "ending@")
	var ov := _ending_view()
	await _press_first("ending", "Back to the lab")
	await _settle()
	_check(not is_instance_valid(ov), "overlay dismissed (open-sourced)")
	_restore_ending_views()


func _drive_ending_rushed() -> void:
	# The fresh run has no resets, so the slider stays at its default: below 70%, no flag: rushed.
	await _press_first("singularity", "Start a new legacy")
	_cheat_agi()
	_tick(1.0)
	await _settle()
	_check(_endings_seen.has("rushed"), "rushed ending reached")
	await _shoot_all("ending_rushed", "ending@")
	await _press_first("ending", "Start a new legacy")
	await _settle()
	_restore_ending_views()
	_check(Game.state.run["run_over"] == "", "new legacy after rushed")


# ---------------------------------------------------------------- harness: views

func _make_views() -> void:
	for sz in SIZES:
		for n in PANELS:
			var vp := _make_vp(sz)
			var p: Control = load("res://src/ui/panels/%s.tscn" % n).instantiate()
			vp.add_child(p)
			_views["%s@%dx%d" % [n, sz.x, sz.y]] = {"vp": vp, "panel": p}
		var ev := _make_vp(sz)
		var e: Control = load("res://src/ui/ending_screen.tscn").instantiate()
		ev.add_child(e)
		_views["ending@%dx%d" % [sz.x, sz.y]] = {"vp": ev, "panel": e}


func _make_vp(sz: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)
	return vp


## The 340x600 instance of a panel: the one the script clicks (the 900x500 instance refreshes from the same state).
func _p(n: String) -> Control:
	return _views["%s@340x600" % n]["panel"]


func _ending_view() -> Control:
	return _views["ending@340x600"]["panel"]


## The ending overlay frees itself on "Back to the lab"; give the harness a fresh one for later shots.
func _restore_ending_views() -> void:
	for sz in SIZES:
		var v: Dictionary = _views["ending@%dx%d" % [sz.x, sz.y]]
		if is_instance_valid(v["panel"]):
			continue
		var e: Control = load("res://src/ui/ending_screen.tscn").instantiate()
		(v["vp"] as SubViewport).add_child(e)
		v["panel"] = e


func _settle() -> void:
	await get_tree().create_timer(0.3).timeout   # panels refresh on a 0.25 s timer
	await get_tree().process_frame


# ---------------------------------------------------------------- harness: clicks

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _enabled_buttons(p: Node, contains: String) -> Array:
	var out: Array = []
	for n in _walk(p):
		if n is Button and contains in n.text and not n.disabled:
			out.append(n)
	return out


## Presses every button that is enabled when the call starts, skipping any that a previous press disabled.
func _press_each(n: String, contains: String) -> void:
	await _settle()   # cheats and ticks change state without a signal; let the panels refresh
	var p := _p(n)
	var todo := _enabled_buttons(p, contains)
	if todo.is_empty():
		print("DEV: %s: no enabled '%s' button (%s)" % [n, contains, _result(p)])
	for b in todo:
		if b.disabled:
			continue
		var label: String = b.text
		b.pressed.emit()
		await get_tree().process_frame
		print("DEV: %s click '%s' -> %s" % [n, label, _result(p)])


func _press_first(n: String, contains: String) -> void:
	await _settle()   # cheats and ticks change state without a signal; let the panels refresh
	var p := _p(n) if n != "ending" else _ending_view()
	var todo := _enabled_buttons(p, contains)
	if todo.is_empty():
		print("DEV: %s: no enabled '%s' button" % [n, contains])
		return
	var label: String = todo[0].text   # read before the press: the button may belong to an overlay that frees itself
	todo[0].pressed.emit()
	await get_tree().process_frame
	print("DEV: %s click '%s' -> %s" % [n, label, _result(p)])


## The result line text: PanelBase.result_line, or the ending screen's _result.
func _result(p) -> String:
	if not is_instance_valid(p):
		return "(closed)"
	if p.get("result_line") != null:
		return str(p.result_line.text)
	if p.get("_result") != null:
		return str(p._result.text)
	return "-"


func _reset(n: String, k: int) -> void:
	await _settle()   # cheats and ticks change state without a signal; let the panels refresh
	var p := _p(n)
	var card: PanelResetCard = null
	for c in _walk(p):
		if c is PanelResetCard:
			card = c
	if card == null:
		_fail("%s: no reset card" % n)
		return
	var btn: Button = null
	var dlg: ConfirmationDialog = null
	for c in _walk(card):
		if c is Button and c.text.begins_with("Run "):
			btn = c
		if c is ConfirmationDialog:
			dlg = c
	if btn == null or dlg == null:
		_fail("layer %d: reset button or dialog missing" % k)
		return
	if btn.disabled:
		_fail("layer %d reset disabled: %s" % [k, btn.text])
		return
	btn.pressed.emit()          # opens the confirmation
	await get_tree().process_frame
	print("DEV: %s dialog '%s'" % [n, dlg.dialog_text])
	dlg.confirmed.emit()        # the dialog's OK
	await get_tree().process_frame
	print("DEV: %s reset -> %s" % [n, _result(p)])
	_check(Game.state.resets(k) >= 1, "layer %d reset ran" % k)


func _set_slider(n: String, v: float) -> void:
	await _settle()   # cheats and ticks change state without a signal; let the panels refresh
	var p := _p(n)
	for c in _walk(p):
		if c is HSlider:
			c.value = v           # emits value_changed, the panel calls Game.set_slider
			await get_tree().process_frame
			print("DEV: %s slider -> %.2f: %s" % [n, v, _result(p)])
			return
	_fail("%s: no alignment slider" % n)


# ---------------------------------------------------------------- harness: state

## Advances the core in steps of `step` seconds, dispatching events the way Game._process does.
func _tick(seconds: float, step: float = 1.0) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(step, left)
		Game._dispatch(Sim.tick(Game.state, dt))
		left -= dt


## CHEAT: adds currency directly.
func _cheat_add(cur: String, amount: float) -> void:
	Game.state.add_cur(cur, BigNum.from_float(amount))


## CHEAT: sets layer k's life to four times its threshold, so the reset gains 2.
func _cheat_life(k: int) -> void:
	var ld = Sim.layer_def(Game.state, k)
	Game.state.run["layers"][k]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)


## CHEAT: meets every AGI stage condition at once, so one tick walks the whole road to the ending check.
func _cheat_agi() -> void:
	var s: GameState = Game.state
	s.run["layers"][2]["best"] = 5.0
	s.run["layers"][0]["owned"]["server_rack"] = 20
	s.set_cur("compute", BigNum.from_float(1e31))
	s.set_cur("energy", BigNum.from_float(100.0))


func _staff_total() -> int:
	var n := 0
	for v in Game.state.run["layers"][1]["staff"].values():
		n += int(v)
	return n


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
	else:
		print("DEV: ok: " + what)


func _fail(msg: String) -> void:
	_fails.append(msg)


# ---------------------------------------------------------------- layout and screenshots

## Pages every panel and the ending overlay at both sizes: scrolls the page and saves one PNG per screen.
func _shoot_all(tag: String, only: String = "") -> void:
	for key in _views.keys():
		if not key.begins_with(only):
			continue
		var v: Dictionary = _views[key]
		var vp: SubViewport = v["vp"]
		var sc := _scroll_of(v["panel"])
		if sc == null:
			continue
		var h := vp.size.y
		var content := sc.get_v_scroll_bar().max_value
		var pages := maxi(1, ceili(content / float(h)))
		for i in pages:
			sc.scroll_vertical = i * h
			await _settle()
			var img := vp.get_texture().get_image()
			img.save_png("%s/%s_%s_%d.png" % [SHOTS, tag, key.replace("@", "_"), i])
		sc.scroll_vertical = 0


## True for nodes inside a popup window (the reset dialog's own OK/Cancel), which the layout rules don't cover.
func _in_window(n: Node) -> bool:
	var q: Node = n
	while q != null:
		if q is Window:
			return true
		q = q.get_parent()
	return false


func _scroll_of(p: Node) -> ScrollContainer:
	for c in _walk(p):
		if c is ScrollContainer:
			return c
	return null


func _check_layout() -> void:
	for key in _views.keys():
		var v: Dictionary = _views[key]
		var vp: SubViewport = v["vp"]
		var sc := _scroll_of(v["panel"])
		if sc == null:
			continue
		var page: Control = sc.get_child(0)
		var need := page.get_combined_minimum_size().x
		_check(need <= float(vp.size.x), "%s: content min width %d fits %d" % [key, int(need), vp.size.x])
		for n in _walk(v["panel"]):
			if n is Button and not _in_window(n):
				_check(n.custom_minimum_size.y >= 28.0, "%s: button '%s' touch height %d" % [key, n.text, int(n.custom_minimum_size.y)])
