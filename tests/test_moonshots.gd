extends GutTest
## Moonshots: unlock and start cost, progress (also offline), slots, one check per reward, carry across resets, save and migration.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 1)
	s.set_cur("breakthroughs", BigNum.from_float(1000.0))
	s.set_cur("cash", BigNum.from_float(1.0e12))
	s.set_cur("compute", BigNum.from_float(1.0e12))
	s.run["layers"][0]["owned"]["intern_laptop"] = 1


## Meets a moonshot's own conditions (not its prerequisites) so it can start.
func _meet(id: String) -> void:
	Support.satisfy(s, content.get_def("moonshots", id).conditions)


## Meets a moonshot's conditions and prerequisites, then starts it and runs it to the end.
func _complete(id: String) -> void:
	if Moonshots.done(s, id):
		return
	var d = content.get_def("moonshots", id)
	for p in d.prereqs:
		_complete(p)
	_meet(id)
	assert_true(Moonshots.start(s, id)["ok"], "start %s" % id)
	Moonshots.tick(s, float(d.hours) * 3600.0 + 1.0, [])


## Resets layer k (reaching the layers below it first), as Sim.perform_reset would after a long run.
func _reset(k: int) -> Dictionary:
	for j in range(1, k):
		s.run["resets_done"][j - 1] = maxi(s.resets(j), 1)
	var ld = Sim.layer_def(s, k)
	s.run["layers"][k]["life"] = BigNum.from_float(float(ld.threshold) * 9.0)
	return Sim.perform_reset(s, k)


# ---------------------------------------------------------------- unlock, cost, progress

func test_unlock_and_start_cost() -> void:
	assert_eq(Moonshots.blocker(s, "second_cluster"), "locked")
	_meet("second_cluster")
	assert_eq(Moonshots.blocker(s, "second_cluster"), "")
	var before := s.cur("breakthroughs").to_float()
	assert_true(Moonshots.start(s, "second_cluster")["ok"])
	assert_almost_eq(s.cur("breakthroughs").to_float(), before - 3.5, 1e-9)
	assert_eq(Moonshots.blocker(s, "second_cluster"), "running")


func test_start_needs_breakthroughs_and_prerequisites() -> void:
	assert_eq(Moonshots.blocker(s, "bulk_pricing"), "locked")
	_meet("bulk_pricing")
	assert_eq(Moonshots.blocker(s, "bulk_pricing"), "needs Talent Pipeline")
	_complete("talent_pipeline")
	s.set_cur("breakthroughs", BigNum.from_float(0.5))
	assert_eq(Moonshots.blocker(s, "bulk_pricing"), "not enough breakthroughs")


func test_progress_counts_down_and_completes_offline() -> void:
	_meet("second_cluster")
	Moonshots.start(s, "second_cluster")  # 4 h
	assert_almost_eq(Moonshots.time_left(s, "second_cluster"), 4.0 * 3600.0, 1e-6)
	var evs: Array = []
	Moonshots.tick(s, 3600.0, evs)
	assert_almost_eq(Moonshots.time_left(s, "second_cluster"), 3.0 * 3600.0, 1e-6)
	assert_eq(evs.size(), 0)
	Sim.offline(s, 3.5 * 3600.0)  # away for the rest: finishes at full speed, not at the offline 50%
	assert_true(Moonshots.done(s, "second_cluster"))
	assert_eq(int(s.persist["stats"]["moonshots"]), 1)


# ---------------------------------------------------------------- slots

func test_one_slot_until_second_bay() -> void:
	_meet("talent_pipeline")
	assert_eq(Moonshots.slots(s), 1)
	assert_true(Moonshots.start(s, "talent_pipeline")["ok"])
	_meet("launch_pad")
	assert_eq(Moonshots.blocker(s, "launch_pad"), "no free project slot")


func test_second_bay_gives_a_second_slot() -> void:
	_complete("second_bay")
	assert_eq(Moonshots.slots(s), 2)
	_meet("talent_pipeline")
	assert_true(Moonshots.start(s, "talent_pipeline")["ok"])
	_meet("second_cluster")
	assert_eq(Moonshots.blocker(s, "second_cluster"), "")


# ---------------------------------------------------------------- one check per reward

func test_open_weights_raises_cash_permanently() -> void:
	_complete("open_weights")
	assert_almost_eq(float(s.persist["perm_mult"]["cash"]), 1.1, 1e-9)


func test_launch_pad_shortens_launch_cooldowns() -> void:
	Support.satisfy(s, [{"type": "stat_gte", "id": "trainings", "value": 1}])
	_complete("launch_pad")
	assert_almost_eq(Moonshots.cooldown_mult(s), 0.75, 1e-9)
	assert_true(Launches.fire(s, "ship_demo")["ok"])
	assert_almost_eq(Launches.cooldown_left(s, "ship_demo"), 600.0 * 0.75, 1e-6)


func test_talent_pipeline_makes_hiring_cheaper() -> void:
	_complete("talent_pipeline")
	assert_almost_eq(Moonshots.staff_cost_mult(s), 0.8, 1e-9)


func test_efficient_training_lowers_fail_chance() -> void:
	_complete("efficient_training")
	assert_almost_eq(Moonshots.fail_mult(s), 0.8, 1e-9)


func test_news_desk_keeps_chips_longer() -> void:
	_complete("news_desk")
	assert_almost_eq(Moonshots.chip_mult(s), 1.5, 1e-9)


func test_bulk_pricing_cuts_producer_prices() -> void:
	_complete("bulk_pricing")
	assert_almost_eq(Moonshots.producer_cost_mult(s), 0.9, 1e-9)


func test_data_flywheel_adds_a_desk_slot() -> void:
	var before := Desk.cap(s)
	_complete("data_flywheel")
	assert_eq(Desk.cap(s), before + 1)


func test_funding_and_generation_multipliers_raise_gain() -> void:
	var f := float(Sim.layer_def(s, 1).threshold)
	var g := float(Sim.layer_def(s, 2).threshold)
	_complete("generation_multiplier")
	assert_almost_eq(Moonshots.threshold_for(s, 1, f), f / 1.5625, 1e-9)
	assert_almost_eq(Moonshots.threshold_for(s, 2, g), g / 1.5625, 1e-9)
	assert_almost_eq(Moonshots.threshold_for(s, 3, 7.0), 7.0, 1e-9, "other layers unchanged")


func test_paradigm_dividend_adds_one_breakthrough_per_paradigm_shift() -> void:
	_complete("paradigm_dividend")
	var before := s.cur("breakthroughs").to_float()
	var r := _reset(3)
	assert_true(r["ok"], str(r.get("reason", "")))
	assert_almost_eq(s.cur("breakthroughs").to_float(), before + float(r["gain"]) + 1.0, 1e-6)


func test_agi_surge_boosts_compute_during_a_run() -> void:
	_complete("agi_surge")
	s.run["stage"] = 1
	assert_eq(Moonshots.parts(s, "compute").size(), 1)
	s.run["stage"] = 0
	assert_eq(Moonshots.parts(s, "compute").size(), 0, "not before the AGI road starts")


func test_legacy_tithe_adds_one_legacy_per_singularity() -> void:
	_complete("legacy_tithe")
	assert_eq(Moonshots.bonus_gain(s, 4), 1.0)
	assert_eq(Moonshots.bonus_gain(s, 3), 1.0, "paradigm_dividend is not done here, so Paradigm pays 0 extra")


func test_seed_capital_grants_producers_after_a_funding_round() -> void:
	_complete("seed_capital")
	assert_true(_reset(1)["ok"])
	var ps: Array = content.get_all("producers")
	ps.sort_custom(func(a, b): return a.order < b.order)
	for d in ps.slice(0, 3):
		assert_eq(s.owned(d.id), Moonshots.SEED_OWNED, d.id)


# ---------------------------------------------------------------- carry across a Funding Round

func test_second_cluster_keeps_training_across_a_funding_round() -> void:
	_complete("second_cluster")
	s.run["layers"][0]["training"] = {"id": "pilot_run", "left": 120.0}
	assert_true(_reset(1)["ok"])
	assert_eq(s.run["layers"][0]["training"], {"id": "pilot_run", "left": 120.0})


func test_no_training_carry_without_second_cluster() -> void:
	s.run["layers"][0]["training"] = {"id": "pilot_run", "left": 120.0}
	assert_true(_reset(1)["ok"])
	assert_eq(s.run["layers"][0]["training"], {})


func test_institutional_memory_keeps_early_lab_upgrades() -> void:
	_complete("institutional_memory")
	var keep: Array = []
	var lose: Array = []
	for d in content.get_all("upgrades"):
		if int(d.order) <= Moonshots.LAB_KEEP_ORDER:
			keep.append(d.id)
		else:
			lose.append(d.id)
	assert_true(keep.size() > 0 and lose.size() > 0, "content has upgrades on both sides of the cut")
	s.run["layers"][0]["upgrades"] = keep + lose
	assert_true(_reset(1)["ok"])
	assert_eq(Upgrades.owned_ids(s), keep)


# ---------------------------------------------------------------- persistence and save

func test_moonshots_survive_every_reset_layer() -> void:
	_complete("open_weights")
	for k in range(1, 5):
		assert_true(_reset(k)["ok"], "reset %d" % k)
		assert_true(Moonshots.done(s, "open_weights"), "after reset %d" % k)
	assert_almost_eq(float(s.persist["perm_mult"]["cash"]), 1.1, 1e-9)


func test_running_project_round_trips_through_save_data() -> void:
	_complete("news_desk")
	_meet("second_cluster")
	Moonshots.start(s, "second_cluster")
	var back := GameState.from_dict(content, s.to_dict())
	assert_true(Moonshots.done(back, "news_desk"))
	assert_true(Moonshots.is_running(back, "second_cluster"))
	assert_almost_eq(Moonshots.time_left(back, "second_cluster"), 4.0 * 3600.0, 1e-6)


func test_a_v5_save_gains_empty_moonshot_state() -> void:
	var state: Dictionary = GameState.new(content, 1).to_dict()
	state["persist"].erase("moonshots")
	state["persist"]["stats"].erase("moonshots")
	var save: SaveSystem = autofree(SaveScript.new())
	var migrated: Dictionary = save.migrate({"version": 5, "state": state})
	assert_eq(migrated["persist"]["moonshots"], {"running": [], "done": []})
	assert_eq(int(migrated["persist"]["stats"]["moonshots"]), 0)
	assert_eq(Moonshots.all(GameState.from_dict(content, migrated)).size(), content.get_all("moonshots").size())
