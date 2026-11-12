extends GutTest
## Launch actions: unlocks, cost, timed mod, cooldowns (run-level), same-key replacement, reset, save.

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 5)
	Support.set_cash_float(s, "cash", 1.0e12)
	Support.set_cash_float(s, "compute", 1.0e12)


func test_unlocks_follow_the_progression() -> void:
	assert_eq(Launches.blocker(s, "ship_demo"), "locked")
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	assert_eq(Launches.blocker(s, "ship_demo"), "")
	assert_eq(Launches.blocker(s, "price_cut"), "locked")
	Support.satisfy(s, [{"type": "resets_gte", "layer": 1, "value": 1}])
	assert_eq(Launches.blocker(s, "price_cut"), "")
	assert_eq(Launches.blocker(s, "hackathon"), "locked")
	assert_eq(Launches.blocker(s, "keynote"), "locked")


func test_fire_pays_its_share_and_applies_the_timed_mod() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	var before := s.cur("compute").to_float()
	var r := Launches.fire(s, "ship_demo")
	assert_true(r["ok"])
	assert_almost_eq(s.cur("compute").to_float(), before * 0.98, before * 1e-9)
	assert_almost_eq(Rules.mult(s, "cash"), 1.5, 1e-9)
	assert_eq(Launches.cooldown_left(s, "ship_demo"), 600.0)


func test_cost_is_a_share_of_the_paying_currency() -> void:
	Support.satisfy(s, [{"type": "resets_gte", "layer": 1, "value": 1}])
	var cash := s.cur("cash").to_float()
	Launches.fire(s, "price_cut")
	assert_almost_eq(s.cur("cash").to_float(), cash * 0.9, cash * 1e-9)
	assert_almost_eq(Rules.mult(s, "compute"), 1.3, 1e-9)


func test_cooldown_blocks_until_it_has_run_out() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	Launches.fire(s, "ship_demo")
	assert_eq(Launches.blocker(s, "ship_demo"), "cooling down")
	Launches.tick(s, 599.0)
	assert_eq(Launches.blocker(s, "ship_demo"), "cooling down")
	Launches.tick(s, 1.0)
	assert_eq(Launches.blocker(s, "ship_demo"), "")
	assert_eq(Launches.cooldown_left(s, "ship_demo"), 0.0)


func test_a_timed_mod_on_the_same_key_replaces_the_old_one() -> void:
	Support.satisfy(s, [{"type": "resets_gte", "layer": 1, "value": 1}, {"type": "resets_gte", "layer": 3, "value": 1}])
	Launches.fire(s, "price_cut")
	Launches.fire(s, "keynote")
	var compute_mods := 0
	for t in s.run["layers"][0]["timed"]:
		if t["key"] == "compute":
			compute_mods += 1
			assert_almost_eq(float(t["value"]), 2.0, 1e-9)
	assert_eq(compute_mods, 1)
	var parts := 0
	for p in Rules.mult_parts(s, "compute"):
		if p["id"] == "timed":
			parts += 1
	assert_eq(parts, 1, "one timed factor on compute, not two multiplied together")


func test_timed_mods_expire_with_the_clock() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	Launches.fire(s, "ship_demo")
	Sim.tick(s, 299.0)
	assert_eq(s.run["layers"][0]["timed"].size(), 1, "still running at 299 s")
	Sim.tick(s, 2.0)
	assert_true(s.run["layers"][0]["timed"].is_empty(), "gone after 300 s")


func test_cooldowns_survive_a_funding_round() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	Launches.fire(s, "ship_demo")
	s.run["layers"][1]["life"] = BigNum.from_float(float(Sim.layer_def(s, 1).threshold) * 4.0)
	assert_true(Sim.perform_reset(s, 1)["ok"])
	assert_eq(Launches.cooldown_left(s, "ship_demo"), 600.0)
	assert_eq(Rules.mult(s, "cash"), 1.0, "the timed boost itself is layer 0, so the reset clears it")


func test_auto_launch_fires_only_when_owned_and_ready() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	var evs: Array = []
	Launches.automate(s, evs)
	assert_eq(evs.size(), 0)
	s.persist["automation"].append("auto_launch")
	Launches.automate(s, evs)
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["id"], "ship_demo")
	Launches.automate(s, evs)
	assert_eq(evs.size(), 1, "still cooling down")


func test_cooldown_survives_a_save() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	Launches.fire(s, "ship_demo")
	var restored := GameState.from_dict(content, s.to_dict())
	assert_eq(Launches.cooldown_left(restored, "ship_demo"), 600.0)
	assert_almost_eq(Rules.mult(restored, "cash"), 1.5, 1e-9)
