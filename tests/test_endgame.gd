extends GutTest
## Singularity finale (src/core/endgame.gd): AGI safety choices, evaluations, majority ending, rival race,
## challenge tiers and recklessness. Deterministic: outcomes that are random use fixed seeds.

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState


class Stub:
	var id := "stub"
	var weight := 2.0
	var category := "incident"
	var value := 0.0


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 1)
	s.set_cur("compute", BigNum.from_float(1.0e12))
	s.set_cur("cash", BigNum.from_float(1.0e12))


func _ready_stages(n: int) -> void:
	s.run["stage"] = n


# ---------------------------------------------------------------- majority and endings

func test_majority_counts_and_breaks_ties_by_most_recent() -> void:
	assert_eq(Endgame.majority([]), "")
	assert_eq(Endgame.majority(["full", "full", "ship"]), "full")
	assert_eq(Endgame.majority(["full", "redteam"]), "redteam", "tie: the later choice wins")
	assert_eq(Endgame.majority(["full", "redteam", "full", "redteam"]), "redteam")
	assert_eq(Endgame.majority(["ship", "full", "ship", "full", "redteam"]), "full", "tie of 2: full is later")


func test_each_method_maps_to_its_ending() -> void:
	assert_eq(Endgame.ending_for(s, "full").id, "aligned")
	assert_eq(Endgame.ending_for(s, "redteam").id, "open_sourced")
	assert_eq(Endgame.ending_for(s, "ship").id, "rushed")
	s.run["agi_choices"] = ["ship", "ship", "full"]
	assert_eq(Endgame.trajectory(s), Endgame.ending_for(s, "ship").title)


# ---------------------------------------------------------------- choices and evaluations

func test_no_choice_without_a_waiting_stage() -> void:
	var r := Endgame.start_choice(s, "ship")
	assert_false(r["ok"])
	assert_eq(r["reason"], "no AGI stage is waiting for a choice")
	assert_eq(Endgame.pending_index(s), -1)


func test_ship_it_clears_the_stage_at_once() -> void:
	_ready_stages(1)
	assert_eq(Endgame.pending_index(s), 0)
	var r := Endgame.start_choice(s, "ship")
	assert_true(r["ok"])
	assert_eq(s.run["agi_choices"], ["ship"])
	assert_eq(int(s.persist["stats"]["ships"]), 1)
	assert_eq(Endgame.pending_index(s), -1)
	assert_true(s.run["eval"].is_empty())


func test_unknown_method_is_refused() -> void:
	_ready_stages(1)
	assert_eq(Endgame.start_choice(s, "vibes")["reason"], "unknown method")


func test_full_suite_takes_twelve_hours_and_runs_offline_at_full_speed() -> void:
	_ready_stages(1)
	assert_true(Endgame.start_choice(s, "full")["ok"])
	assert_almost_eq(float(s.run["eval"]["left"]), 43200.0, 1e-9)
	Sim.offline(s, 43200.0)
	assert_true(s.run["eval"].is_empty(), "finished at full speed, not at the offline 50%")
	var choices: Array = s.run["agi_choices"]
	assert_true(choices == ["full"] or float(s.run["eval_cooldown"]) > 0.0)


func test_red_team_takes_six_hours() -> void:
	_ready_stages(1)
	Endgame.start_choice(s, "redteam")
	var evs: Array = []
	Endgame.tick(s, 21599.0, evs)
	assert_false(s.run["eval"].is_empty())
	Endgame.tick(s, 1.0, evs)
	assert_true(s.run["eval"].is_empty())
	assert_eq(int(s.persist["redteam_uses"]), 1, "every red-team run counts, pass or fail")


func test_agi_peak_requirements_survive_lower_layer_wipes_and_unlock_sequentially() -> void:
	s.run["layers"][0]["owned"]["server_rack"] = 20
	s.run["layers"][2]["best"] = 5.0
	s.set_cur("energy", BigNum.from_float(90.0))
	Endgame.track_peaks(s)
	s.run["layers"][0]["owned"].clear()
	s.run["layers"][2]["best"] = 0.0
	s.set_cur("energy", BigNum.new())
	assert_true(Rules.check(s, Endgame.stage_conditions(s, 1)[0]))
	assert_true(Rules.check(s, Endgame.stage_conditions(s, 0)[0]))
	s.run["peak_compute_rate"] = 1.1e11
	assert_true(Rules.check(s, Endgame.stage_conditions(s, 2)[0]))
	assert_true(Rules.check(s, Endgame.stage_conditions(s, 3)[0]))
	assert_true(Rules.check(s, Endgame.stage_conditions(s, 4)[0]))
	assert_gte(Rules.condition_progress(s, Endgame.stage_conditions(s, 1)[0]), 1.0)
	s.run["stage"] = 0
	var evs: Array = []
	Endgame.unlock_stages(s, evs)
	assert_eq(int(s.run["stage"]), 1, "only the next uncleared stage may unlock")


func test_full_suite_failure_sets_the_cooldown() -> void:
	for seed_value in range(1, 60):
		var st := Support.new_state(content, seed_value)
		st.run["stage"] = 1
		Endgame.start_choice(st, "full")
		var evs: Array = []
		Endgame.tick(st, 43200.0, evs)
		var failed := false
		for e in evs:
			failed = failed or e["kind"] == "agi_failed"
		if failed:
			assert_almost_eq(float(st.run["eval_cooldown"]), 3600.0, 1e-9)
			assert_eq(Endgame.choice_blocker(st, "full"), "full suite cooling down")
			assert_eq(Endgame.choice_blocker(st, "redteam"), "", "other methods stay open")
			assert_eq(st.run["agi_choices"], [], "a failed stage is not cleared")
			return
	fail_test("no failing full-suite run among seeds 1-59")


func test_full_suite_chance_follows_slider_and_ops() -> void:
	s.run["slider"] = 0.0
	s.run["layers"][1]["staff"].erase("ops")
	assert_almost_eq(Endgame.pass_chance(s, "full"), 0.5, 1e-9)
	s.run["slider"] = 0.5
	assert_almost_eq(Endgame.pass_chance(s, "full"), 0.7, 1e-9)
	s.run["layers"][1]["staff"]["ops"] = 5
	assert_almost_eq(Endgame.pass_chance(s, "full"), 0.8, 1e-9)
	s.run["slider"] = 1.0
	s.run["layers"][1]["staff"]["ops"] = 50
	assert_almost_eq(Endgame.pass_chance(s, "full"), 0.97, 1e-9, "capped at 97%")
	assert_almost_eq(Endgame.pass_chance(s, "redteam"), 0.7, 1e-9)
	assert_almost_eq(Endgame.pass_chance(s, "ship"), 1.0, 1e-9)


func test_running_evaluation_blocks_another_choice() -> void:
	_ready_stages(2)
	Endgame.start_choice(s, "redteam")
	assert_eq(Endgame.start_choice(s, "ship")["reason"], "an evaluation is already running")


# ---------------------------------------------------------------- ending after five stages

func test_five_ship_choices_end_the_run_as_rushed() -> void:
	_ready_stages(5)
	var evs: Array = []
	for i in 5:
		assert_true(Endgame.start_choice(s, "ship")["ok"])
	evs = []
	Endgame.tick(s, 0.0, evs)
	assert_eq(s.run["run_over"], "rushed")
	assert_eq(int(s.persist["stats"]["solo_ship"]), 1, "unanimous: counted as a solo finish")
	assert_eq(Endgame.start_choice(s, "full")["reason"], "the run is over")


# ---------------------------------------------------------------- deterministic routes to each ending

func test_each_method_reaches_its_ending() -> void:
	for m in Endgame.METHODS:
		var st := Support.new_state(content, 3)
		st.run["stage"] = 5
		var guard := 0
		while String(st.run["run_over"]) == "" and guard < 400:
			guard += 1
			var evs: Array = []
			if st.run["eval"].is_empty():
				if not Endgame.start_choice(st, m)["ok"]:
					Endgame.tick(st, 3600.0, evs)
					continue
			Endgame.tick(st, 28800.0, evs)
		assert_eq(st.run["run_over"], Endgame.ending_for(st, m).id, m)


# ---------------------------------------------------------------- rival race

func test_rival_races_from_its_target_stage() -> void:
	var aurora = content.get_def("rivals", "aurora")
	assert_eq(aurora.outpace_stage, 2)
	_ready_stages(1)
	assert_false(Endgame.racing(s, aurora))
	assert_eq(Endgame.race_eta(s, "aurora"), INF)
	_ready_stages(2)
	assert_true(Endgame.racing(s, aurora))
	assert_almost_eq(Endgame.race_eta(s, "aurora"), 6.0 * 3600.0, 1e-6)


func test_rival_launches_when_its_clock_runs_out() -> void:
	_ready_stages(2)
	var evs: Array = []
	Endgame.tick(s, 6.0 * 3600.0 - 1.0, evs)
	assert_eq(evs.size(), 0)
	Endgame.tick(s, 2.0, evs)
	assert_eq(evs[0]["kind"], "rival_launched")
	assert_false(Endgame.racing(s, content.get_def("rivals", "aurora")))


func test_redteam_runs_speed_every_rival_for_good() -> void:
	s.persist["redteam_uses"] = 2
	assert_almost_eq(Endgame.rival_speed(s, "aurora"), 1.1, 1e-9)


func test_clearing_the_target_stage_first_outpaces_the_rival() -> void:
	_ready_stages(2)
	Endgame.start_choice(s, "ship")
	var r := Endgame.start_choice(s, "ship")
	assert_true(r["ok"])
	var kinds: Array = []
	for e in r["events"]:
		kinds.append(e["kind"])
	assert_true("rival_outpaced" in kinds)
	assert_true(s.run["flags"].get("outpaced_aurora", false))
	assert_true(s.persist["records"]["outpaced"].has("aurora"))
	assert_false(Endgame.racing(s, content.get_def("rivals", "aurora")))


func test_outship_adds_delay_for_growing_compute_and_is_capped() -> void:
	_ready_stages(2)
	s.set_cur("compute", BigNum.from_float(1.0e12))
	assert_true(Endgame.outship(s, "aurora")["ok"])
	assert_almost_eq(float(s.run["race"]["delay"]["aurora"]), 0.5, 1e-9)
	assert_eq(Endgame.outship(s, "aurora")["reason"], "cooling down")
	s.run["race"]["cool"].clear()
	assert_true(Endgame.outship(s, "aurora")["ok"])
	assert_almost_eq(float(s.run["race"]["delay"]["aurora"]), 0.75, 1e-9)
	for i in 10:
		s.run["race"]["cool"].clear()
		s.set_cur("compute", BigNum.from_float(1.0e30))
		Endgame.outship(s, "aurora")
	var delay := float(s.run["race"]["delay"]["aurora"])
	assert_true(delay < Endgame.OUTSHIP_MAX, "never reaches the +100% ceiling")
	assert_true(delay > 0.99, "diminishing returns close in on it")
	assert_almost_eq(Endgame.launch_seconds(s, "aurora"), 6.0 * 3600.0 * (1.0 + delay), 1e-3)


func test_outship_costs_compute_and_needs_enough() -> void:
	_ready_stages(2)
	s.set_cur("compute", BigNum.from_float(10.0))
	assert_eq(Endgame.outship(s, "aurora")["reason"], "not enough compute")
	s.set_cur("compute", BigNum.from_float(2.0e6))
	Endgame.outship(s, "aurora")
	assert_almost_eq(s.cur("compute").to_float(), 1.0e6, 1.0)


func test_acqui_hire_is_once_per_rival_and_slows_it() -> void:
	_ready_stages(2)
	var before: int = int(s.run["layers"][1]["staff"].get("researcher", 0))
	assert_true(Endgame.acqui(s, "aurora")["ok"])
	assert_eq(int(s.run["layers"][1]["staff"]["researcher"]), before + 1)
	assert_almost_eq(Endgame.rival_speed(s, "aurora"), 0.75, 1e-9)
	s.run["race"]["cool"].clear()
	assert_eq(Endgame.acqui(s, "aurora")["reason"], "already acquired")


func test_acqui_hire_has_a_shared_cooldown() -> void:
	_ready_stages(3)
	Endgame.acqui(s, "aurora")
	assert_eq(Endgame.acqui(s, "helix")["reason"], "cooling down")


# ---------------------------------------------------------------- challenge tiers

func test_tier_two_needs_tier_one_passed() -> void:
	assert_eq(Endgame.tier_blocker(s, "eu_ai_audit_t2"), "pass EU AI Audit first")
	Records.note(s.persist, "challenges", "eu_ai_audit")
	assert_eq(Endgame.tier_blocker(s, "eu_ai_audit_t2"), "")
	assert_eq(Endgame.tier_blocker(s, "eu_ai_audit"), "", "tier one is always open")


func test_challenge_wins_count_once_per_tier() -> void:
	var d = content.get_def("challenges", "eu_ai_audit_t2")
	Endgame.challenge_won(s, d)
	Endgame.challenge_won(s, d)
	assert_eq(int(s.persist["stats"]["tier_2"]), 1)
	assert_eq(int(s.persist["stats"].get("tier_1", 0)), 0)


func test_challenge_multipliers_share_a_cap_of_1_4() -> void:
	s.persist["challenge_mult"] = 1.3
	var e := Endgame.challenge_effect(s, {"type": "perm_mult", "key": "cash", "value": 1.2})
	assert_almost_eq(float(e["value"]), 1.4 / 1.3, 1e-9)
	assert_almost_eq(float(s.persist["challenge_mult"]), 1.4, 1e-9)
	var again := Endgame.challenge_effect(s, {"type": "perm_mult", "key": "cash", "value": 1.2})
	assert_almost_eq(float(again["value"]), 1.0, 1e-9, "nothing left to add")


func test_non_permanent_challenge_rewards_are_untouched() -> void:
	var e := {"type": "add_currency", "id": "cash", "value": 5.0}
	assert_eq(Endgame.challenge_effect(s, e), e)


# ---------------------------------------------------------------- recklessness

func test_ship_it_makes_bad_events_costlier_not_likelier() -> void:
	_ready_stages(2)
	Endgame.start_choice(s, "ship")
	Endgame.start_choice(s, "ship")
	assert_eq(Endgame.reckless(s), 2)
	var bad := Stub.new()
	assert_almost_eq(Endgame.event_weight(s, bad), 2.0, 1e-9, "pool weight is unchanged")
	assert_almost_eq(Endgame.rival_speed(s, "aurora"), 1.0 + Endgame.RECK_RIVAL * 2.0, 1e-9)
	var good := Stub.new()
	good.category = "news"
	var debt := {"type": "add_debt", "value": 10.0}
	assert_eq(Endgame.event_effect(s, bad, debt), debt, "debt is production: never made worse")
	var slide := {"type": "add_slider", "value": -0.1}
	assert_almost_eq(float(Endgame.event_effect(s, bad, slide)["value"]), -0.15, 1e-9, "alignment loss x1.5")
	s.run["slider"] = 0.35
	assert_almost_eq(float(Endgame.event_effect(s, bad, {"type": "add_slider", "value": -0.2})["value"]), -0.05, 1e-9,
		"recklessness cannot push alignment below the debt threshold")
	var equity := {"type": "add_currency", "id": "equity", "value": -1.0}
	assert_eq(Endgame.event_effect(s, bad, equity), equity, "equity losses cannot block engineer hires")
	var compute := {"type": "add_currency", "id": "compute", "value": -1000.0}
	assert_eq(Endgame.event_effect(s, bad, compute), compute, "compute is production: never made worse")
	var timed := {"type": "timed_mod", "key": "rate", "value": 0.5, "seconds": 60.0}
	assert_eq(Endgame.event_effect(s, bad, timed), timed, "timed production loss is never made worse")
	assert_eq(Endgame.event_effect(s, good, slide), slide, "news events are not made worse")


func test_ship_it_cuts_the_next_stage_requirement_by_thirty_percent() -> void:
	var plain: Array = Endgame.stage_conditions(s, 1)
	assert_eq(int(plain[0]["value"]), 20, "agentic coding needs 20 server racks")
	_ready_stages(1)
	assert_true(Endgame.start_choice(s, "ship")["ok"])
	var cut: Array = Endgame.stage_conditions(s, 1)
	assert_eq(int(cut[0]["value"]), 14, "30% off: 14 racks")
	assert_eq(int(Endgame.stage_conditions(s, 1, "full")[0]["value"]), 34, "preview uses the method that will clear the prior stage")
	var gate := Endgame.stage_conditions(s, 4)
	assert_almost_eq(float(gate[0]["value"]), 1e11 * 0.7, 1e-3, "compute rate cut too")
	assert_eq(gate[1]["type"], "resets_gte", "reset gates are never cut")
	assert_eq(int(gate[1]["value"]), 1)
	s.run["agi_choices"] = ["full"]
	assert_eq(int(Endgame.stage_conditions(s, 1)[0]["value"]), 34, "full suite raises the next numeric requirement by 70%")
	assert_almost_eq(float(Endgame.stage_conditions(s, 3)[0]["value"]), Sim.ENERGY_CAP, 1e-3, "scaled energy cannot exceed its 100-unit cap")
	assert_almost_eq(float(Endgame.stage_conditions(s, 4)[0]["value"]), 1e11 * 1.7, 1e-3, "full suite raises the final rate gate too")
	s.run["agi_choices"] = ["redteam"]
	assert_eq(int(Endgame.stage_conditions(s, 1)[0]["value"]), 20, "red-team leaves the next requirement at baseline")


func test_ending_pays_its_legacy() -> void:
	var st := Support.new_state(content, 3)
	st.run["stage"] = 5
	var before := st.cur("legacy").to_float()
	for i in 5:
		Endgame.start_choice(st, "ship")
	assert_eq(st.run["run_over"], "rushed")
	assert_almost_eq(st.cur("legacy").to_float() - before, float(content.get_def("endings", "rushed").legacy_payout), 1e-9)


func test_no_ship_it_choices_leave_events_alone() -> void:
	var bad := Stub.new()
	assert_almost_eq(Endgame.event_weight(s, bad), 2.0, 1e-9)
	var debt := {"type": "add_debt", "value": 10.0}
	assert_eq(Endgame.event_effect(s, bad, debt), debt)


# ---------------------------------------------------------------- save round trip

func test_endgame_state_round_trips_through_save_data() -> void:
	_ready_stages(2)
	Endgame.start_choice(s, "full")
	s.run["race"]["delay"]["aurora"] = 0.5
	s.run["race"]["acqui"].append("helix")
	var back := GameState.from_dict(content, s.to_dict())
	assert_eq(back.run["agi_choices"], [])
	assert_eq(back.run["eval"]["method"], "full")
	assert_almost_eq(float(back.run["race"]["delay"]["aurora"]), 0.5, 1e-9)
	assert_eq(back.run["race"]["acqui"], ["helix"])
