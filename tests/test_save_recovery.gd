extends GutTest
## Save recovery and migration: a v1 save, missing keys, a damaged main file with and without a backup, a newer
## file that must survive, the rolling backup, and delete. Files go to user:// and are removed after each test.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
const PATH := "user://test_save_recovery.json"

var content: Node
var saver: Node


func before_each() -> void:
	content = autofree(Support.make_content())
	saver = autofree(SaveScript.new())
	Support.remove_save_files(PATH)


func after_each() -> void:
	Support.remove_save_files(PATH)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null  # closes the file


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Full path of the file the save system set aside with this kind ("bad" or "newer"), or "" if none.
func _kept(kind: String) -> String:
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with(PATH.get_file() + "." + kind + "-"):
			return "user://" + f
	return ""


func _best_all_in(path: String) -> float:
	var d: Dictionary = JSON.parse_string(_read(path))
	return float(d["state"]["persist"]["best_all"])


## A version 1 save as the v0.1.x game wrote it: training held a compute share ("frac") instead of a run type,
## and persist had no intro flag or lifetime counter (both came with v0.2.0).
func _v1_state() -> Dictionary:
	var d := Support.new_state(content, 11).to_dict()
	d["persist"].erase("intro_seen")
	d["persist"].erase("lifetime_resets")
	var L0: Dictionary = d["run"]["layers"][0]
	L0["cur"]["compute"] = {"mantissa": 2.5, "exponent": 4}  # 25 000 compute
	L0["training"] = {"frac": 0.5, "log": 3.0, "left": 30.0, "fail": 0.1}  # in flight: 10^3 compute spent
	return d


func test_v1_save_migrates_and_refunds_the_run_in_flight() -> void:
	_write(PATH, JSON.stringify({"version": 1, "state": _v1_state()}))
	var s := GameState.from_dict(content, saver.load_data(PATH))
	assert_true(s.run["layers"][0]["training"].is_empty(), "the old training run is cleared")
	assert_almost_eq(s.cur("compute").to_float(), 26000.0, 0.5, "its spend (10^3) is refunded")
	assert_eq(s.run["layers"].size(), 5)
	assert_true(bool(s.persist["intro_seen"]), "a v1 save has been played")
	assert_eq(saver.last_notice, "", "a clean migration says nothing")


func test_missing_keys_default_and_partial_structs_are_completed() -> void:
	var partial := {
		"persist": {"saved_at": 5.0, "stats": {"runs": 3}},
		"run": {"layers": [{"cur": {"cash": {"mantissa": 1.0, "exponent": 2}}}]},
	}
	var s := GameState.from_dict(content, partial)
	assert_eq(s.run["layers"].size(), 5, "layers padded to five")
	assert_eq(int(s.persist["stats"]["runs"]), 3, "a saved stat is kept")
	assert_true(s.persist["stats"].has("resets"), "a missing stat is filled")
	assert_true(s.persist["settings"].has("reduce_motion"), "missing settings are filled")
	assert_true(bool(s.persist["intro_seen"]), "no intro flag counts as seen")
	assert_eq(s.persist["lifetime_resets"], s.run["resets_done"], "no lifetime counter: this run's resets")
	assert_eq(s.run["layers"][0]["cur"].size(), 1, "a saved cur is not merged with the starting values")
	assert_true(s.run["layers"][1]["cur"].is_empty(), "a layer with no cur starts empty")
	assert_true(s.run["layers"][0]["life"] is BigNum, "a missing life is a BigNum")
	assert_ne(s.rng.state, 0, "a missing rng gets a seeded state")


func test_damaged_main_falls_back_to_the_backup() -> void:
	var good := Support.new_state(content, 12)
	good.persist["best_all"] = 123.0
	assert_true(saver.save(good.to_dict(), PATH))
	DirAccess.copy_absolute(PATH, PATH + ".bak")
	_write(PATH, "{ broken")

	var s := GameState.from_dict(content, saver.load_data(PATH))
	assert_almost_eq(float(s.persist["best_all"]), 123.0, 0.001, "the backup is restored")
	assert_string_contains(saver.last_notice, "restored")
	assert_ne(_kept("bad"), "", "the damaged file is kept")
	assert_false(FileAccess.file_exists(PATH), "the damaged main was moved aside")


func test_damaged_main_and_backup_start_a_new_game_and_keep_the_damage() -> void:
	_write(PATH, "{ broken")
	_write(PATH + ".bak", "[1, 2")
	assert_eq(saver.load_data(PATH), {}, "nothing usable: a new game")
	assert_string_contains(saver.last_notice, "no backup")
	var kept := _kept("bad")
	assert_ne(kept, "", "the damaged file is kept")
	assert_eq(_read(kept), "{ broken")
	assert_false(FileAccess.file_exists(PATH))


func test_newer_version_is_kept_and_never_overwritten() -> void:
	var text := JSON.stringify({"version": SaveScript.VERSION + 1, "state": {"persist": {}}})
	_write(PATH, text)
	assert_eq(saver.load_data(PATH), {}, "a new game starts")
	assert_string_contains(saver.last_notice, "newer version")
	var kept := _kept("newer")
	assert_eq(_read(kept), text, "the newer file is kept as it was")
	# Saving the new game twice must not touch the kept file.
	var fresh := Support.new_state(content, 13)
	assert_true(saver.save(fresh.to_dict(), PATH))
	assert_true(saver.save(fresh.to_dict(), PATH))
	assert_eq(_read(kept), text)


func test_save_refuses_to_overwrite_a_newer_main_file() -> void:
	var text := JSON.stringify({"version": SaveScript.VERSION + 1, "state": {}})
	_write(PATH, text)
	assert_false(saver.save(Support.new_state(content, 14).to_dict(), PATH))
	assert_push_error("newer version")
	assert_eq(_read(PATH), text)


func test_rolling_backup_holds_the_previous_good_save() -> void:
	var a := Support.new_state(content, 15)
	a.persist["best_all"] = 1.0
	var b := Support.new_state(content, 15)
	b.persist["best_all"] = 2.0
	assert_true(saver.save(a.to_dict(), PATH))
	assert_true(saver.save(b.to_dict(), PATH))
	assert_eq(_best_all_in(PATH + ".bak"), 1.0, "the backup is the save before the last one")
	assert_eq(_best_all_in(PATH), 2.0)

	# A main file that was cut short (killed mid-write) must not replace the backup.
	_write(PATH, "{ trunc")
	var c := Support.new_state(content, 15)
	c.persist["best_all"] = 3.0
	assert_true(saver.save(c.to_dict(), PATH))
	assert_eq(_best_all_in(PATH + ".bak"), 1.0, "the last good backup survives a damaged main")
	assert_eq(_best_all_in(PATH), 3.0)


func test_delete_removes_the_backup_too() -> void:
	saver.save(Support.new_state(content, 16).to_dict(), PATH)
	saver.save(Support.new_state(content, 16).to_dict(), PATH)
	assert_true(FileAccess.file_exists(PATH + ".bak"))
	saver.delete(PATH)
	assert_false(FileAccess.file_exists(PATH))
	assert_false(FileAccess.file_exists(PATH + ".bak"), "a later damaged save must not restore reset progress")
