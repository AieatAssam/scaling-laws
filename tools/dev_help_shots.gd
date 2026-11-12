extends SceneTree
## Dev: Help screenshots. Never touches user://save.json; the save path is a dev file.
## $GODOT --path . --resolution 1280x720 -s tools/dev_help_shots.gd -- out.png [fresh|advanced] [topic]

const DEV_SAVE := "user://dev_help_shots.json"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[1] if args.size() > 1 else "fresh"
	var topic := args[2] if args.size() > 2 else ""
	await process_frame
	var game := root.get_node("/root/Game")
	var content := root.get_node("/root/Content")
	game.save_path = DEV_SAVE
	if mode == "advanced":
		var s := GameState.new(content, 7)
		s.persist["stats"]["time"] = 7200.0
		s.persist["intro_seen"] = true
		s.persist["saved_at"] = Time.get_unix_time_from_system()  # no offline-progress dialog over the shot
		for id in ["reset_funding_1", "reset_generation_1", "reset_paradigm_1"]:
			s.persist["benchmarks"].append(id)
		s.run["resets_done"] = [1, 1, 0, 0]
		s.add_cur("compute", BigNum.from_float(5e6))
		root.get_node("/root/SaveSystem").save(s.to_dict(), DEV_SAVE)
	else:
		DirAccess.remove_absolute(DEV_SAVE)
		game.state.persist["intro_seen"] = true  # skip the first-run intro
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(2.0).timeout
	if topic.begins_with("?"):
		# "?" or "?<tab>": presses the first visible "?" help button on that tab, the way a player would.
		await _press_help(topic.substr(1) if topic.length() > 1 else "training")
	else:
		current_scene.open_help(topic)
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(args[0])
	quit()


func _press_help(tab: String) -> void:
	current_scene._select(tab)
	await process_frame
	var panel: Node = current_scene.get("_panels")[tab]
	for b in _buttons(panel):
		if b.text == "?" and b.is_visible_in_tree():
			print("pressing ? on ", tab)
			b.pressed.emit()
			return
	push_error("no visible ? button on tab " + tab)


func _buttons(n: Node) -> Array:
	var out := []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out
