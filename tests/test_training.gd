extends GutTest
## Training runs: the three content-defined run types, spend and fail chance (ops-composed), score maths, refunds,
## best-only ratchet and the permanent compute multiplier.

const Support := preload("res://tests/support.gd")

var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 9)
	Support.set_cash_float(s, "compute", 1e6)


func _training_done(evs: Array) -> Dictionary:
	for e in evs:
		if e["kind"] == "training_done":
			return e
	return {}


func _def(id: String):
	return content.get_def("training_runs", id)


func test_three_run_types_load_in_content_order() -> void:
	var runs: Array = content.get_all("training_runs")
	assert_eq(runs.size(), 3, "three run types")
	var ids := []
	for d in runs:
		ids.append(d.id)
	assert_eq(ids, ["fine_tune", "standard", "frontier"])
	assert_eq(Sim.AUTO_TRAIN_RUN, "standard", "auto_train starts a standard run")


func test_spend_is_the_run_share_of_compute() -> void:
	for d in content.get_all("training_runs"):
		var p := Sim.training_preview(s, d.id)
		assert_true(p["ok"], "%s: %s" % [d.id, p["reason"]])
		assert_true(Support.bn_near(p["spend"], BigNum.from_float(1e6 * float(d.spend_share))), "spend for %s" % d.id)


func test_below_minimum_spend_is_refused() -> void:
	Support.set_cash_float(s, "compute", Sim.MIN_TRAIN_SPEND * 0.5)
	var p := Sim.training_preview(s, "frontier")
	assert_false(p["ok"])
	assert_string_contains(p["reason"], "at least")


func test_start_deducts_spend_and_sets_the_run_length() -> void:
	var r := Sim.start_training(s, "standard")
	assert_true(r["ok"])
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(1e6 * 0.5)), "half compute left")
	assert_eq(s.run["layers"][0]["training"]["left"], _def("standard").seconds)
	assert_eq(s.run["layers"][0]["training"]["type"], "standard")
	assert_false(Sim.start_training(s, "fine_tune")["ok"], "one run at a time")


func test_unknown_run_type_is_refused() -> void:
	var r := Sim.start_training(s, "moonshot")
	assert_false(r["ok"])
	assert_eq(r["reason"], "unknown run type")
	assert_true(s.run["layers"][0]["training"].is_empty())


func test_fail_chance_is_the_base_without_ops() -> void:
	for d in content.get_all("training_runs"):
		var p := Sim.training_preview(s, d.id)
		assert_almost_eq(float(p["fail_chance"]), float(d.fail_chance), 1e-12, "%s base fail" % d.id)
		assert_almost_eq(float(p["fail_factor"]), 1.0, 1e-12)


func test_ops_cut_fail_chance_and_the_cut_is_floored() -> void:
	var base := float(_def("frontier").fail_chance)
	s.run["layers"][1]["staff"]["ops"] = 2
	assert_almost_eq(Sim.training_fail_factor(s), 0.8, 1e-12, "two ops cut 20%")
	assert_almost_eq(float(Sim.training_preview(s, "frontier")["fail_chance"]), base * 0.8, 1e-12)
	s.run["layers"][1]["staff"]["ops"] = 50
	assert_almost_eq(Sim.training_fail_factor(s), Sim.FAIL_FLOOR, 1e-12, "cut never goes below the floor")


func test_fail_chance_rises_with_run_risk() -> void:
	var fine := float(Sim.training_preview(s, "fine_tune")["fail_chance"])
	var std := float(Sim.training_preview(s, "standard")["fail_chance"])
	var front := float(Sim.training_preview(s, "frontier")["fail_chance"])
	assert_lt(fine, std)
	assert_lt(std, front)


func test_duration_is_exact() -> void:
	Sim.start_training(s, "frontier")
	assert_eq(_training_done(Sim.tick(s, 119.5)), {}, "not done early")
	assert_false(_training_done(Sim.tick(s, 0.5)).is_empty(), "done at exactly the run length")
	assert_true(s.run["layers"][0]["training"].is_empty())


func test_success_score_is_log_spend_times_multipliers_within_the_roll() -> void:
	Sim.start_training(s, "frontier")
	s.run["layers"][0]["training"]["fail"] = 0.0
	var log_spend: float = s.run["layers"][0]["training"]["log"]
	var expected := log_spend * Rules.mult(s, "training") * float(_def("frontier").score_mult)
	var e := _training_done(Sim.tick(s, 120.0))
	assert_true(e["ok"])
	var score: float = e["score"]
	assert_between(score, expected * (1.0 - Sim.SCORE_ROLL), expected * (1.0 + Sim.SCORE_ROLL))
	assert_almost_eq(float(s.run["layers"][2]["best"]), score, 1e-12)
	assert_almost_eq(float(s.persist["best_all"]), score, 1e-12)
	assert_eq(s.persist["stats"]["trainings"], 1)
	assert_eq(s.persist["stats"]["failed"], 0)


func test_predicted_score_is_the_score_without_the_roll() -> void:
	var p := Sim.training_preview(s, "standard")
	Sim.start_training(s, "standard")
	s.run["layers"][0]["training"]["fail"] = 0.0
	var score: float = _training_done(Sim.tick(s, 60.0))["score"]
	assert_between(score, float(p["predicted_score"]) * (1.0 - Sim.SCORE_ROLL),
		float(p["predicted_score"]) * (1.0 + Sim.SCORE_ROLL))


func test_bonus_if_success_is_the_bonus_after_the_predicted_score() -> void:
	var p := Sim.training_preview(s, "standard")
	assert_eq(float(p["bonus_now"]), 1.0, "no training yet, no bonus")
	assert_almost_eq(float(p["bonus_if_success"]),
		Rules.training_bonus_for(float(p["predicted_score"]), float(p["predicted_score"])), 1e-12)
	assert_gt(float(p["bonus_if_success"]), float(p["bonus_now"]))


func test_same_seed_gives_same_score() -> void:
	var scores := []
	for seed_value in [5, 5]:
		var st := Support.new_state(content, seed_value)
		Support.set_cash_float(st, "compute", 1e6)
		Sim.start_training(st, "standard")
		scores.append(_training_done(Sim.tick(st, 60.0))["score"])
	assert_eq(scores[0], scores[1])


func test_failure_refunds_half_the_spend_and_scores_nothing() -> void:
	Sim.start_training(s, "standard")
	s.run["layers"][0]["training"]["fail"] = 1.0
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(0.5e6)), "spend taken up front")
	var e := _training_done(Sim.tick(s, 60.0))
	assert_false(e["ok"])
	assert_false(e.has("score"))
	assert_true(Support.bn_near(e["refund"], BigNum.from_float(0.25e6)), "refund is half the spend")
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(0.75e6)), "compute = kept half + refund")
	assert_eq(float(s.run["layers"][2]["best"]), 0.0, "failed run does not score")
	assert_eq(float(s.persist["best_all"]), 0.0)
	assert_eq(s.persist["stats"]["failed"], 1)
	assert_eq(s.persist["stats"]["trainings"], 1)


func test_best_score_only_ratchets_up() -> void:
	s.run["layers"][2]["best"] = 10.0
	s.persist["best_all"] = 10.0
	Sim.start_training(s, "fine_tune")
	s.run["layers"][0]["training"]["fail"] = 0.0
	s.run["layers"][0]["training"]["log"] = 0.5
	Sim.tick(s, 30.0)
	assert_eq(float(s.run["layers"][2]["best"]), 10.0)
	assert_eq(float(s.persist["best_all"]), 10.0)


func test_best_score_is_a_permanent_compute_multiplier() -> void:
	var m0 := Rules.mult(s, "compute")
	assert_eq(m0, 1.0, "no training, no bonus")
	s.run["layers"][2]["best"] = 10.0
	var m1 := Rules.mult(s, "compute")
	assert_gt(m1, m0)
	s.run["layers"][2]["best"] = 20.0
	assert_gt(Rules.mult(s, "compute"), m1)
	# The all-time best carries over to later generations as a further bonus.
	s.persist["best_all"] = 20.0
	var m2 := Rules.mult(s, "compute")
	s.persist["best_all"] = 0.0
	assert_gt(m2, Rules.mult(s, "compute"))
