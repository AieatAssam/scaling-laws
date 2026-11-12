extends GutTest
## Staff hiring amounts: Hiring.max_count (the MAX choice) against Sim.staff_cost, and the AmountPicker row shared by
## the producers and hiring panels (selection, change signal, B-key cycling).

const Support := preload("res://tests/support.gd")

var _content: Node


func before_each() -> void:
	_content = Support.make_content()


func after_each() -> void:
	_content.free()


func _role() -> String:
	return str(_content.get_all("staff")[0].id)


## A state past the first Funding Round (hiring unlocked) with the given equity.
func _unlocked(equity: BigNum) -> GameState:
	var s := Support.new_state(_content)
	s.run["resets_done"][0] = 1
	s.set_cur("equity", equity)
	return s


func test_locked_hiring_has_no_max() -> void:
	var s := Support.new_state(_content)
	s.set_cur("equity", BigNum.from_float(1e30))
	assert_eq(Hiring.max_count(s, _role()), 0, "no Funding Round yet, so no hires")


func test_unknown_role_has_no_max() -> void:
	assert_eq(Hiring.max_count(_unlocked(BigNum.from_float(1e30)), "no_such_role"), 0)


func test_no_equity_means_no_max() -> void:
	assert_eq(Hiring.max_count(_unlocked(BigNum.new()), _role()), 0)


func test_max_is_exact_at_the_cost_boundary() -> void:
	var s := _unlocked(BigNum.new())
	var role := _role()
	s.set_cur("equity", Sim.staff_cost(s, role, 7))
	assert_eq(Hiring.max_count(s, role), 7, "exactly the price of seven buys seven")
	s.set_cur("equity", Sim.staff_cost(s, role, 7).mul_f(0.999))
	assert_eq(Hiring.max_count(s, role), 6, "a little less buys one fewer")


func test_max_is_affordable_and_one_more_is_not() -> void:
	var s := _unlocked(BigNum.from_float(1e100))
	var role := _role()
	var n := Hiring.max_count(s, role)
	assert_gt(n, 100, "a large equity buys many hires")
	assert_true(Sim.staff_cost(s, role, n).compare(s.cur("equity")) <= 0, "the max is affordable")
	assert_true(Sim.staff_cost(s, role, n + 1).compare(s.cur("equity")) > 0, "one more is not")


func test_max_is_capped() -> void:
	var s := _unlocked(BigNum.new(1.0, 1000000000))
	assert_eq(Hiring.max_count(s, _role()), Hiring.MAX_COUNT)


func test_hiring_the_max_succeeds_and_one_more_fails() -> void:
	var s := _unlocked(BigNum.from_float(1e12))
	var role := _role()
	var n := Hiring.max_count(s, role)
	assert_gt(n, 0)
	assert_true(Sim.hire(s, role, n)["ok"], "the max hire goes through")
	assert_false(Sim.hire(s, role, 1)["ok"], "the equity left cannot pay for one more")
