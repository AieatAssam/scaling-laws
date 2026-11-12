extends GutTest
## First-run intro flag (persist.intro_seen): fresh state, save/load, survives every reset kind, and old saves count as seen.
## Also checks the intro's art and caption contract. Files go to user:// and are deleted after each test.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
const Intro := preload("res://src/ui/intro.gd")
const PATH := "user://test_intro_flag.json"

var content: Node
var saver: Node


func before_each() -> void:
	content = autofree(Support.make_content())
	saver = autofree(SaveScript.new())
	saver.delete(PATH)


func after_each() -> void:
	saver.delete(PATH)


func test_fresh_state_has_not_seen_the_intro() -> void:
	var s := Support.new_state(content, 5)
	assert_true(s.persist.has("intro_seen"), "field exists on a fresh state")
	assert_false(bool(s.persist["intro_seen"]), "a brand-new game shows the intro")


func test_flag_round_trips_through_save_and_load() -> void:
	for seen in [false, true]:
		var s := Support.new_state(content, 6)
		s.persist["intro_seen"] = seen
		assert_true(saver.save(s.to_dict(), PATH))
		var back := GameState.from_dict(content, saver.load_data(PATH))
		assert_eq(bool(back.persist["intro_seen"]), seen, "saved as %s" % seen)


func test_flag_survives_every_reset_kind() -> void:
	for k in range(1, 5):
		var s := Support.new_state(content, 7)
		s.persist["intro_seen"] = true
		for j in range(1, k):
			s.run["resets_done"][j - 1] = maxi(s.resets(j), 1)
		s.run["layers"][k]["life"] = BigNum.from_float(float(Sim.layer_def(s, k).threshold) * 4.0)
		var r := Sim.perform_reset(s, k)
		assert_true(r["ok"], "layer %d reset: %s" % [k, r.get("reason", "")])
		assert_true(bool(s.persist["intro_seen"]), "layer %d reset keeps the flag" % k)


func test_flag_survives_a_new_run() -> void:
	var s := Support.new_state(content, 8)
	s.persist["intro_seen"] = true
	s.run["run_over"] = "aligned"
	var r := Sim.new_run(s)
	assert_true(r["ok"], str(r.get("reason", "")))
	assert_true(bool(s.persist["intro_seen"]), "a new legacy keeps the flag")


func test_save_without_the_field_counts_as_seen() -> void:
	var d := Support.new_state(content, 9).to_dict()
	d["persist"].erase("intro_seen")
	var s := GameState.from_dict(content, d)
	assert_true(bool(s.persist["intro_seen"]), "an older save does not replay the intro")


func test_hard_reset_state_shows_the_intro_again() -> void:
	# Settings > Hard reset builds GameState.new(), so the fresh default is what makes the intro come back.
	var s := GameState.new(content, 10)
	assert_false(bool(s.persist["intro_seen"]))


func test_intro_assets_and_captions_exist() -> void:
	var beats: Array = Intro.BEATS
	assert_eq(beats.size(), 5, "five beats")
	for b in beats:
		var path := Intro.DIR % b["art"]
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		assert_true(String(b["caption"]).length() <= 110, "caption fits: %s" % b["art"])
