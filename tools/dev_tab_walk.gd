extends SceneTree
## Dev: walks every visible tab at 1280x720 and 390x844 and saves one screenshot per tab. Prints any Control that
## sticks out past the left or right edge, and the root's minimum width. Windowed (screenshots need a renderer):
##   $GODOT --path . -s tools/dev_tab_walk.gd -- <out_dir> fresh|late
## "late" gives a mid-to-late tower (currencies, resets, producers). Never touches the real save.

const SIZES := [Vector2i(1280, 720), Vector2i(390, 844)]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var mode: String = args[1] if args.size() > 1 else "fresh"
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
	if mode == "late":
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
	await create_timer(0.5).timeout
	var tabs: Dictionary = main.get("_tabs")
	for s in SIZES:
		DisplayServer.window_set_size(s)
		await create_timer(1.0).timeout
		var vp: Vector2 = root.get_visible_rect().size
		print("== %s %dx%d (logical %dx%d) root_min=%s" % [mode, s.x, s.y, vp.x, vp.y,
			str(main.get_combined_minimum_size())])
		for id in tabs.keys():
			var b: Button = tabs[id]
			if not b.is_visible_in_tree():
				continue
			b.pressed.emit()
			await create_timer(0.5).timeout
			_scan(main, vp, "%s@%dx%d" % [id, s.x, s.y])
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%dx%d_%s.png" % [out, mode, s.x, s.y, id])
		if s.x == 390:
			# Phone: a held finger on an icon-only tab shows its name (Tip long-press).
			# Input events take window pixels; the tab rect is in logical (stretched) units.
			var p: Vector2 = root.get_final_transform() * (tabs["benchmarks"] as Button).get_global_rect().get_center()
			var mm := InputEventMouseMotion.new()  # a real finger also moves the emulated pointer onto the tab
			mm.position = p
			mm.global_position = p
			Input.parse_input_event(mm)
			await process_frame
			await _touch(p, true)
			await create_timer(1.2).timeout
			for c in main.get_children():
				if c.get_script() != null and c.get_script().resource_path.ends_with("tip.gd"):
					print("LONGPRESS tip shown=%s" % str(c.get("_shown")))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%dx%d_longpress_benchmarks.png" % [out, mode, s.x, s.y])
			await _touch(p, false)
			await create_timer(0.3).timeout
		print("tabs shown: %s" % ", ".join(tabs.keys().filter(func(k): return (tabs[k] as Button).is_visible_in_tree())))
	quit()


func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = pos
	Input.parse_input_event(ev)
	await process_frame
	await process_frame


## Prints every visible Control whose rect lies past the left or right edge of the logical viewport.
func _scan(n: Node, vp: Vector2, tag: String) -> void:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).size.x > 0.0:
		var r: Rect2 = (n as Control).get_global_rect()
		if r.end.x > vp.x + 0.5 or r.position.x < -0.5:
			print("OVERFLOW %s %s rect=%s" % [tag, n.get_path(), str(r)])
	for c in n.get_children():
		_scan(c, vp, tag)
