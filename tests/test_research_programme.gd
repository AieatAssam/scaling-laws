extends GutTest

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 1)
	s.run["resets_done"][2] = 1
	s.set_cur("breakthroughs", BigNum.from_float(100000.0))


func test_programme_cost_grows_and_completion_compounds_compute() -> void:
	assert_eq(Moonshots.programme_blocker(Support.new_state(content, 1)), "locked")
	assert_eq(Moonshots.programme_cost(s), 0.35)
	assert_true(Moonshots.start_programme(s)["ok"])
	assert_eq(Moonshots.programme_left(s), 4.0 * 3600.0)
	var saved := GameState.from_dict(content, s.to_dict())
	assert_eq(Moonshots.programme_left(saved), 4.0 * 3600.0)
	Moonshots.tick(s, 4.0 * 3600.0, [])
	assert_eq(Moonshots.programme_level(s), 1)
	assert_almost_eq(float(s.persist["perm_mult"]["compute"]), 1.03, 1e-9)
	assert_almost_eq(Moonshots.programme_cost(s), 0.49, 1e-9)
	assert_true(Moonshots.start_programme(s)["ok"])
	Moonshots.tick(s, 4.0 * 3600.0, [])
	assert_eq(Moonshots.programme_level(s), 2)
	assert_almost_eq(float(s.persist["perm_mult"]["compute"]), 1.03 * 1.03, 1e-9)


func test_programme_caps_at_25_levels() -> void:
	for _i in Moonshots.PROGRAMME_MAX:
		assert_true(Moonshots.start_programme(s)["ok"])
		Moonshots.tick(s, 8.0 * 3600.0, [])
	assert_eq(Moonshots.programme_level(s), 25)
	assert_eq(Moonshots.programme_blocker(s), "max level")


func test_v9_save_gains_programme_state() -> void:
	var state: Dictionary = s.to_dict()
	state["persist"]["moonshots"].erase("programme")
	var save: SaveSystem = autofree(SaveScript.new())
	var migrated: Dictionary = save.migrate({"version": 9, "state": state})
	assert_eq(int(migrated["persist"]["moonshots"]["programme"]["level"]), 0)
	assert_eq(float(migrated["persist"]["moonshots"]["programme"]["left"]), 0.0)
	var restored := GameState.from_dict(content, migrated)
	assert_eq(Moonshots.programme_level(restored), 0)
