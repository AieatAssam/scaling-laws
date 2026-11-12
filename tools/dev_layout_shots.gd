extends SceneTree
## Dev: one screenshot of the real main scene at a forced game stage, for layout review. Not shipped.
## Window size comes from the command line: $GODOT --path . --resolution 390x844 -s tools/dev_layout_shots.gd -- <out.png> <stage> [tab]
## stage: fresh (1 producer) | six (6 tiers, multi-floor) | orbit (stage 2) | swarm (stage 3) | universe (stage 4)
## tab: optional panel id to select before the shot (default: the first unlocked tab). Never touches the real save.

const COUNTS := {
	"fresh": {"intern_laptop": 1},
	"six": {"intern_laptop": 3, "cloud_gpus": 2, "server_rack": 2, "data_centre": 1, "custom_silicon": 1, "hyperscale_campus": 1},
	"orbit": {"intern_laptop": 3, "cloud_gpus": 2, "server_rack": 2, "data_centre": 1, "custom_silicon": 1, "hyperscale_campus": 1, "fusion_plant": 1, "orbital_cluster": 1},
	"swarm": {"intern_laptop": 3, "cloud_gpus": 2, "server_rack": 2, "data_centre": 1, "custom_silicon": 1, "hyperscale_campus": 1, "fusion_plant": 1, "orbital_cluster": 1, "lunar_foundry": 1, "dyson_swarm": 1},
	"universe": {"intern_laptop": 3, "cloud_gpus": 2, "server_rack": 2, "data_centre": 1, "custom_silicon": 1, "hyperscale_campus": 1, "fusion_plant": 1, "orbital_cluster": 1, "lunar_foundry": 1, "dyson_swarm": 1, "matrioshka_brain": 1, "universe_simulator": 1},
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var stage: String = args[1]
	await process_frame
	var g = root.get_node("/root/Game")
	g.save_path = "user://dev_layout_%s.json" % stage
	root.get_node("/root/SaveSystem").delete(g.save_path)
	g.state.persist["intro_seen"] = true
	g.state.persist["saved_at"] = Time.get_unix_time_from_system()
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.6).timeout
	var st = g.state
	st.set_cur("cash", BigNum.from_float(1e40))  # buying needs cash; reset below
	for id in COUNTS[stage]:
		Sim.buy_producer(st, id, COUNTS[stage][id])
	st.set_cur("cash", BigNum.from_float(250.0))
	g.running = false
	var main: Node = current_scene
	if args.size() > 2:
		main.call("_select", args[2])
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHOT %s %s" % [out, str(root.get_visible_rect().size)])
	quit(0)
