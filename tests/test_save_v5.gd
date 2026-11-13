extends GutTest
## Save version 5: upgrades, launch cooldowns and news state arrive through the v4 -> v5 migration.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func test_version_is_seven() -> void:
	assert_eq(SaveScript.VERSION, 7)


func test_a_v4_save_gains_the_new_state() -> void:
	var state: Dictionary = GameState.new(content, 1).to_dict()
	state["run"]["layers"][0].erase("upgrades")
	state["run"].erase("launches")
	state["run"].erase("news")
	state["persist"]["stats"].erase("news")
	state["persist"]["stats"].erase("launches")
	var save: SaveSystem = autofree(SaveScript.new())
	var migrated: Dictionary = save.migrate({"version": 4, "state": state})
	assert_true(migrated["run"]["layers"][0].has("upgrades"))
	assert_eq(migrated["run"]["launches"], {})
	assert_eq(float(migrated["run"]["news"]["timer"]), News.FIRST_SECONDS)
	assert_eq(int(migrated["persist"]["stats"]["news"]), 0)
	assert_eq(int(migrated["persist"]["stats"]["launches"]), 0)
	var restored := GameState.from_dict(content, migrated)
	assert_eq(Upgrades.owned_ids(restored), [])


func test_a_v5_save_is_left_alone() -> void:
	var state: Dictionary = GameState.new(content, 1).to_dict()
	state["run"]["news"]["timer"] = 42.0
	var save: SaveSystem = autofree(SaveScript.new())
	var migrated: Dictionary = save.migrate({"version": 5, "state": state})
	assert_eq(float(migrated["run"]["news"]["timer"]), 42.0)
