extends SceneTree
## Dev: lab zoom sweep across window sizes. Prints the lab's physical pixels per art pixel at each size and saves a
## screenshot per size. Run windowed (not --headless): $GODOT --path . -s tools/dev_lab_sweep.gd -- <out_dir>

const SIZES := [
	Vector2i(800, 600), Vector2i(1000, 800), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1440, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(390, 844), Vector2i(844, 390),
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var g = root.get_node("/root/Game")
	g.save_path = "user://dev_lab_sweep_save.json"  # never touch the real save
	g.state.persist["intro_seen"] = true
	g.state.persist["saved_at"] = Time.get_unix_time_from_system()  # no offline card over the lab
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.5).timeout
	# A mid-game tower: several producers owned, so the framing and the zoom depend on the window.
	var st = g.state
	st.set_cur("cash", BigNum.from_float(1e9))
	for id in ["intern_laptop", "cloud_gpus", "server_rack", "data_centre", "custom_silicon"]:
		Sim.buy_producer(st, id, -1)
	g.running = false
	for s in SIZES:
		DisplayServer.window_set_size(s)
		await create_timer(1.5).timeout
		var lab := _find_lab(current_scene)
		var k: int = lab.pixel_k if lab != null else -1
		print("%dx%d pixel_k=%d px=%.2f stage=%d" % [s.x, s.y, k, lab.px if lab != null else 0.0, lab.shown_stage if lab != null else -1])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/lab_%dx%d.png" % [out, s.x, s.y])
	quit()


func _find_lab(n: Node) -> Node:
	if n.get_script() != null and n.get_script().resource_path == "res://src/lab/lab_view.gd":
		return n
	for c in n.get_children():
		var f := _find_lab(c)
		if f != null:
			return f
	return null
