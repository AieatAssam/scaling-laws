extends GutTest
## Economy: producer cost curve, buy 1 / 10 / max exactness, milestone multipliers, production and cash revenue.

const Support := preload("res://tests/support.gd")

var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 42)


## Previous tier owned so that `id` is buyable.
func _unlock(id: String) -> void:
	var list: Array = Sim.producers(s)
	for i in list.size():
		if list[i].id == id and i > 0:
			Support.set_owned(s, list[i - 1].id, maxi(s.owned(list[i - 1].id), 1))


func test_cost_is_base_times_growth_to_the_owned() -> void:
	for d in Sim.producers(s):
		for n in [0, 1, 7, 25, 60]:
			Support.set_owned(s, d.id, n)
			var expected: float = float(d.base_cost) * pow(Sim.COST_GROWTH, n)
			assert_almost_eq(Sim.cost_for(s, d.id, 1).to_float(), expected, expected * 1e-9, "%s owned %d" % [d.id, n])


func test_buy_one_pays_exactly_the_next_unit() -> void:
	var d = Sim.producers(s)[0]
	Support.set_owned(s, d.id, 3)
	var cost := Sim.cost_for(s, d.id, 1)
	s.set_cur("cash", cost.mul_f(10.0))  # same magnitude as the cost, so the subtraction is exact
	var before := s.cur("cash")
	var r := Sim.buy_producer(s, d.id, 1)
	assert_true(r["ok"])
	assert_eq(s.owned(d.id), 4)
	assert_true(Support.bn_near(before.subtract(s.cur("cash")), cost))


func test_buy_ten_costs_the_same_as_ten_single_buys() -> void:
	var d = Sim.producers(s)[0]
	var s2 := Support.new_state(content, 42)
	for st in [s, s2]:
		Support.set_cash_float(st, "cash", 1e30)
	var expected := Sim.cost_for(s, d.id, 10)
	var r := Sim.buy_producer(s, d.id, 10)
	assert_true(r["ok"])
	assert_eq(r["count"], 10)
	assert_true(Support.bn_near(r["cost"], expected), "buy 10 reports the closed-form cost")
	for i in 10:
		assert_true(Sim.buy_producer(s2, d.id, 1)["ok"])
	assert_eq(s.owned(d.id), s2.owned(d.id))
	assert_true(Support.bn_near(s.cur("cash"), s2.cur("cash")), "cash after 10 vs 10x1")


func test_buy_max_is_the_largest_affordable_count() -> void:
	for d in Sim.producers(s):
		_unlock(d.id)
		Support.set_owned(s, d.id, 5)
		s.set_cur("cash", Sim.cost_for(s, d.id, 3).mul_f(1.5))  # enough for a few units of every tier
		var m := Sim.max_affordable(s, d.id)
		assert_true(m >= 1, "%s affordable" % d.id)
		assert_true(Sim.cost_for(s, d.id, m).compare(s.cur("cash")) <= 0, "%s: %d fits" % [d.id, m])
		assert_true(Sim.cost_for(s, d.id, m + 1).compare(s.cur("cash")) > 0, "%s: %d+1 does not" % [d.id, m])
		var r := Sim.buy_producer(s, d.id, -1)
		assert_true(r["ok"])
		assert_eq(r["count"], m, "%s buy max count" % d.id)
		assert_eq(Sim.max_affordable(s, d.id), 0)


func test_buy_with_no_cash_fails() -> void:
	var d = Sim.producers(s)[0]
	s.set_cur("cash", BigNum.new())  # a fresh run starts with START_CASH, which can buy the first tier
	var r := Sim.buy_producer(s, d.id, -1)
	assert_false(r["ok"])
	assert_eq(s.owned(d.id), 0)


func test_locked_tier_cannot_be_bought() -> void:
	var list: Array = Sim.producers(s)
	if list.size() < 2:
		pending("needs at least two producers")
		return
	Support.set_cash_float(s, "cash", 1e30)
	var r := Sim.buy_producer(s, list[1].id, 1)
	assert_false(r["ok"])
	assert_string_contains(r["reason"], "locked")


func test_milestones_double_output_at_each_threshold() -> void:
	var d = Sim.producers(s)[0]
	var top: int = Sim.MILESTONES.max() + 2
	for n in range(1, top + 1):
		Support.set_owned(s, d.id, n)
		var doublings := 0
		for m in Sim.MILESTONES:
			if n >= m:
				doublings += 1
		var expected: float = float(d.base_output) * n * pow(2.0, doublings)
		assert_almost_eq(Sim.raw_rate(s).to_float(), expected, expected * 1e-9, "owned %d" % n)


func test_production_and_cash_revenue_follow_the_formulas() -> void:
	var i := 0
	var expected_raw := 0.0
	for d in Sim.producers(s):
		i += 1
		Support.set_owned(s, d.id, i)
		var m := 1.0
		for ms in Sim.MILESTONES:
			if i >= ms:
				m *= 2.0
		expected_raw += float(d.base_output) * i * m
	assert_almost_eq(Sim.compute_per_second(s).to_float(), expected_raw, expected_raw * 1e-9)
	assert_almost_eq(Sim.cash_per_second(s).to_float(), expected_raw * Sim.REVENUE, expected_raw * 1e-9)

	var cash0 := s.cur("cash")
	var compute0 := s.cur("compute")
	Sim.tick(s, 10.0)
	var compute_gain := s.cur("compute").subtract(compute0)
	var cash_gain := s.cur("cash").subtract(cash0)
	assert_almost_eq(compute_gain.to_float(), expected_raw * 10.0, expected_raw * 1e-6)
	assert_true(Support.bn_near(cash_gain, compute_gain.mul_f(Sim.REVENUE), 1e-6), "cash = compute * REVENUE")


func test_perm_multipliers_scale_compute_and_cash_independently() -> void:
	var d = Sim.producers(s)[0]
	Support.set_owned(s, d.id, 10)
	var base_c := Sim.compute_per_second(s).to_float()
	var base_k := Sim.cash_per_second(s).to_float()
	s.persist["perm_mult"]["compute"] = 2.0
	assert_almost_eq(Sim.compute_per_second(s).to_float(), base_c * 2.0, base_c * 1e-9)
	assert_almost_eq(Sim.cash_per_second(s).to_float(), base_k * 2.0, base_k * 1e-9)
	s.persist["perm_mult"]["cash"] = 1.5
	assert_almost_eq(Sim.cash_per_second(s).to_float(), base_k * 3.0, base_k * 1e-9)
	assert_almost_eq(Sim.compute_per_second(s).to_float(), base_c * 2.0, base_c * 1e-9)


func test_compute_rate_condition_reads_output_not_held_compute() -> void:
	# AGI stages are rate-based: a huge held stock with no producers must not pass, a real output rate must.
	var cond := {"type": "compute_rate_gte", "value": 1000.0}
	s.set_cur("compute", BigNum.from_float(1e30))
	assert_false(Rules.check(s, cond), "held compute alone does not sustain a rate")
	var first = Sim.producers(s)[0]
	Support.set_owned(s, first.id, ceili(1000.0 / float(first.base_output)))
	assert_true(Rules.check(s, cond), "a producer rate of 1000/s sustains the requirement")
