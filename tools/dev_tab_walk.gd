extends SceneTree
## Dev: walks every visible tab at four phone/desktop sizes. For each tab it shoots the top, middle and bottom of the
## panel's scroll page and joins the three into one montage PNG. Runs a clipping check on every frame and exits 1 when
## anything clips, overflows its container or breaks mid-word:
##   $GODOT --path . -s tools/dev_tab_walk.gd -- <out_dir> fresh|late [inject-overflow]
## inject-overflow adds a 400 px control to the shell; the run must then exit 1 (self-test of the width check).
## "late" gives a mid-to-late tower (currencies, resets, producers). Never touches the real save. Windowed.

const SIZES := [Vector2i(360, 640), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1280, 720)]
const SCROLL_POS := [0.0, 0.5, 1.0]
## Overflow tolerance in logical px (text metrics are rounded).
const EPS := 1.0

var _problems := 0
var _checked := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var mode: String = args[1] if args.size() > 1 else "fresh"
	var inject := args.size() > 2 and args[2] == "inject-overflow"  # self-test: a 400 px control must fail the run
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var g = root.get_node("/root/Game")
	g.save_path = "user://dev_tab_walk_%s.json" % mode
	root.get_node("/root/SaveSystem").delete(g.save_path)
	g.state.persist["intro_seen"] = true
	g.state.persist["saved_at"] = Time.get_unix_time_from_system()
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	var main: Node = current_scene
	var st = g.state
	if mode == "full":
		_populate(g, st)
	if mode == "late" or mode == "full":
		st.set_cur("cash", BigNum.from_float(1e9))
		st.set_cur("compute", BigNum.from_float(1e9))
		for c in ["equity", "insights", "breakthroughs", "data", "energy", "legacy"]:
			st.set_cur(c, BigNum.from_float(1e4))
		var lifetime: Array = st.persist["lifetime_resets"]
		for k in lifetime.size():
			lifetime[k] = 2
		for k in st.run["resets_done"].size():
			st.run["resets_done"][k] = 2  # unlocks every layer's tab (PanelResetCard.is_layer_unlocked)
		for id in ["intern_laptop", "cloud_gpus", "server_rack", "data_centre", "custom_silicon"]:
			Sim.buy_producer(st, id, -1)
	g.running = false
	if inject:
		var wide := Control.new()
		wide.custom_minimum_size = Vector2(400, 4)
		main.get("_column").add_child(wide)
	await create_timer(0.5).timeout
	var tabs: Dictionary = main.get("_tabs")
	var panels: Dictionary = main.get("_panels")
	for s in SIZES:
		DisplayServer.window_set_size(s)
		await create_timer(1.0).timeout
		var vp: Vector2 = root.get_visible_rect().size
		print("== %s %dx%d (logical %dx%d)" % [mode, s.x, s.y, vp.x, vp.y])
		for id in tabs.keys():
			var b: Button = tabs[id]
			if not b.is_visible_in_tree():
				continue
			b.pressed.emit()
			await create_timer(0.4).timeout
			var tag := "%s@%dx%d" % [id, s.x, s.y]
			_checked += 1
			_check(main, vp, tag)
			var frames: Array[Image] = []
			var sc := _scroll_of(panels.get(id))
			for f in (SCROLL_POS if sc != null else [0.0]):
				if sc != null:
					sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value * f)
					await process_frame
					await process_frame
				await process_frame  # frame_post_draw never fired while the window was occluded: the run hung
				frames.append(root.get_texture().get_image())
			_save_montage(frames, "%s/%s_%dx%d_%s.png" % [out, mode, s.x, s.y, id])
		await _overlay_walk(main, vp, out, mode, s)
		print("tabs shown: %s" % ", ".join(tabs.keys().filter(func(k): return (tabs[k] as Button).is_visible_in_tree())))
	print("CHECK items=%d problems=%d" % [_checked, _problems])
	quit(1 if _problems > 0 else 0)


func _overlay_walk(main: Node, vp: Vector2, out: String, mode: String, size: Vector2i) -> void:
	var g = root.get_node("/root/Game")
	g.state.persist["records"]["offline_seconds"] = 90500.0
	g.state.persist["records"]["deployment_burst_cash"] = BigNum.from_float(1e12).to_json()
	main.open_stats()
	await _capture(main, vp, out, mode, size, "overlay_stats")
	var stats_scroll := _find_scroll(main.get("_stats"))
	stats_scroll.scroll_vertical = int(stats_scroll.get_v_scroll_bar().max_value)
	await process_frame
	await _capture(main, vp, out, mode, size, "overlay_stats_bottom")
	stats_scroll.scroll_vertical = 0
	main.get("_stats").hide()

	var reveal = main.get("_reveal_card")
	g.state.persist["stats"]["time"] = 1300.0
	g.state.persist["seen_reveals"].erase("training")
	reveal.call("_open", "training")
	await _capture(main, vp, out, mode, size, "overlay_reveal")
	reveal.call("_close")

	var notices = main.get("_notices")
	notices.show_offline({"away": 90000.0, "capped": true, "cash": BigNum.from_float(1234),
		"compute": BigNum.from_float(5678), "events": [{"kind": "training_done"}, {"kind": "reset"}]})
	await _capture(main, vp, out, mode, size, "overlay_offline")
	notices.dismiss()

	main.call("play_intro")
	await create_timer(0.7).timeout
	main.get("_intro").call("_end_typing")
	await _capture(main, vp, out, mode, size, "overlay_intro")
	main.get("_intro").call("_finish")
	await create_timer(0.8).timeout
	await process_frame

	for key in ["funding", "singularity"]:
		var card = main.get("_panels")[key].get("_card")
		card.call("_confirm_dialog")
		await process_frame
		await _capture(main, vp, out, mode, size, "overlay_reset_%s" % key)
		card.get("_dialog").hide()

	for ending in ["aligned", "rushed", "open_sourced"]:
		var scene: Node = load("res://src/ui/ending_screen.tscn").instantiate()
		main.add_child(scene)
		scene.call("show_ending", ending)
		await process_frame
		await _capture(main, vp, out, mode, size, "overlay_ending_%s" % ending)
		scene.queue_free()
		await process_frame


func _capture(main: Node, vp: Vector2, out: String, mode: String, size: Vector2i, tag: String) -> void:
	await process_frame
	_checked += 1
	_check(main, vp, "%s@%dx%d" % [tag, size.x, size.y])
	root.get_texture().get_image().save_png("%s/%s_%dx%d_%s.png" % [out, mode, size.x, size.y, tag])


## "full": everything unlocked and running, so every tab, row and overlay has content. CHEATS (dev only, never saved):
## currencies and layer resets are written directly, the rest goes through the Game API (buys, launches, runs, choices).
func _populate(g, st) -> void:
	var content = root.get_node("/root/Content")
	st.run["layers"][0]["event_timer"] = 1e9   # no event popups: their queued modals would cover the panels in the walk
	for c in ["cash", "compute"]:
		st.set_cur(c, BigNum.from_float(1e12))
	for c in ["equity", "insights", "breakthroughs", "data", "energy", "legacy"]:
		st.set_cur(c, BigNum.from_float(1e6))
	for k in st.run["resets_done"].size():
		st.run["resets_done"][k] = 2
	var lifetime: Array = st.persist["lifetime_resets"]   # Desk.unlocked reads lifetime_resets[1]
	for k in lifetime.size():
		lifetime[k] = 2
	for d in content.get_all("producers"):
		g.buy_producer(d.id, -1)
	for d in content.get_all("upgrades"):
		g.buy_upgrade(d.id)
	for d in content.get_all("automation"):
		if d.id != "auto_review":   # auto_review resolves each paper the moment it arrives, which leaves the desk empty
			g.buy_automation(d.id)
	for d in content.get_all("research"):
		g.research(d.id)
		g.research(d.id)
	var legacy_keys: Dictionary = load("res://src/ui/panels/singularity.gd").get_script_constant_map()["LEGACY_KEYS"]
	for key in legacy_keys:
		for _n in 2:
			g.buy_legacy(key)
	# Ten simulated hours in 10 s steps: desk papers appear, runs finish, launches come off cooldown.
	for _i in 3600:
		g._dispatch(Sim.tick(st, 10.0))
	for d in content.get_all("moonshots"):
		g.start_moonshot(d.id)
	g.start_challenge("compute_cap_hearing")
	# AGI: stage 3 is unlocked with one choice made, so the road now waits on a choice and the rivals race.
	st.run["stage"] = 3
	st.run["agi_choices"] = ["full"]
	for _i in 720:
		g._dispatch(Sim.tick(st, 10.0))
	print("populate: desk=%d launches_ready=%d upgrades_owned=%d" % [
		(Desk.state(st)["slots"] as Array).size(), 0, Upgrades.owned_ids(st).size()])


## The first visible vertical scroll page of a panel: what the top/middle/bottom shots scroll through.
func _scroll_of(panel: Variant) -> ScrollContainer:
	if not (panel is Control):
		return null
	return _find_scroll(panel as Node)


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n as Control).is_visible_in_tree() and (n as ScrollContainer).get_v_scroll_bar().max_value > 0.0:
		return n
	for c in n.get_children():
		var f := _find_scroll(c)
		if f != null:
			return f
	return null


## Joins the frames side by side into one PNG (one column per scroll position).
func _save_montage(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		return
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var sheet := Image.create(w * frames.size() + 4 * (frames.size() - 1), h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1, 0, 1))
	for i in frames.size():
		var f := frames[i]
		f.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(f, Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(i * (w + 4), 0))
	sheet.save_png(path)


## Clipping and overflow checks over every visible control under n. Each problem prints one line:
##   CLIP-H  a label/button whose text is wider than its box (clip_text cuts it off)
##   CLIP-V  a wrapped label whose text is taller than its box
##   BREAK   a word wider than its label (it would split mid-word)
##   MINW    a control whose minimum width is larger than the space its container gives it
##   OFF     a control that sticks out of the logical viewport (top/bottom, outside scroll pages)
##   OFF-W   a control that sticks out past the left or right edge (checked inside scroll pages too)
func _check(n: Node, vp: Vector2, tag: String) -> void:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).size.x > 0.0:
		var c := n as Control
		var r := c.get_global_rect()
		# Vertical overflow inside a scroll page is expected (that is what scrolling is for); sideways never is.
		# Width is checked everywhere, scroll pages included: nothing may stick out past the viewport's left or right edge.
		if r.end.x > vp.x + EPS or r.position.x < -EPS:
			_problem("OFF-W", c, tag, "rect=%s vp=%.0f" % [str(r), vp.x])
		if not _in_scroll(c) and (r.end.y > vp.y + EPS or r.position.y < -EPS):
			_problem("OFF", c, tag, "rect=%s" % str(r))
		if c is Label:
			_check_label(c as Label, tag)
		elif c is Button:
			_check_button(c as Button, tag)
		if not (c is Label or c is Button) and c.get_combined_minimum_size().x > c.size.x + EPS and c.size.x > 0.0:
			_problem("MINW", c, tag, "min=%.0f have=%.0f" % [c.get_combined_minimum_size().x, c.size.x])
	for child in n.get_children():
		_check(child, vp, tag)


func _check_label(l: Label, tag: String) -> void:
	if l.text == "":
		return
	var font := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		for word in l.text.replace("\n", " ").split(" ", false):
			if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x + EPS:
				_problem("BREAK", l, tag, "word '%s' wider than %.0f" % [word, l.size.x])
				break
		var h := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, l.size.x, fs).y
		if h > l.size.y + EPS:
			_problem("CLIP-V", l, tag, "text %.0f tall, box %.0f" % [h, l.size.y])
	elif l.clip_text:
		var w := _widest_line(font, l.text, fs)
		if w > l.size.x + EPS:
			_problem("CLIP-H", l, tag, "'%s' needs %.0f, box %.0f" % [l.text, w, l.size.x])


func _check_button(b: Button, tag: String) -> void:
	if b.text == "" or not b.clip_text:
		return
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var sb := b.get_theme_stylebox("normal")
	var pad: float = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	var icon_w: float = (b.icon.get_width() + b.get_theme_constant("h_separation")) if b.icon != null else 0.0
	var w: float = _widest_line(font, b.text, fs) + pad + icon_w
	if w > b.size.x + EPS:
		_problem("CLIP-H", b, tag, "'%s' needs %.0f, button %.0f" % [b.text, w, b.size.x])


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _widest_line(font: Font, text: String, fs: int) -> float:
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


func _problem(kind: String, c: Control, tag: String, detail: String) -> void:
	_problems += 1
	print("%s %s %s %s (%s)" % [kind, tag, c.get_path(), detail, c.get_class()])
