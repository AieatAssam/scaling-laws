extends SceneTree
## Captures the README frames from the real main scene without touching the player save.
## Phones are captured at exactly 360x640 and written 3x nearest-neighbour (1080x1920); the desktop frame is 1280x720.
## The state is an early run: four producer types owned (10-40 of the first two), a first reset of the funding and
## generation layers, a training run half done, four lab rooms, and no Paradigm/Singularity tabs or late rooms.
## $GODOT --path . -s tools/dev_readme_shots.gd -- <out_dir>

const PHONE := Vector2i(360, 640)
const PHONE_SCALE := 3
const DESKTOP := Vector2i(1280, 720)
const OWNED := {"intern_laptop": 36, "cloud_gpus": 14, "server_rack": 6, "data_centre": 2}
const LATE_TABS := ["paradigm", "singularity"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "docs/screenshots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var game = root.get_node("/root/Game")
	game.save_path = "user://dev_readme_shots.json"
	root.get_node("/root/SaveSystem").delete(game.save_path)
	game.state.persist["intro_seen"] = true
	game.state.persist["saved_at"] = Time.get_unix_time_from_system()
	game.running = false
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.8).timeout
	var main: Node = current_scene
	var state = game.state
	# Buy with plenty of money, then set the wallet to what an early run would hold.
	state.set_cur("cash", BigNum.from_float(1e12))
	state.set_cur("compute", BigNum.from_float(1e12))
	for id in OWNED:
		Sim.buy_producer(state, id, OWNED[id])
	state.set_cur("cash", BigNum.from_float(312.0))
	state.set_cur("compute", BigNum.from_float(58.0))
	state.persist["stats"]["time"] = 900.0
	state.persist["stats"]["runs"] = 1
	state.persist["stats"]["trainings"] = 1
	state.persist["best_all"] = 2.35
	# Funding reset done this run unlocks the generation tab. The desk unlocks on a lifetime generation reset (Desk.unlocked),
	# but run resets_done[1] would unlock Paradigm (is_layer_unlocked(3)), which is late: leave that at 0.
	state.persist["lifetime_resets"][0] = 1
	state.persist["lifetime_resets"][1] = 1
	state.run["resets_done"][0] = 1
	game.running = true
	game.set_setting("reduce_motion", true)
	var lab: Node = main.get("_lab_slot").get_child(0)
	lab.call("_resync")
	main.call("_refresh_tabs")
	main.get("_panels")["producers"].call("_refresh")
	_hide_later_producers(main.get("_panels")["producers"])
	await create_timer(1.2).timeout  # let the lab's purchase bursts finish before the clean frames
	_check_tabs(main)

	await _capture(main, out, "01-lab-desktop", DESKTOP, "producers", false)
	await _capture(main, out, "02-producers", PHONE, "producers", true)

	game.start_training("standard")
	state.run["layers"][0]["training"]["left"] = 34.0  # of the run's 60 s
	await _capture(main, out, "03-training", PHONE, "training", true)

	state.set_cur("equity", BigNum.from_float(125.0))
	state.set_cur("insights", BigNum.from_float(8.0))
	state.run["layers"][2]["desk"]["slots"] = [{"id": "paper_02", "landmark": false}]
	state.run["layers"][2]["desk"]["timer"] = 900.0
	state.persist["stats"]["papers"] = 0
	state.persist["stats"]["resets"] = 2
	main.call("_refresh_tabs")
	_check_tabs(main)
	await _capture(main, out, "04-research-desk", PHONE, "generation", true)

	state.run["layers"][2]["desk"]["slots"] = []
	DisplayServer.window_set_size(PHONE)
	main.open_stats()
	await _settle()
	var stats = main.get("_stats")
	var stats_children: Array = stats.page.get_children()
	stats_children[3].hide()  # completion lists systems that have not been revealed yet
	stats_children[7].hide()
	for row in stats_children[6].get_children():
		if row is HBoxContainer and row.get_child_count() > 0 and row.get_child(0) is Label:
			var title: String = row.get_child(0).text
			if title.begins_with("Moonshots") or title.begins_with("Evals"):
				row.hide()
	await _settle()
	var reveal = main.get("_reveal_card")
	if reveal != null:
		reveal.dismiss()
	var notices = main.get("_notices")
	if notices != null and notices.get("_toast") != null:
		notices.get("_toast").hide()
	await _settle()
	await _save(root.get_texture().get_image(), "%s/05-stats.png" % out, true)
	quit()


func _capture(main: Node, out: String, name: String, size: Vector2i, tab: String, phone: bool) -> void:
	DisplayServer.window_set_size(size)
	await process_frame
	main.call("_select", tab)
	if tab == "generation":
		var panel = main.get("_panels")[tab]
		panel.call("_refresh")
		for child in panel.page.get_children():
			if child != panel.get("_desk") and child != panel.result_line:
				child.hide()  # the requested paper card is the only reset-layer content in this frame
	else:
		main.get("_panels")[tab].call("_refresh")
		if tab == "producers":
			_hide_later_producers(main.get("_panels")[tab])
	await _settle()
	var reveal = main.get("_reveal_card")
	if reveal != null:
		reveal.dismiss()
	var notices = main.get("_notices")
	if notices != null and notices.get("_toast") != null:
		notices.get("_toast").hide()
	await _settle()
	await _save(root.get_texture().get_image(), "%s/%s.png" % [out, name], phone)


func _settle() -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(image: Image, path: String, phone: bool) -> void:
	if phone:
		if image.get_size() != PHONE:
			push_error("%s captured at %s, expected %s" % [path, image.get_size(), PHONE])
		image.resize(PHONE.x * PHONE_SCALE, PHONE.y * PHONE_SCALE, Image.INTERPOLATE_NEAREST)
	image.save_png(path)
	print("saved %s %s" % [path, image.get_size()])


## Reports the tabs on screen and fails loudly if a late tab shows in an early-game frame.
func _check_tabs(main: Node) -> void:
	var shown: Array[String] = []
	for id in main.get("_tabs"):
		if (main.get("_tabs")[id] as Button).visible:
			shown.append(id)
	print("tabs shown: %s" % [shown])
	for id in LATE_TABS:
		if id in shown:
			push_error("late tab '%s' is visible in the early-game state" % id)


func _hide_later_producers(panel: Node) -> void:
	var rows: Dictionary = panel.get("_rows")
	var order: Array = panel.get("_order")
	var state = root.get_node("/root/Game").state
	for id in order:
		if state.owned(id) == 0 and not Sim.producer_available(state, id):
			rows[id]["row"].hide()
