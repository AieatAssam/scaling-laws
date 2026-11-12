extends GutTest
## Training runs: cost, duration, score, failure path and the permanent multiplier.

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


func test_cost_is_a_fraction_of_compute() -> void:
	for frac in [0.25, 0.5, 1.0]:
		var p := Sim.training_preview(s, frac)
		assert_true(p["ok"], "frac %s: %s" % [frac, p["reason"]])
		assert_true(Support.bn_near(p["spend"], BigNum.from_float(1e6 * frac)), "spend for frac %s" % frac)


func test_below_minimum_spend_is_refused() -> void:
	Support.set_cash_float(s, "compute", Sim.MIN_TRAIN_SPEND * 0.5)
	var p := Sim.training_preview(s, 1.0)
	assert_false(p["ok"])
	assert_string_contains(p["reason"], "at least")


func test_start_deducts_exact_spend_and_sets_duration() -> void:
	var r := Sim.start_training(s, 0.5)
	assert_true(r["ok"])
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(1e6 * 0.5)), "half compute left")
	assert_eq(s.run["layers"][0]["training"]["left"], Sim.TRAIN_SECONDS)
	assert_false(Sim.start_training(s, 0.25)["ok"], "one run at a time")


func test_invalid_fraction_is_refused() -> void:
	assert_false(Sim.start_training(s, 0.3)["ok"])


func test_fail_chance_is_shown_up_front_and_rises_with_spend() -> void:
	var last := -1.0
	for frac in [0.25, 0.5, 1.0]:
		var fc: float = Sim.training_preview(s, frac)["fail_chance"]
		assert_almost_eq(fc, Sim.FAIL_BASE + Sim.FAIL_PER_FRAC * frac, 1e-12)
		assert_gt(fc, last)
		last = fc


func test_duration_is_exact() -> void:
	Sim.start_training(s, 1.0)
	assert_eq(_training_done(Sim.tick(s, Sim.TRAIN_SECONDS - 0.5)), {}, "not done early")
	assert_false(_training_done(Sim.tick(s, 0.5)).is_empty(), "done at exactly TRAIN_SECONDS")
	assert_true(s.run["layers"][0]["training"].is_empty())


func test_success_scores_by_log_spend_with_bounded_noise() -> void:
	Sim.start_training(s, 1.0)
	s.run["layers"][0]["training"]["fail"] = 0.0
	var log_spend: float = s.run["layers"][0]["training"]["log"]
	var e := _training_done(Sim.tick(s, Sim.TRAIN_SECONDS))
	assert_true(e["ok"])
	var score: float = e["score"]
	assert_between(score, log_spend * 0.95, log_spend * 1.05)
	assert_almost_eq(float(s.run["layers"][2]["best"]), score, 1e-12)
	assert_almost_eq(float(s.persist["best_all"]), score, 1e-12)
	assert_eq(s.persist["stats"]["trainings"], 1)
	assert_eq(s.persist["stats"]["failed"], 0)


func test_same_seed_gives_same_score() -> void:
	var scores := []
	for seed_value in [5, 5]:
		var st := Support.new_state(content, seed_value)
		Support.set_cash_float(st, "compute", 1e6)
		Sim.start_training(st, 0.5)
		scores.append(_training_done(Sim.tick(st, Sim.TRAIN_SECONDS))["score"])
	assert_eq(scores[0], scores[1])


func test_failure_path_records_failure_and_keeps_the_spend() -> void:
	Sim.start_training(s, 1.0)
	s.run["layers"][0]["training"]["fail"] = 1.0
	var spent_to := s.cur("compute")
	var e := _training_done(Sim.tick(s, Sim.TRAIN_SECONDS))
	assert_false(e["ok"])
	assert_false(e.has("score"))
	assert_eq(float(s.run["layers"][2]["best"]), 0.0, "failed run does not score")
	assert_eq(float(s.persist["best_all"]), 0.0)
	assert_eq(s.persist["stats"]["failed"], 1)
	assert_eq(s.persist["stats"]["trainings"], 1)
	assert_true(Support.bn_near(s.cur("compute"), spent_to), "compute is not refunded")


func test_best_score_only_ratchets_up() -> void:
	s.run["layers"][2]["best"] = 10.0
	s.persist["best_all"] = 10.0
	Sim.start_training(s, 0.25)
	s.run["layers"][0]["training"]["fail"] = 0.0
	s.run["layers"][0]["training"]["log"] = 0.5
	Sim.tick(s, Sim.TRAIN_SECONDS)
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
