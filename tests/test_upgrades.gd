extends GutTest
## Lab upgrades: unlocks, purchase, effects through tier_mult / cost_for / Rules.mult_parts / training, reset, automation, save.

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 3)
	Support.set_cash_float(s, "cash", 1.0e12)


func test_unlock_needs_the_tier_owned_one_ten_or_twenty_five() -> void:
	assert_eq(Upgrades.blocker(s, "intern_laptop_double"), "locked: needs 1 Intern Laptop")
	Support.set_owned(s, "intern_laptop", 1)
	assert_eq(Upgrades.blocker(s, "intern_laptop_double"), "")
	assert_eq(Upgrades.blocker(s, "intern_laptop_synergy"), "locked: needs 10 Intern Laptop")
	Support.set_owned(s, "intern_laptop", 10)
	assert_eq(Upgrades.blocker(s, "intern_laptop_synergy"), "")
	assert_eq(Upgrades.blocker(s, "intern_laptop_cost"), "locked: needs 25 Intern Laptop")


func test_buy_pays_once_and_refuses_a_second_time() -> void:
	Support.set_owned(s, "intern_laptop", 1)
	var before := s.cur("cash").to_float()
	var r := Upgrades.buy(s, "intern_laptop_double")
	assert_true(r["ok"])
	assert_true(Upgrades.is_owned(s, "intern_laptop_double"))
	assert_almost_eq(s.cur("cash").to_float(), before - 80.0, 1e-6)
	assert_eq(Upgrades.buy(s, "intern_laptop_double")["reason"], "already bought")


func test_buy_refuses_without_cash() -> void:
	Support.set_owned(s, "intern_laptop", 1)
	Support.set_cash_float(s, "cash", 1.0)
	assert_eq(Upgrades.buy(s, "intern_laptop_double")["reason"], "not enough cash")
	assert_false(Upgrades.is_owned(s, "intern_laptop_double"))


func test_double_doubles_the_tier_output() -> void:
	Support.set_owned(s, "intern_laptop", 4)
	var base := Sim.producer_raw_rate(s, "intern_laptop").to_float()
	Upgrades.buy(s, "intern_laptop_double")
	assert_almost_eq(Sim.producer_raw_rate(s, "intern_laptop").to_float(), base * 2.0, base * 1e-9)
	assert_eq(Upgrades.tier_mult(s, "intern_laptop"), 2.0)


func test_synergy_adds_one_percent_per_unit_of_the_source_and_caps_at_double() -> void:
	Support.set_owned(s, "intern_laptop", 10)
	Support.set_owned(s, "cloud_gpus", 30)
	Upgrades.buy(s, "intern_laptop_synergy")
	assert_almost_eq(Upgrades.tier_mult(s, "intern_laptop"), 1.30, 1e-9)
	Support.set_owned(s, "cloud_gpus", 500)
	assert_almost_eq(Upgrades.tier_mult(s, "intern_laptop"), 2.0, 1e-9)
	var tip := Upgrades.tier_parts(s, "intern_laptop")
	assert_eq(tip.size(), 1)
	assert_eq(tip[0]["id"], "intern_laptop_synergy")


func test_cost_upgrade_cuts_the_tier_price_by_ten_percent() -> void:
	Support.set_owned(s, "intern_laptop", 25)
	var full := Sim.cost_for(s, "intern_laptop", 1).to_float()
	Upgrades.buy(s, "intern_laptop_cost")
	assert_almost_eq(Upgrades.cost_mult(s, "intern_laptop"), 0.9, 1e-9)
	assert_almost_eq(Sim.cost_for(s, "intern_laptop", 1).to_float(), full * 0.9, full * 1e-9)


func test_revenue_upgrade_shows_as_a_cash_factor_in_mult_parts() -> void:
	Support.set_owned(s, "data_centre", 1)
	Upgrades.buy(s, "enterprise_tier")
	var found := false
	for p in Rules.mult_parts(s, "cash"):
		if p["id"] == "enterprise_tier":
			found = true
			assert_almost_eq(float(p["value"]), 1.25, 1e-9)
	assert_true(found)
	assert_almost_eq(Rules.mult(s, "cash"), 1.25, 1e-9)


func test_train_speed_shortens_the_run_length_in_the_preview() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	var rid: String = s.db.get_all("training_runs")[0].id
	var raw := float(s.db.get_def("training_runs", rid).seconds)
	Upgrades.buy(s, "faster_checkpoints")
	assert_almost_eq(float(Sim.training_preview(s, rid)["seconds"]), raw * 0.9, 1e-9)
	assert_true(Rules.mult_parts(s, "train_speed").size() > 0)


func test_upgrades_are_run_scoped_and_a_funding_round_wipes_them() -> void:
	Support.set_owned(s, "intern_laptop", 1)
	Upgrades.buy(s, "intern_laptop_double")
	var ld = Sim.layer_def(s, 1)
	s.run["layers"][1]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)
	var r := Sim.perform_reset(s, 1)
	assert_true(r["ok"])
	assert_eq(Upgrades.owned_ids(s), [])
	assert_eq(Upgrades.tier_mult(s, "intern_laptop"), 1.0)


func test_persistent_state_is_untouched_by_a_reset() -> void:
	Support.set_owned(s, "intern_laptop", 1)
	Upgrades.buy(s, "intern_laptop_double")
	var stats_before: Dictionary = s.persist["stats"].duplicate(true)
	s.run["layers"][1]["life"] = BigNum.from_float(float(Sim.layer_def(s, 1).threshold) * 4.0)
	Sim.perform_reset(s, 1)
	assert_eq(s.persist["stats"]["resets"], stats_before["resets"] + 1, "the reset itself is counted")
	assert_eq(s.persist["stats"]["runs"], stats_before["runs"])
	assert_eq(s.persist["perm_mult"], stats_before.get("perm_mult", s.persist["perm_mult"]))


func test_auto_upgrade_buys_every_unlocked_upgrade_only_when_owned() -> void:
	Support.set_owned(s, "intern_laptop", 25)
	var evs: Array = []
	Upgrades.automate(s, evs)
	assert_eq(Upgrades.owned_ids(s).size(), 0, "no automation, no buying")
	s.persist["automation"].append("auto_upgrade")
	Upgrades.automate(s, evs)
	assert_eq(Upgrades.owned_ids(s).size(), 3, "the three intern upgrades unlocked at 25 owned")
	assert_eq(evs.size(), 3)
	assert_true(evs[0]["auto"])


func test_late_producer_tiers_each_have_three_lab_upgrades() -> void:
	for id in ["lunar_foundry", "dyson_swarm", "matrioshka_brain", "universe_simulator"]:
		var tier_upgrades: Array = content.get_all("upgrades").filter(func(d): return d.target == id)
		assert_eq(tier_upgrades.size(), 3, "%s has double, synergy and cost upgrades" % id)


func test_save_round_trip_keeps_upgrades_and_their_effect() -> void:
	Support.set_owned(s, "intern_laptop", 1)
	Upgrades.buy(s, "intern_laptop_double")
	var restored := GameState.from_dict(content, s.to_dict())
	assert_eq(Upgrades.owned_ids(restored), ["intern_laptop_double"])
	assert_eq(Upgrades.tier_mult(restored, "intern_laptop"), 2.0)
