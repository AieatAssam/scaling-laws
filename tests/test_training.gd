extends GutTest
## Training runs: the three content-defined run types, spend and fail chance (ops-composed), score maths, refunds,
## best-only ratchet, the permanent compute multiplier, the cash burst on success, and the shared pick rule.

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
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(1e6 * (1.0 - _def("standard").spend_share))), "the rest of compute left")
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
	var secs := float(_def("frontier").seconds)
	Sim.start_training(s, "frontier")
	assert_eq(_training_done(Sim.tick(s, secs - 0.5)), {}, "not done early")
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
	var share := float(_def("standard").spend_share)
	Sim.start_training(s, "standard")
	s.run["layers"][0]["training"]["fail"] = 1.0
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(1e6 * (1.0 - share))), "spend taken up front")
	var e := _training_done(Sim.tick(s, 60.0))
	assert_false(e["ok"])
	assert_false(e.has("score"))
	assert_true(Support.bn_near(e["refund"], BigNum.from_float(1e6 * share * Sim.REFUND_SHARE)), "refund is half the spend")
	assert_true(Support.bn_near(s.cur("compute"), BigNum.from_float(1e6 * (1.0 - share * (1.0 - Sim.REFUND_SHARE)))),
		"compute = kept rest + refund")
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


# ---------------------------------------------------------------- cash burst and pick rule

## A state that earns cash: one producer tier owned, so the cash rate is above zero (bursts are a multiple of it).
func _earning_state(seed_value: int = 9) -> GameState:
	var st := Support.new_state(content, seed_value)
	Support.set_cash_float(st, "compute", 1e6)
	Support.set_owned(st, Sim.producers(st)[0].id, 10)
	assert_gt(Sim.cash_per_second(st).to_float(), 0.0, "the test state earns cash")
	return st


func test_success_pays_revenue_seconds_of_cash_rate() -> void:
	var st := _earning_state()
	var rate := Sim.cash_per_second(st)
	var cash0 := st.cur("cash")
	Sim.start_training(st, "standard")
	st.run["layers"][0]["training"]["fail"] = 0.0
	var e := _training_done(Sim.tick(st, 60.0))
	assert_true(e["ok"])
	assert_true(Support.bn_near(e["revenue"], rate.mul_f(_def("standard").revenue_seconds)), "burst = 12 s of rate")
	# Cash gained this tick = 60 s of income + the burst.
	var gained := st.cur("cash").subtract(cash0)
	assert_true(Support.bn_near(gained, rate.mul_f(60.0 + _def("standard").revenue_seconds)), "burst is added to cash")


func test_burst_counts_in_every_layer_life_like_income() -> void:
	var st := _earning_state()
	var rate := Sim.cash_per_second(st)
	Sim.start_training(st, "fine_tune")
	st.run["layers"][0]["training"]["fail"] = 0.0
	var before := []
	for k in range(1, 5):
		before.append(st.run["layers"][k]["life"])
	Sim.tick(st, 30.0)
	var burst := rate.mul_f(_def("fine_tune").revenue_seconds)
	for k in range(1, 5):
		var gained: BigNum = (st.run["layers"][k]["life"] as BigNum).subtract(before[k - 1])
		assert_true(Support.bn_near(gained, rate.mul_f(30.0).add(burst)), "layer %d life counts income and burst" % k)


func test_failure_pays_no_burst() -> void:
	var st := _earning_state()
	var rate := Sim.cash_per_second(st)
	var cash0 := st.cur("cash")
	Sim.start_training(st, "standard")
	st.run["layers"][0]["training"]["fail"] = 1.0
	var e := _training_done(Sim.tick(st, 60.0))
	assert_false(e["ok"])
	assert_true((e["revenue"] as BigNum).is_zero(), "no burst on failure")
	assert_true(Support.bn_near(st.cur("cash").subtract(cash0), rate.mul_f(60.0)), "only income, no burst")


func test_frontier_pays_no_burst() -> void:
	var st := _earning_state()
	assert_true((Sim.training_preview(st, "frontier")["revenue"] as BigNum).is_zero(), "preview: no burst")
	Sim.start_training(st, "frontier")
	st.run["layers"][0]["training"]["fail"] = 0.0
	var e := _training_done(Sim.tick(st, 120.0))
	assert_true(e["ok"])
	assert_true((e["revenue"] as BigNum).is_zero(), "payout: no burst")


func test_preview_revenue_is_the_payout_when_the_rate_is_unchanged() -> void:
	for id in ["fine_tune", "standard"]:
		var st := _earning_state()
		var p := Sim.training_preview(st, id)
		assert_eq(float(p["revenue_seconds"]), _def(id).revenue_seconds, "%s: preview seconds" % id)
		Sim.start_training(st, id)
		st.run["layers"][0]["training"]["fail"] = 0.0
		var e := _training_done(Sim.tick(st, float(_def(id).seconds)))
		assert_true(Support.bn_near(e["revenue"], p["revenue"]), "%s: preview matches payout" % id)


func test_offline_burst_is_scaled_like_offline_income() -> void:
	var st := _earning_state()
	var rate := Sim.cash_per_second(st)
	Sim.start_training(st, "fine_tune")
	st.run["layers"][0]["training"]["fail"] = 0.0
	var e := _training_done(Sim.tick(st, 30.0, true))
	assert_true(Support.bn_near(e["revenue"], rate.mul_f(_def("fine_tune").revenue_seconds * Sim.OFFLINE_EFF)),
		"offline: burst at the offline efficiency")


func test_run_started_before_the_burst_existed_pays_none() -> void:
	var st := _earning_state()
	Sim.start_training(st, "standard")
	st.run["layers"][0]["training"].erase("revenue_seconds")  # a save from before this field
	st.run["layers"][0]["training"]["fail"] = 0.0
	var e := _training_done(Sim.tick(st, 60.0))
	assert_true(e["ok"])
	assert_true((e["revenue"] as BigNum).is_zero())


func test_save_round_trip_mid_run_pays_the_same_burst() -> void:
	var st := _earning_state()
	Sim.start_training(st, "standard")
	st.run["layers"][0]["training"]["fail"] = 0.0
	Sim.tick(st, 20.0)
	var st2 := GameState.from_dict(content, JSON.parse_string(JSON.stringify(Support.plain(st.to_dict()))))
	assert_eq(st2.run["layers"][0]["training"]["revenue_seconds"], _def("standard").revenue_seconds)
	var a := _training_done(Sim.tick(st, 40.0))
	var b := _training_done(Sim.tick(st2, 40.0))
	assert_true(Support.bn_near(a["revenue"], b["revenue"]), "same burst after reload")
	assert_false((a["revenue"] as BigNum).is_zero(), "and it is paid")


func test_pick_is_standard_with_no_ops_and_nothing_to_beat() -> void:
	# Frontier fails 30% at 0 Ops, over the risk cap; standard predicts above the empty best.
	assert_eq(Sim.pick_training(_earning_state()), "standard")


func test_pick_is_frontier_once_ops_make_it_safe_enough() -> void:
	var st := _earning_state()
	st.run["layers"][1]["staff"]["ops"] = 4  # 30% x 0.6 = 18%, under the 20% cap
	assert_eq(Sim.pick_training(st), "frontier")


func test_standard_is_chased_when_it_only_matches_the_best() -> void:
	# Standard's chase_margin is 0: predicting just above the best is enough (frontier is risk-blocked at 0 Ops).
	var st := _earning_state()
	var pred := float(Sim.training_preview(st, "standard")["predicted_score"])
	st.run["layers"][2]["best"] = pred * 0.99
	assert_eq(Sim.pick_training(st), "standard")


func test_frontier_is_not_chased_inside_its_own_margin() -> void:
	# Frontier needs 3% over the best (chase_margin 0.03). Predicting 2% over is not enough, so it falls to cash.
	var st := _earning_state()
	st.run["layers"][1]["staff"]["ops"] = 4  # safe enough on fail rate, so only the margin can stop it
	var pred := float(Sim.training_preview(st, "frontier")["predicted_score"])
	st.run["layers"][2]["best"] = pred / 1.02
	assert_eq(Sim.pick_training(st), "fine_tune")


func test_pick_is_fine_tune_for_cash_when_nothing_beats_the_best() -> void:
	var st := _earning_state()
	st.run["layers"][2]["best"] = 1e9
	assert_eq(Sim.pick_training(st), "fine_tune")


func test_risk_blocked_frontier_picks_standard_when_standard_is_near_the_best() -> void:
	# Frontier fails 30% at 0 Ops, over the cap. Standard predicts inside PICK_NEAR_BEST below the best, so it is
	# picked over the cash run; further below the best, cash wins.
	var st := _earning_state()
	var pred := float(Sim.training_preview(st, "standard")["predicted_score"])
	st.run["layers"][2]["best"] = pred / (1.0 - 0.5 * Sim.PICK_NEAR_BEST)
	assert_eq(Sim.pick_training(st), "standard")
	st.run["layers"][2]["best"] = pred / (1.0 - 1.5 * Sim.PICK_NEAR_BEST)
	assert_eq(Sim.pick_training(st), "fine_tune", "outside the near band, cash wins")


func test_pick_is_empty_with_no_compute() -> void:
	var st := _earning_state()
	st.set_cur("compute", BigNum.new())
	assert_eq(Sim.pick_training(st), "")


func test_auto_train_starts_the_picked_run() -> void:
	var st := _earning_state()
	st.run["layers"][2]["best"] = 1e9
	st.persist["automation"] = ["auto_train"]
	var evs := Sim.tick(st, 1.0)
	var auto := {}
	for e in evs:
		if e["kind"] == "auto_train":
			auto = e
	assert_eq(auto.get("id", ""), "fine_tune", "auto_train reports the run it started")
	assert_eq(st.run["layers"][0]["training"]["type"], "fine_tune")


func test_reset_mid_run_drops_the_run_and_pays_no_burst() -> void:
	var st := _earning_state()
	Sim.start_training(st, "standard")
	var ld = Sim.layer_def(st, 1)
	st.run["layers"][1]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)  # gain 2
	var r := Sim.perform_reset(st, 1)
	assert_true(r["ok"], "the Funding Round reset is allowed")
	assert_true((st.run["layers"][0]["training"] as Dictionary).is_empty(), "the run in flight is wiped")
	assert_eq(int(st.persist["stats"]["trainings"]), 0, "no run was finished")
	assert_true(Support.bn_near(st.cur("cash"), BigNum.from_float(GameState.START_CASH)), "cash is the bootstrap amount, no burst")
	assert_eq(_training_done(Sim.tick(st, 120.0)), {}, "nothing finishes after the reset")
