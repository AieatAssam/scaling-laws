extends SceneTree
## Dev: one screenshot of the real main scene with the Funding reset card unlocked and an ETA to show (Rules.reset_eta).
## Window size from the command line: $GODOT --path . --resolution 360x640 -s tools/dev_progress_shots.gd -- <out.png> [tab]
## Sets Funding life to one threshold (gain 1, not yet worth it) on a six-tier producer setup. Never touches the real save.

const COUNTS := {"intern_laptop": 3, "cloud_gpus": 2, "server_rack": 2, "data_centre": 1, "custom_silicon": 1, "hyperscale_campus": 1}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	await process_frame
	var g = root.get_node("/root/Game")
	g.save_path = "user://dev_progress.json"
	root.get_node("/root/SaveSystem").delete(g.save_path)
	g.state.persist["intro_seen"] = true
	g.state.persist["saved_at"] = Time.get_unix_time_from_system()
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	var st = g.state
	st.set_cur("cash", BigNum.from_float(1e40))
	for id in COUNTS:
		Sim.buy_producer(st, id, COUNTS[id])
	st.set_cur("cash", BigNum.from_float(250.0))
	var threshold := float(Sim.layer_def(st, 1).threshold)
	st.run["layers"][1]["life"] = BigNum.from_float(threshold)
	g.running = false
	var main: Node = current_scene
	main.call("_select", args[1] if args.size() > 1 else "funding")
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHOT %s %s" % [out, str(root.get_visible_rect().size)])
	quit(0)
