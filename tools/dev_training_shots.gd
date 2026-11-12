extends SceneTree
## Dev: Training panel shot in the real main scene, unlocked with compute and a best score.
## $GODOT --path . --resolution 390x844 -s tools/dev_training_shots.gd -- <out.png> <idle|run|mid|done|short|rich>
## short: compute below the Fine-tune minimum, so the compute bar and the blocked Start show.
## Never touches the real save. Dismisses the benchmark toast so it does not cover the panel.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1]
	await process_frame
	var g = root.get_node("/root/Game")
	g.save_path = "user://dev_training_%s.json" % mode
	root.get_node("/root/SaveSystem").delete(g.save_path)
	g.state.persist["intro_seen"] = true
	g.state.persist["saved_at"] = Time.get_unix_time_from_system()
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	var st = g.state
	st.set_cur("cash", BigNum.from_float(1e6))
	st.set_cur("compute", BigNum.from_float(137.0 if mode == "short" else 1e12))
	st.run["layers"][2]["best"] = 3.45
	st.persist["best_all"] = 4.1
	if mode == "rich":  # cash income x1e12: the widest cash burst numbers the stat line has to fit
		st.run["layers"][0]["run_mult"]["cash"] = 1.0e12
	for id in ["intern_laptop"]:
		Sim.buy_producer(st, id, 1)
	g.running = true
	var main: Node = current_scene
	main.call("_select", "training")
	if mode in ["run", "mid", "done"]:
		g.start_training("standard")
	if mode == "mid":
		st.run["layers"][0]["training"]["left"] = 30.0   # half way
	if mode == "done":
		st.run["layers"][0]["training"]["left"] = 0.5    # the next tick ends it
		g.running = true
		await create_timer(2.0).timeout
	g.running = false
	await create_timer(1.0).timeout
	for c in main.get_children():
		if c.has_method("dismiss"):
			c.dismiss()
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHOT %s %s" % [out, str(root.get_visible_rect().size)])
	quit(0)
