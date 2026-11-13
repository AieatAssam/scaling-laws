extends SceneTree
## Dev: store listing screenshots from the real main scene, on the same early-game state as tools/dev_readme_shots.gd.
## Phones (six frames, captioned): capture 360x640 with the shell pushed down 50 px, then 3x nearest (1080x1920) and the
## caption band drawn over the top 150 px, so the caption never covers the HUD.
## Tablets (four landscape frames): capture 960x540 (1:1 with the 360x540 base), 2x nearest (1920x1080), no caption.
## Never touches the player save; never writes outside the out dir.
## $GODOT --path . -s tools/dev_store_shots.gd -- <out_dir>   (default store/screenshots)

const PHONE := Vector2i(360, 640)
const PHONE_OUT := Vector2i(1080, 1920)
const BAND_LOGICAL := 50
const BAND_PX := 150
const CAPTION_SIZE := 40  # 5 x 8 px: whole pixel-font cells at 1080 px wide
const TABLET := Vector2i(960, 540)
const TABLET_OUT := Vector2i(1920, 1080)
const NAVY := Color("0B0E1A")
const AMBER := Color("FFB347")
const FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const OWNED := {"intern_laptop": 36, "cloud_gpus": 14, "server_rack": 6, "data_centre": 2}
const LATE_TABS := ["paradigm", "singularity"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "store/screenshots"
	for d in ["phone", "tablet7", "tablet10"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out, d])
	create_timer(300.0).timeout.connect(quit.bind(1))  # failsafe: a stuck frame must not hang the run
	await process_frame
	var game = root.get_node("/root/Game")
	game.save_path = "user://dev_store_shots.json"
	root.get_node("/root/SaveSystem").delete(game.save_path)
	game.state.persist["intro_seen"] = true
	game.state.persist["saved_at"] = Time.get_unix_time_from_system()
	game.running = false
	change_scene_to_file("res://src/ui/main.tscn")
	await create_timer(0.8).timeout
	var main: Node = current_scene
	var state = game.state
	# The same early run as the README frames: four producer types owned, one Funding Round taken, no late tabs.
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
	await create_timer(1.2).timeout  # let the purchase bursts finish before the clean frames
	_check_tabs(main)

	await _phone(main, out, "phone/01-buy-compute", "BUY COMPUTE", "producers")
	await _tablet(main, out, "tablet7/01-lab-producers", "producers")

	game.start_training("standard")
	state.run["layers"][0]["training"]["left"] = 34.0  # of the run's 60 s
	await _phone(main, out, "phone/02-train-models", "TRAIN MODELS", "training")
	await _tablet(main, out, "tablet10/01-training", "training")

	state.set_cur("equity", BigNum.from_float(125.0))
	state.set_cur("insights", BigNum.from_float(8.0))
	state.run["layers"][2]["desk"]["slots"] = [{"id": "paper_02", "landmark": false}]
	state.run["layers"][2]["desk"]["timer"] = 900.0
	state.persist["stats"]["papers"] = 0
	state.persist["stats"]["resets"] = 2
	main.call("_refresh_tabs")
	_check_tabs(main)
	await _phone(main, out, "phone/03-publish-papers", "PUBLISH PAPERS", "generation")
	await _tablet(main, out, "tablet10/02-research-desk", "generation")

	await _show_tab(main, "funding", PHONE)
	_scroll_to_staff(main.get("_panels")["funding"], 120.0)  # the Funding card is taller than the phone: show the hire rows
	await _settle()
	await _phone_frame(main, out, "phone/04-hire-a-team", "HIRE A TEAM")
	await _tablet(main, out, "tablet7/02-hire-a-team", "funding", 200.0)

	# Statistics overlay: hide the rows that list systems not yet revealed in this early run.
	DisplayServer.window_set_size(PHONE)
	main.call("_refresh_tabs")
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
	# Cut at the bottom edge: rows that do not fit fully are hidden (no half-visible row under the frame).
	var limit := float(PHONE.y) - 40.0  # a clean bottom margin: no partly drawn row
	var cut := false
	for section in stats.page.get_children():
		if not (section is Control) or not section.visible:
			continue
		for row in section.get_children():
			if not (row is Control) or not row.visible:
				continue
			if cut or (row as Control).get_global_rect().end.y > limit:
				cut = true
				row.hide()
	await _settle()
	await _phone_frame(main, out, "phone/05-track-everything", "TRACK EVERYTHING")
	stats.hide()

	# Offline card: three minutes away, credited by the real Sim.offline (50% efficiency).
	await _show_tab(main, "producers", PHONE)
	var away := 3.0 * 60.0  # 3 min: a credit of tens of thousands, in proportion to the /s rates on screen
	var summary: Dictionary = Sim.offline(state, minf(away, Sim.OFFLINE_CAP))
	summary["away"] = away
	main.get("_notices").show_offline(summary)
	await _phone_frame(main, out, "phone/06-come-back-to-progress", "COME BACK TO PROGRESS")
	quit()


## Phone frame for a tab: the shell pushed down under the caption band.
func _phone(main: Node, out: String, file: String, caption: String, tab: String) -> void:
	await _show_tab(main, tab, PHONE)
	await _phone_frame(main, out, file, caption)


func _tablet(main: Node, out: String, file: String, tab: String, staff_margin: float = -1.0) -> void:
	await _show_tab(main, tab, TABLET)
	main.offset_top = 0.0
	if staff_margin >= 0.0:
		_scroll_to_staff(main.get("_panels")[tab], staff_margin)
	await _settle()
	_clear_overlays(main)
	await _settle()
	var img: Image = root.get_texture().get_image()
	if img.get_size() != TABLET:
		push_error("%s captured at %s, expected %s" % [file, img.get_size(), TABLET])
	img.convert(Image.FORMAT_RGBA8)
	img.resize(TABLET_OUT.x, TABLET_OUT.y, Image.INTERPOLATE_NEAREST)
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [out, file])
	print("saved %s %s" % [file, TABLET_OUT])


func _phone_frame(main: Node, out: String, file: String, caption: String) -> void:
	main.offset_top = BAND_LOGICAL
	await _settle()
	_clear_overlays(main)
	await _settle()
	var img: Image = root.get_texture().get_image()
	if img.get_size() != PHONE:
		push_error("%s captured at %s, expected %s" % [file, img.get_size(), PHONE])
	img.convert(Image.FORMAT_RGBA8)
	img.resize(PHONE_OUT.x, PHONE_OUT.y, Image.INTERPOLATE_NEAREST)
	var band: Image = await _caption(caption, PHONE_OUT.x, BAND_PX)
	img.blit_rect(band, Rect2i(Vector2i.ZERO, Vector2i(PHONE_OUT.x, BAND_PX)), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [out, file])
	print("saved %s %s" % [file, PHONE_OUT])
	main.offset_top = 0.0


## Scrolls the nearest ScrollContainer so the first staff row sits near the top of the phone.
func _scroll_to_staff(panel: Node, margin: float) -> void:
	var staff: Dictionary = panel.get("_staff")
	var first: Dictionary = staff[staff.keys()[0]]
	var hire: Control = first["hire"]
	var sc: Node = hire.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc == null:
		push_error("funding staff rows are not inside a ScrollContainer")
		return
	var scroll := sc as ScrollContainer
	scroll.scroll_vertical = int(hire.get_global_rect().position.y - scroll.get_global_rect().position.y + scroll.scroll_vertical - margin)


## Hides the reveal card and the benchmark toast so neither lands on the frame.
func _clear_overlays(main: Node) -> void:
	var reveal = main.get("_reveal_card")
	if reveal != null:
		reveal.dismiss()
	var notices = main.get("_notices")
	if notices != null and notices.get("_toast") != null:
		notices.get("_toast").hide()


## Window size, tab and the dev-only tidy-ups (no reveal card, no toast, later producers hidden).
func _show_tab(main: Node, tab: String, size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	await process_frame
	main.call("_select", tab)
	var panel = main.get("_panels")[tab]
	panel.call("_refresh")
	if tab == "generation":
		for child in panel.page.get_children():
			if child != panel.get("_desk") and child != panel.result_line:
				child.hide()  # the requested paper card is the only reset-layer content in this frame
	elif tab == "producers":
		_hide_later_producers(panel)
	await _settle()
	var reveal = main.get("_reveal_card")
	if reveal != null:
		reveal.dismiss()
	var notices = main.get("_notices")
	if notices != null and notices.get("_toast") != null:
		notices.get("_toast").hide()
	await _settle()


## Caption band: the pixel font drawn by Godot at native 1080 px, navy background, centred.
func _caption(text: String, width: int, height: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(width, height)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.size = Vector2(width, height)
	vp.add_child(bg)
	var label := Label.new()
	label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_font_size_override("font_size", CAPTION_SIZE)
	label.add_theme_color_override("font_color", AMBER)
	label.text = text
	label.position = Vector2.ZERO
	label.size = Vector2(width, height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vp.add_child(label)
	root.add_child(vp)
	await _settle()
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _settle() -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw


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
