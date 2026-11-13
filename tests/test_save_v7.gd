extends GutTest
## Save version 7: AGI choices arrive through the v6 -> v7 migration. A finished run gets its ending's method for each
## stage; a run still going gets Ship it for each stage already reached.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _migrate_v6(run_over: String, stage: int) -> Dictionary:
	var state: Dictionary = GameState.new(content, 1).to_dict()
	state["run"].erase("agi_choices")
	state["run"]["run_over"] = run_over
	state["run"]["stage"] = stage
	var save: SaveSystem = autofree(SaveScript.new())
	return save.migrate({"version": 6, "state": state})


func test_an_aligned_run_gets_the_full_suite_on_every_stage() -> void:
	var m: Dictionary = _migrate_v6("aligned", 5)
	assert_eq(m["run"]["agi_choices"], ["full", "full", "full", "full", "full"])


func test_an_open_sourced_run_gets_the_red_team_on_every_stage() -> void:
	var m: Dictionary = _migrate_v6("open_sourced", 5)
	assert_eq(m["run"]["agi_choices"], ["redteam", "redteam", "redteam", "redteam", "redteam"])


func test_a_rushed_run_gets_ship_it_on_every_stage() -> void:
	var m: Dictionary = _migrate_v6("rushed", 5)
	assert_eq(m["run"]["agi_choices"], ["ship", "ship", "ship", "ship", "ship"])


func test_an_in_progress_run_gets_ship_for_each_stage_reached() -> void:
	var m: Dictionary = _migrate_v6("", 3)
	assert_eq(m["run"]["agi_choices"], ["ship", "ship", "ship"])


func test_a_save_that_already_has_choices_is_left_alone() -> void:
	var state: Dictionary = GameState.new(content, 1).to_dict()
	state["run"]["agi_choices"] = ["full"]
	var save: SaveSystem = autofree(SaveScript.new())
	var m: Dictionary = save.migrate({"version": 6, "state": state})
	assert_eq(m["run"]["agi_choices"], ["full"])
