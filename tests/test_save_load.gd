extends GutTest
## Save/load: full round-trip equality after a non-trivial session, version field, migration of an
## older version, and corrupt-file handling. Files go to user:// and are deleted after each test.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
const PATH := "user://test_save_roundtrip.json"

var content: Node
var saver: Node


func before_each() -> void:
	content = autofree(Support.make_content())
	saver = autofree(SaveScript.new())
	saver.delete(PATH)


func after_each() -> void:
	Support.remove_save_files(PATH)


## JSON turns every number into a float, so equality is checked on the JSON form of both sides.
func _norm(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(Support.plain(d)))


## A session that touches most systems: buys, training, events, a reset, then more time.
func _played_state() -> GameState:
	var s := Support.new_state(content, 2024)
	Support.set_cash_float(s, "cash", 1e12)
	var list: Array = Sim.producers(s)
	for i in 3:
		Sim.buy_producer(s, list[0].id, 5)
		Sim.buy_producer(s, list[1].id, 2)
		Sim.tick(s, 45.0)
	s.add_cur("compute", BigNum.from_float(5e4))
	Sim.start_training(s, "standard")
	for i in 40:
		for e in Sim.tick(s, 7.0):
			if e["kind"] == "event":
				Sim.resolve_event(s, 0)
	for k in [1]:
		s.run["layers"][k]["life"] = BigNum.from_float(float(Sim.layer_def(s, k).threshold) * 4.0)
		Sim.perform_reset(s, k)
	Sim.tick(s, 120.0)
	return s


func test_round_trip_is_exact_and_the_run_continues_identically() -> void:
	var s := _played_state()
	var before := _norm(s.to_dict())
	assert_true(saver.save(s.to_dict(), PATH))

	var s2 := GameState.from_dict(content, saver.load_data(PATH))
	assert_eq(_norm(s2.to_dict()), before, "state after reload equals state before save")

	for i in 30:
		Sim.tick(s, 13.0)
		Sim.tick(s2, 13.0)
	assert_eq(_norm(s2.to_dict()), _norm(s.to_dict()), "same RNG and state: same future")


func test_file_carries_the_current_version() -> void:
	saver.save(_played_state().to_dict(), PATH)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(parsed["version"]), SaveScript.VERSION)
	assert_true(parsed["state"] is Dictionary)


func test_older_version_dict_is_migrated_to_current() -> void:
	var state := _norm(_played_state().to_dict())
	var old_wrapper := {"version": 0, "state": state}
	assert_eq(saver.migrate(old_wrapper), state, "v0 state passes through the migration chain")
	# A file written without any version field counts as version 0.
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"state": state}))
	f = null
	var loaded: Dictionary = saver.load_data(PATH)
	assert_eq(_norm(loaded), state)


func test_newer_version_is_refused() -> void:
	var newer := {"version": SaveScript.VERSION + 1, "state": {}}
	assert_eq(saver.migrate(newer), {})
	assert_push_error("newer")


func test_missing_file_loads_as_empty() -> void:
	assert_eq(saver.load_data(PATH), {})


func test_corrupt_files_load_as_empty_and_report() -> void:
	var cases := ["{ this is not json", "[1, 2, 3]", "{\"version\": 1}"]
	for text in cases:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(text)
		f = null
		assert_eq(saver.load_data(PATH), {}, "corrupt: %s" % text)
		assert_ne(saver.last_notice, "", "the player is told the save was damaged")
		assert_false(FileAccess.file_exists(PATH), "the damaged file was moved aside")
