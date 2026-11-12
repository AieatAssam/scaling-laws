extends GutTest
## Breaking news: spawn timing, chip life, hold, reward bounds, content weights, benchmarks, seed, save.

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 11)
	Support.set_owned(s, "intern_laptop", 10)   # income > 0, so headlines may spawn
	s.run["news"]["timer"] = 0.0


func _chip(id: String) -> void:
	s.run["news"]["chip"] = {"id": id, "left": News.CHIP_SECONDS}
	s.run["news"]["timer"] = 1.0e6


func _chip_empty() -> bool:
	return (s.run["news"]["chip"] as Dictionary).is_empty()


func test_spawns_once_the_timer_runs_out_and_waits_at_least_ninety_seconds() -> void:
	var evs: Array = []
	News.tick(s, 1.0, evs, false)
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["kind"], "news")
	assert_false(_chip_empty())
	assert_gte(float(s.run["news"]["timer"]), News.MIN_GAP)


func test_chip_stays_for_fifteen_seconds() -> void:
	News.tick(s, 1.0, [], false)
	News.tick(s, 14.0, [], false)
	assert_false(_chip_empty())
	News.tick(s, 1.0, [], false)
	assert_true(_chip_empty())


func test_no_spawn_without_income() -> void:
	Support.set_owned(s, "intern_laptop", 0)
	News.tick(s, 1.0, [], false)
	assert_true(_chip_empty())


func test_hold_offline_or_in_a_modal_clears_the_chip_and_freezes_the_timer() -> void:
	News.tick(s, 1.0, [], false)
	var timer: float = s.run["news"]["timer"]
	var evs: Array = []
	News.tick(s, 60.0, evs, true)
	assert_true(_chip_empty())
	assert_eq(float(s.run["news"]["timer"]), timer)
	assert_eq(evs.size(), 0)


func test_modal_and_offline_ticks_never_spawn() -> void:
	var evs := Sim.tick(s, 5.0, false, true)
	for e in evs:
		assert_ne(e["kind"], "news")
	assert_true(_chip_empty())
	Sim.offline(s, 3600.0)
	assert_true(_chip_empty())


func test_cash_reward_is_thirty_to_ninety_seconds_of_income() -> void:
	_chip("news_01")
	var rate := Sim.cash_per_second(s).to_float()
	var before := s.cur("cash").to_float()
	var r := News.catch(s)
	assert_true(r["ok"])
	assert_between(float(r["seconds"]), 30.0, 90.0)
	assert_between(s.cur("cash").to_float() - before, rate * 30.0 - 1e-6, rate * 90.0 + 1e-6)
	assert_true(_chip_empty())


func test_compute_reward_is_thirty_to_ninety_seconds_of_compute() -> void:
	_chip("news_09")
	var rate := Sim.compute_per_second(s).to_float()
	var r := News.catch(s)
	assert_true(r["ok"])
	assert_between(s.cur("compute").to_float(), rate * 30.0 - 1e-6, rate * 90.0 + 1e-6)


func test_double_cash_doubles_cash_for_thirty_seconds() -> void:
	_chip("news_17")
	News.catch(s)
	assert_almost_eq(Rules.mult(s, "cash"), 2.0, 1e-9)
	Sim.tick(s, 29.0)
	assert_almost_eq(Rules.mult(s, "cash"), 2.0, 1e-9)
	Sim.tick(s, 1.0)
	assert_almost_eq(Rules.mult(s, "cash"), 1.0, 1e-9)


func test_viral_moment_is_seven_times_cash_for_fifteen_seconds() -> void:
	_chip("news_22")
	News.catch(s)
	assert_almost_eq(Rules.mult(s, "cash"), 7.0, 1e-9)
	Sim.tick(s, 15.0)
	assert_almost_eq(Rules.mult(s, "cash"), 1.0, 1e-9)


func test_missing_costs_nothing_and_catch_counts_once() -> void:
	News.tick(s, 1.0, [], false)
	var cash := s.cur("cash").to_float()
	News.tick(s, 15.0, [], false)
	assert_eq(s.cur("cash").to_float(), cash)
	assert_false(News.catch(s)["ok"], "nothing to catch once it has faded")
	assert_eq(int(s.persist["stats"]["news"]), 0)
	_chip("news_01")
	News.catch(s)
	assert_eq(int(s.persist["stats"]["news"]), 1)


func test_content_has_twenty_headlines_and_a_five_percent_viral_share() -> void:
	var pool: Array = s.db.get_all("news")
	assert_gte(pool.size(), 20)
	var total := 0.0
	var viral := 0.0
	for d in pool:
		total += float(d.weight)
		if d.reward == "viral":
			viral += float(d.weight)
	assert_almost_eq(viral / total, 0.05, 1e-9)


func test_news_benchmarks_unlock_at_ten_hundred_and_five_hundred() -> void:
	for pair in [["news_10", 10], ["news_100", 100], ["news_500", 500]]:
		var b = s.db.get_def("benchmarks", pair[0])
		assert_not_null(b)
		assert_eq(int(b.conditions[0]["value"]), pair[1])
	s.persist["stats"]["news"] = 100
	var evs: Array = []
	Sim._benchmarks(s, evs)
	var ids: Array = []
	for e in evs:
		ids.append(e["id"])
	assert_true("news_10" in ids)
	assert_true("news_100" in ids)
	assert_false("news_500" in ids)


func test_spawns_are_reproducible_from_the_seed() -> void:
	var a := Support.new_state(content, 42)
	var b := Support.new_state(content, 42)
	for x in [a, b]:
		Support.set_owned(x, "intern_laptop", 10)
		x.run["news"]["timer"] = 0.0
		News.tick(x, 1.0, [], false)
	assert_eq(a.run["news"]["chip"], b.run["news"]["chip"])


func test_chip_and_timer_survive_a_save() -> void:
	News.tick(s, 1.0, [], false)
	var restored := GameState.from_dict(content, s.to_dict())
	assert_eq(restored.run["news"], s.run["news"])
