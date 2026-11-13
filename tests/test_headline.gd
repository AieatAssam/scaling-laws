extends GutTest

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content)


func test_fresh_game_headline() -> void:
	var h := Rules.headline(s)
	assert_true(h["scale"] is BigNum)
	assert_eq(h["stage_name"], "Garage")
	assert_eq(h["currency"], "equity")
	assert_eq(h["line"], "0 +0 on reset")
	assert_false(h["highlight"])


func test_mid_funding_uses_equity_and_shared_worth_it_rule() -> void:
	s.run["layers"][1]["life"] = BigNum.from_float(4.0e7)
	s.set_cur("equity", BigNum.from_float(1.0))
	var h := Rules.headline(s)
	assert_eq(h["currency"], "equity")
	assert_eq(h["line"], "1.00 +2.00 on reset")
	assert_true(h["highlight"])


func test_frontier_moves_after_each_layer_unlock() -> void:
	for resets in [[0, 0, 0, 0], [1, 0, 0, 0], [1, 1, 0, 0], [1, 1, 1, 0]]:
		s.run["resets_done"] = resets.duplicate()
		var h := Rules.headline(s)
		assert_eq(h["currency"], ["equity", "insights", "breakthroughs", "legacy"][resets.count(1)])
		assert_true(h["line"].ends_with("on reset"))


func test_agi_road_shows_stage_progress_and_trajectory() -> void:
	s.run["resets_done"] = [1, 1, 1, 1]
	s.run["stage"] = 1
	s.run["agi_choices"] = ["redteam"]
	var h := Rules.headline(s)
	assert_eq(h["currency"], "agi")
	assert_eq(h["line"], "AGI 2/5 0% (open)")
	assert_false(h["highlight"])
