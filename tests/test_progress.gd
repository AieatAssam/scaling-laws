extends GutTest
## Goal progress (Rules.condition_progress, next_goals) and reset ETA (Rules.reset_eta). Pure core, headless.

const Support := preload("res://tests/support.gd")

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _all_conditions() -> Array:
	var out: Array = []
	for type in ["benchmarks", "agi_stages", "events", "endings", "help"]:
		for d in content.get_all(type):
			for c in d.conditions:
				out.append(c)
	return out


func _has(goals: Array, kind: String, id: String) -> bool:
	for g in goals:
		if g["kind"] == kind and g["id"] == id:
			return true
	return false


func _goal(goals: Array, kind: String, id: String) -> Dictionary:
	for g in goals:
		if g["kind"] == kind and g["id"] == id:
			return g
	return {}


func _earning(owned: int = 5) -> GameState:
	var s := Support.new_state(content, 1)
	Support.set_owned(s, Sim.producers(s)[0].id, owned)
	return s


# ---------------------------------------------------------------- condition_progress

## Every condition the content uses, on a fresh state, a rich state and a state where it holds: progress is in
## 0..1, is exactly 1 only when check() passes, and never reads 1 for a near miss.
func test_progress_bounds_and_agrees_with_check() -> void:
	var fresh := Support.new_state(content, 3)
	var rich := Support.new_state(content, 3)
	rich.set_cur("cash", BigNum.from_float(1e9))
	rich.set_cur("compute", BigNum.from_float(1e12))
	rich.run["resets_done"][0] = 1
	rich.run["layers"][2]["best"] = 4.0
	for d in content.get_all("producers"):
		rich.run["layers"][0]["owned"][d.id] = 3
	for c in _all_conditions():
		for s in [fresh, rich]:
			var p := Rules.condition_progress(s, c)
			assert_true(p >= 0.0 and p <= 1.0, "progress in 0..1 for %s" % str(c))
			assert_eq(p == 1.0, Rules.check(s, c), "1.0 exactly when it holds: %s" % str(c))
		var met := Support.new_state(content, 3)
		Support.satisfy(met, [c])
		assert_eq(Rules.condition_progress(met, c) == 1.0, Rules.check(met, c), "satisfied: %s" % str(c))


func test_currency_progress_is_log_scale() -> void:
	var s := Support.new_state(content, 1)
	s.set_cur("cash", BigNum.from_float(1000.0))
	# log10(1001) / log10(1000001) is about 0.5: half the orders of magnitude climbed.
	assert_almost_eq(Rules.condition_progress(s, {"type": "currency_gte", "id": "cash", "value": 1000000.0}), 0.5, 0.01)


func test_count_progress_is_linear_and_capped_below_one() -> void:
	var s := _earning(5)
	assert_almost_eq(Rules.condition_progress(s, {"type": "owned_gte", "id": Sim.producers(s)[0].id, "value": 20}), 0.25, 1e-9)
	Support.set_owned(s, Sim.producers(s)[0].id, 19)
	assert_almost_eq(Rules.condition_progress(s, {"type": "owned_gte", "id": Sim.producers(s)[0].id, "value": 20}), 0.95, 1e-9)


func test_conditions_progress_is_the_minimum() -> void:
	var s := _earning(5)
	var id: String = Sim.producers(s)[0].id
	var conds: Array = [{"type": "owned_gte", "id": id, "value": 20}, {"type": "owned_gte", "id": id, "value": 10}]
	assert_almost_eq(Rules.conditions_progress(s, conds), 0.25, 1e-9)  # min(5/20, 5/10)
	assert_eq(Rules.conditions_progress(s, []), 1.0)


# ---------------------------------------------------------------- next_goals

func test_next_goals_shape_count_and_order() -> void:
	var s := Support.new_state(content, 1)
	var goals := Rules.next_goals(s, 3)
	assert_eq(goals.size(), 3)
	for g in goals:
		assert_true(g.has("kind") and g.has("id") and g.has("title") and g.has("progress") and g.has("hint"))
		assert_true(float(g["progress"]) >= 0.0 and float(g["progress"]) <= 1.0)
	# Sorted by progress, with a big goal (reset, new tier, AGI stage) counted BIG_BONUS higher.
	var all := Rules.next_goals(s, 1000)
	for i in range(1, all.size()):
		assert_true(_rank(all[i - 1]) >= _rank(all[i]) - 1e-9, "rank order at %d" % i)


func _rank(g: Dictionary) -> float:
	return float(g["progress"]) + (Rules.BIG_BONUS if Rules.BIG_KINDS.has(g["kind"]) else 0.0)


func test_next_goals_fresh_state_has_first_tier_and_funding_reset() -> void:
	var s := Support.new_state(content, 1)
	var goals := Rules.next_goals(s, 1000)
	var first: String = Sim.producers(s)[0].id
	assert_true(_has(goals, "producer", first), "first tier is the next producer")
	assert_true(_has(goals, "reset", "funding"), "funding reset is reachable")
	assert_false(_has(goals, "reset", "generation"), "generation waits for the funding reset")
	assert_false(_has(goals, "agi", content.get_all("agi_stages")[0].id), "no AGI goal before Singularity is reachable")


func test_next_goals_drop_earned_benchmarks_and_reached_resets() -> void:
	var s := Support.new_state(content, 1)
	var bench = content.get_all("benchmarks")[0]
	assert_true(_has(Rules.next_goals(s, 1000), "benchmark", bench.id), "locked benchmark is a goal")
	s.persist["benchmarks"].append(bench.id)
	assert_false(_has(Rules.next_goals(s, 1000), "benchmark", bench.id), "earned benchmark is not")
	s.run["resets_done"][0] = 1
	assert_true(_has(Rules.next_goals(s, 1000), "reset", "generation"), "Models reset opens after the funding reset")


func test_next_goals_milestone_and_agi() -> void:
	var s := _earning(3)
	var first: String = Sim.producers(s)[0].id
	var m := _goal(Rules.next_goals(s, 1000), "milestone", first)
	assert_almost_eq(float(m["progress"]), 3.0 / 25.0, 1e-9, "next milestone is 25 owned")
	var agi_id: String = content.get_all("agi_stages")[0].id
	assert_false(_has(Rules.next_goals(s, 1000), "agi", agi_id))
	s.run["resets_done"][3] = 1  # Paradigm done: Singularity is reachable
	assert_true(_has(Rules.next_goals(s, 1000), "agi", agi_id), "current AGI stage once Singularity is reachable")


# ---------------------------------------------------------------- reset_eta

func test_reset_eta_without_income_is_infinite() -> void:
	var s := Support.new_state(content, 1)
	var e := Rules.reset_eta(s, 1)
	assert_true(is_inf(e["worth_in"]) and is_inf(e["next_in"]), "no producers, no income")
	assert_false(e["worth_now"])


func test_reset_eta_time_to_worth_and_next_gain_match_rate() -> void:
	var s := _earning()
	var rate := Sim.cash_per_second(s).to_float()
	var T := float(Sim.layer_def(s, 1).threshold)
	# Holding 0: worth it at gain 2 (life 4T); the next gain (1) comes at life T.
	var e := Rules.reset_eta(s, 1)
	assert_almost_eq(e["worth_in"] * rate, 4.0 * T, 1e-6 * 4.0 * T)
	assert_almost_eq(e["next_in"] * rate, T, 1e-6 * T)


func test_reset_eta_uses_ceil_of_double_holding() -> void:
	var s := _earning()
	var T := float(Sim.layer_def(s, 1).threshold)
	var rate := Sim.cash_per_second(s).to_float()
	# 2 x 2.3 = 4.6, so gain 5 is needed (life 25T). Without the ceiling, 4.6^2 = 21.2T would look reached.
	s.set_cur("equity", BigNum.from_float(2.3))
	s.run["layers"][1]["life"] = BigNum.from_float(22.0 * T)  # gain 4: not worth it yet
	assert_false(Sim.reset_preview(s, 1)["highlight"])
	var e := Rules.reset_eta(s, 1)
	assert_almost_eq(e["worth_in"] * rate, 3.0 * T, 1e-6 * 3.0 * T)


func test_reset_eta_zero_at_the_worth_it_point() -> void:
	var s := _earning()
	var T := float(Sim.layer_def(s, 1).threshold)
	s.set_cur("equity", BigNum.from_float(2.3))
	s.run["layers"][1]["life"] = BigNum.from_float(25.0 * T)
	assert_true(Sim.reset_preview(s, 1)["highlight"], "reset_preview agrees: worth it")
	var e := Rules.reset_eta(s, 1)
	assert_true(e["worth_now"])
	assert_eq(e["worth_in"], 0.0)
	s.run["layers"][1]["life"] = BigNum.from_float(25.0 * T * (1.0 - 1e-6))
	assert_false(Sim.reset_preview(s, 1)["highlight"])
	assert_false(Rules.reset_eta(s, 1)["worth_now"])
