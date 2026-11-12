extends GutTest
## Reset purity. A reset of layer k wipes layers 0..k-1, zeroes layer k's life/clock, grants gain in
## currency k, and keeps everything else: higher layers, run-level flags, and all persistent state.
## A new run keeps persistent state and the legacy currency.

const Support := preload("res://tests/support.gd")

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


## A state with every kind of run and persistent field non-trivially populated.
func _rich_state(resets_before: int) -> GameState:
	var s := Support.new_state(content, 77)
	var L0: Dictionary = s.run["layers"][0]
	var i := 0
	for d in Sim.producers(s):
		i += 1
		L0["owned"][d.id] = i + 2
	for name in GameState.CURRENCY_LAYER:
		s.set_cur(name, BigNum.from_float(37.5 + GameState.CURRENCY_LAYER[name]))
	L0["debt"] = 3.0
	L0["run_mult"] = {"compute": 1.5}
	L0["timed"] = [{"key": "cash", "value": 2.0, "left": 30.0}]
	L0["event_timer"] = 55.0
	var events: Array = content.get_all("events")
	if not events.is_empty():
		L0["cooldowns"] = {events[0].id: 40.0}
	for d in content.get_all("staff"):
		s.run["layers"][1]["staff"][d.id] = 2
	var research_id := Support.first_with_no_prereq(content)
	if research_id != "":
		s.run["layers"][2]["research"] = [research_id]
	s.run["layers"][2]["best"] = 12.0
	for k in 5:
		s.run["layers"][k]["life"] = BigNum.from_float(1000.0 + 10.0 * k)
		s.run["layers"][k]["clock"] = 100.0 + k
	s.run["slider"] = 0.7
	s.run["flags"] = {"seen": true}
	s.run["rivals"] = {"aurora": 0.5}
	s.run["challenges_done"] = ["c1"]
	s.run["stage"] = 2
	for j in 4:
		s.run["resets_done"][j] = 1 if j < resets_before else 0
	s.persist["perm_mult"] = {"compute": 1.3}
	s.persist["legacy_perks"] = {"cash": 2}
	s.persist["automation"] = ["auto_buy"]
	var benches: Array = content.get_all("benchmarks")
	if not benches.is_empty():
		s.persist["benchmarks"] = [benches[0].id]
	s.persist["best_all"] = 9.0
	s.persist["stats"]["time"] = 5000.0
	s.persist["stats"]["trainings"] = 4
	s.persist["settings"]["reduce_motion"] = true
	s.persist["saved_at"] = 123.0
	return s


func test_each_reset_wipes_exactly_the_layers_below_it() -> void:
	for k in range(1, 5):
		var s := _rich_state(k - 1)
		var ld = Sim.layer_def(s, k)
		s.run["layers"][k]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)  # gain 2
		var holding_k := s.cur(ld.currency)
		var before: Dictionary = Support.plain(s.to_dict())

		var r := Sim.perform_reset(s, k)
		assert_true(r["ok"], "reset %d: %s" % [k, str(r.get("reason", ""))])
		var after: Dictionary = Support.plain(s.to_dict())

		for j in k:
			var expect: Dictionary = Support.plain(GameState.fresh_layer())
			if j == 0:
				expect["cur"] = {"cash": Support.plain(BigNum.from_float(GameState.START_CASH))}
			assert_eq(after["run"]["layers"][j], expect, "reset %d wipes layer %d" % [k, j])

		var expect_k: Dictionary = before["run"]["layers"][k].duplicate(true)
		expect_k["life"] = Support.plain(BigNum.new())
		expect_k["clock"] = 0.0
		expect_k["cur"][ld.currency] = Support.plain(holding_k.add(BigNum.from_float(2.0)))
		assert_eq(after["run"]["layers"][k], expect_k, "reset %d keeps layer %d except life/clock/currency" % [k, k])

		for j in range(k + 1, 5):
			assert_eq(after["run"]["layers"][j], before["run"]["layers"][j], "reset %d keeps higher layer %d" % [k, j])

		for key in ["slider", "flags", "rivals", "challenges_done", "stage", "run_over"]:
			assert_eq(after["run"][key], before["run"][key], "run.%s kept by reset %d" % [key, k])

		var expect_resets: Array = before["run"]["resets_done"].duplicate()
		expect_resets[k - 1] = expect_resets[k - 1] + 1
		assert_eq(after["run"]["resets_done"], expect_resets, "resets_done after reset %d" % k)

		var expect_persist: Dictionary = before["persist"].duplicate(true)
		expect_persist["stats"]["resets"] = expect_persist["stats"]["resets"] + 1
		expect_persist["lifetime_resets"][k - 1] = expect_persist["lifetime_resets"][k - 1] + 1
		assert_eq(after["persist"], expect_persist, "persistent state kept by reset %d" % k)
		assert_eq(after["rng"], before["rng"], "reset %d does not touch the RNG" % k)


func test_no_reset_leaves_the_player_without_benefit() -> void:
	for k in range(1, 5):
		var s := _rich_state(k - 1)
		var ld = Sim.layer_def(s, k)
		s.run["layers"][k]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)
		assert_true(Sim.perform_reset(s, k)["ok"])
		assert_true(s.cur("cash").compare(BigNum.from_float(GameState.START_CASH)) == 0, "bootstrap cash after %d" % k)
		var first: ProducerDef = content.get_all("producers")[0]
		assert_true(Sim.cost_for(s, first.id, 1).compare(s.cur("cash")) <= 0, "first producer affordable after %d" % k)
		assert_false(s.persist["perm_mult"].is_empty(), "permanent multipliers kept after %d" % k)
		assert_gte(s.cur(ld.currency).to_float(), 1.0, "currency %d granted" % k)


func test_reset_is_refused_without_enough_life() -> void:
	var s := _rich_state(0)
	var before: Dictionary = Support.plain(s.to_dict())
	var r := Sim.perform_reset(s, 1)
	assert_false(r["ok"])
	assert_eq(Support.plain(s.to_dict()), before, "refused reset changes nothing")


func test_new_run_keeps_persistent_state_and_legacy_currency() -> void:
	var s := _rich_state(4)
	s.run["run_over"] = "rushed"
	var legacy := s.cur("legacy")
	var persist_before: Dictionary = Support.plain(s.persist)

	var r := Sim.new_run(s)
	assert_true(r["ok"])
	assert_eq(s.persist["stats"]["runs"], int(persist_before["stats"]["runs"]) + 1)
	var persist_expect: Dictionary = persist_before.duplicate(true)
	persist_expect["stats"]["runs"] = persist_expect["stats"]["runs"] + 1
	assert_eq(Support.plain(s.persist), persist_expect, "persistent state kept by a new run")
	assert_true(Support.bn_near(s.cur("legacy"), legacy), "legacy currency kept by a new run")
	assert_eq(s.resets(1), 0, "run-level resets wiped")
	assert_eq(s.owned(content.get_all("producers")[0].id), 0, "run-level producers wiped")
	assert_eq(s.run["run_over"], "")


func test_new_run_refused_while_the_run_is_live() -> void:
	var s := _rich_state(0)
	assert_false(Sim.new_run(s)["ok"])
