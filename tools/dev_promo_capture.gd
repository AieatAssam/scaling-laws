extends SceneTree
## Dev: records the Play promo clips from the REAL main scene (res://src/ui/main.tscn) as PNG frames, one clip per run.
## Not shipped. Uses its own save file, never the player's.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 30 -s tools/dev_promo_capture.gd -- <clip> <out_dir>
##   clip: lab_fill | training | research | funding (360x640 portrait) | hud (1280x720 landscape)
##
## Frames are dumped from the viewport every fixed 1/30 s, so game time equals frame count. --write-movie is not used:
## it sizes the writer from the project's 1280x720 window override, so portrait frames would come out wrong.
## store/video/README.md has the ffmpeg step that turns these frames into the clips in store/video/public/clips/.
##
## Early-game only: no Paradigm or Singularity tabs and no late rooms. Each run fails loudly if a late tab shows.
## Lifetime resets are set but run resets_done[1] is not, so Paradigm stays hidden (same setup as dev_readme_shots.gd).

const MAIN := "res://src/ui/main.tscn"
const SAVE := "user://dev_promo_capture.json"
const PHONE := Vector2i(360, 640)
const DESKTOP := Vector2i(1280, 720)
const FRAMES := 180  # 6 s at 30 fps
const SEED := 2026  # fixed rng: training pass/fail and paper rolls are the same on every capture
const LATE_TABS := ["paradigm", "singularity"]
## [frame, producer id]: real Buy-button presses on the producer rows.
const LAB_BUYS := [
	[20, "intern_laptop"], [28, "intern_laptop"], [36, "intern_laptop"], [48, "cloud_gpus"],
	[56, "intern_laptop"], [68, "cloud_gpus"], [80, "server_rack"], [92, "intern_laptop"],
	[104, "cloud_gpus"], [118, "server_rack"], [132, "data_centre"], [146, "intern_laptop"],
]

var _main: Node
var _game: Node
var _clip := ""
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["lab_fill", "training", "research", "funding", "hud"]:
		push_error("usage: -- <lab_fill|training|research|funding|hud> <out_dir>")
		quit(1)
		return
	_clip = args[0]
	_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	await process_frame
	_game = root.get_node("/root/Game")
	var size := DESKTOP if _clip == "hud" else PHONE
	DisplayServer.window_set_size(size)
	_game.save_path = SAVE
	root.get_node("/root/SaveSystem").delete(SAVE)
	_game.state.persist["intro_seen"] = true
	_game.state.persist["saved_at"] = Time.get_unix_time_from_system()
	_game.running = false
	_game.set_setting("reduce_motion", false)  # the purchase pops and bursts are part of the footage
	_setup()
	change_scene_to_file(MAIN)
	for _i in 4:
		await process_frame
	_main = current_scene
	_main.call("_refresh_tabs")
	_main.call("_select", _tab())
	_game.running = true
	await _settle()
	var got := root.get_texture().get_image().get_size()
	if got != size:
		push_error("viewport is %s, expected %s" % [got, size])
		quit(1)
		return
	_check_tabs()
	for i in FRAMES:
		_act(i)
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%04d.png" % [_out, i])
	print("PROMO OK %s %d frames at %s" % [_clip, FRAMES, size])
	quit(0)


## Early-game state for each clip, written before the main scene loads (same pattern as dev_readme_shots.gd).
func _setup() -> void:
	var s = _game.state
	s.rng.seed = SEED
	match _clip:
		"lab_fill":
			s.set_cur("cash", BigNum.from_float(1e4))
			s.set_cur("compute", BigNum.from_float(1e4))
		"training":
			s.set_cur("cash", BigNum.from_float(1e6))
			s.set_cur("compute", BigNum.from_float(1e12))
			s.run["layers"][2]["best"] = 3.45
			s.persist["best_all"] = 4.1
			Sim.buy_producer(s, "intern_laptop", 6)
		"research":
			s.set_cur("cash", BigNum.from_float(312.0))
			s.set_cur("compute", BigNum.from_float(58.0))
			Sim.buy_producer(s, "intern_laptop", 12)
			s.persist["lifetime_resets"][0] = 1
			s.persist["lifetime_resets"][1] = 1  # unlocks the research desk; run resets_done[1] stays 0 (Paradigm hidden)
			s.run["resets_done"][0] = 1
			s.run["layers"][2]["desk"]["slots"] = [{"id": "paper_02", "landmark": false}]
			s.run["layers"][2]["desk"]["timer"] = 900.0
			s.persist["stats"]["resets"] = 2
		"funding":
			s.set_cur("cash", BigNum.from_float(1e4))
			s.set_cur("compute", BigNum.from_float(1e4))
			Sim.buy_producer(s, "intern_laptop", 20)
			Sim.buy_producer(s, "cloud_gpus", 4)
		"hud":
			s.set_cur("cash", BigNum.from_float(1e3))
			s.set_cur("compute", BigNum.from_float(1e3))
			Sim.buy_producer(s, "intern_laptop", 10)
			Sim.buy_producer(s, "cloud_gpus", 2)


func _tab() -> String:
	match _clip:
		"training":
			return "training"
		"research":
			return "generation"
		"funding":
			return "funding"
	return "producers"


## One-frame actions, scheduled by frame index. Everything here is a real UI press or a real Game call.
func _act(i: int) -> void:
	match _clip:
		"lab_fill":
			for step in LAB_BUYS:
				if step[0] == i:
					(_main.get("_panels")["producers"].get("_rows")[step[1]]["buy"] as Button).pressed.emit()
		"hud":
			if i == 40 or i == 100 or i == 150:
				(_main.get("_panels")["producers"].get("_rows")["intern_laptop"]["buy"] as Button).pressed.emit()
			if i == 70:
				(_main.get("_panels")["producers"].get("_rows")["cloud_gpus"]["buy"] as Button).pressed.emit()
		"training":
			if i == 12:
				_game.start_training("standard")
				_game.state.run["layers"][0]["training"]["left"] = 4.0  # of the run's 60 s: completes around frame 130
		"research":
			if i == 0:
				_hide_all_but_desk()
			if i == 110:
				_press_first_paper_choice()
		"funding":
			if i == 60:
				var ld = Sim.layer_def(_game.state, 1)
				_game.state.run["layers"][1]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)
				var r: Dictionary = _game.reset_layer(1)
				if not r.get("ok", false):
					push_error("funding reset refused: %s" % str(r.get("reason", "")))


func _hide_all_but_desk() -> void:
	var panel = _main.get("_panels")["generation"]
	for child in panel.page.get_children():
		if child != panel.get("_desk") and child != panel.result_line:
			child.hide()


func _press_first_paper_choice() -> void:
	var cards: Node = _main.get("_panels")["generation"].get("_desk_cards")
	for card in cards.get_children():
		var btn := _first_button(card)
		if btn != null:
			btn.pressed.emit()
			return
	push_error("no paper on the desk to choose from")


func _first_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button:
			return c
		var found := _first_button(c)
		if found != null:
			return found
	return null


## Waits for the frame to settle and dismisses the one-time reveal cards, toasts and natural event popups.
func _settle() -> void:
	for _i in 2:
		await process_frame
	var card = _main.get("_reveal_card")
	if card != null:
		card.dismiss()
	var notices = _main.get("_notices")
	if notices != null and notices.get("_toast") != null:
		notices.get("_toast").hide()
	for c in _main.get_children():
		if c.has_method("check_pending") and c.visible:
			c.call("_pick", 0)
	await RenderingServer.frame_post_draw


func _check_tabs() -> void:
	var tabs: Dictionary = _main.get("_tabs")
	for id in LATE_TABS:
		if tabs.has(id) and (tabs[id] as Button).visible:
			push_error("late tab '%s' is visible in an early-game clip" % id)
			quit(1)
