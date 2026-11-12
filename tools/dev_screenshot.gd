extends SceneTree
# Dev: $GODOT --path . --resolution 1280x720 -s tools/dev_screenshot.gd -- out.png [seconds]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	root.get_node("/root/Game").state.persist["intro_seen"] = true  # skip the first-run intro
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(float(args[1]) if args.size() > 1 else 2.0).timeout
	root.get_texture().get_image().save_png(args[0])
	quit()
