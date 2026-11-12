extends GutTest
## Reset layers: gain = floor(sqrt(life / threshold)) per layer, prerequisites, highlight rule.

const Support := preload("res://tests/support.gd")

var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 3)


## Gives every lower layer its reset so that layer k is reachable.
func _reach(k: int) -> void:
	for j in range(1, k):
		s.run["resets_done"][j - 1] = maxi(s.resets(j), 1)


func _set_life(k: int, value: float) -> void:
	s.run["layers"][k]["life"] = BigNum.from_float(value)


func test_gain_is_floor_sqrt_of_life_over_threshold_for_every_layer() -> void:
	for k in range(1, 5):
		var ld = Sim.layer_def(s, k)
		assert_not_null(ld, "layer %d def" % k)
		_reach(k)
		for g in [1, 2, 3, 5, 10]:
			_set_life(k, float(ld.threshold) * g * g)
			assert_eq(Sim.reset_preview(s, k)["gain"], g, "layer %d life = %d^2 thresholds" % [k, g])
			# Just short of the next square: still the lower gain.
			_set_life(k, float(ld.threshold) * (g + 1) * (g + 1) * 0.99)
			assert_eq(Sim.reset_preview(s, k)["gain"], g, "layer %d just under %d" % [k, g + 1])
		_set_life(k, float(ld.threshold) * 0.99)
		assert_eq(Sim.reset_preview(s, k)["gain"], 0, "layer %d below threshold" % k)
		assert_false(Sim.reset_preview(s, k)["allowed"])


func test_layer_k_needs_layer_k_minus_one_first() -> void:
	for k in range(2, 5):
		_set_life(k, float(Sim.layer_def(s, k).threshold) * 4.0)
		var p := Sim.reset_preview(s, k)
		assert_false(p["allowed"], "layer %d blocked" % k)
		assert_string_contains(p["reason"], "first")


func test_highlight_when_gain_at_least_twice_holding() -> void:
	for k in range(1, 5):
		var ld = Sim.layer_def(s, k)
		_reach(k)
		_set_life(k, float(ld.threshold) * 16.0)    # gain 4
		var holding := 2.0
		Support.set_cash_float(s, ld.currency, holding)
		assert_true(Sim.reset_preview(s, k)["highlight"], "layer %d: 4 >= 2 x 2" % k)
		Support.set_cash_float(s, ld.currency, 2.01)
		assert_false(Sim.reset_preview(s, k)["highlight"], "layer %d: 4 < 2 x 2.01" % k)


func test_zero_gain_is_never_highlighted() -> void:
	var ld = Sim.layer_def(s, 1)
	_set_life(1, 0.0)
	Support.set_cash_float(s, ld.currency, 0.0)
	var p := Sim.reset_preview(s, 1)
	assert_eq(p["gain"], 0)
	assert_false(p["highlight"])


func test_perform_reset_grants_gain_in_its_currency() -> void:
	for k in range(1, 5):
		var ld = Sim.layer_def(s, k)
		_reach(k)
		_set_life(k, float(ld.threshold) * 9.0)
		var before := s.cur(ld.currency)
		var r := Sim.perform_reset(s, k)
		assert_true(r["ok"], str(r.get("reason", "")))
		assert_eq(r["gain"], 3)
		assert_true(Support.bn_near(s.cur(ld.currency), before.add(BigNum.from_float(3.0))), "layer %d currency" % k)


## Automatic resets follow the highlight rule and the 60 s layer clock only; LayerDef.target_hours is design-only.
func test_auto_reset_ignores_target_hours_and_waits_for_the_minimum_clock() -> void:
	var ld = Sim.layer_def(s, 1)
	ld.target_hours = 1000.0
	_set_life(1, float(ld.threshold) * 4.0)          # gain 2, holding 0: highlighted
	Support.set_cash_float(s, ld.currency, 0.0)
	var evs: Array = []
	s.run["layers"][1]["clock"] = 59.0
	Sim._auto_reset(s, 1, evs)
	assert_eq(evs.size(), 0, "no reset before the minimum clock")
	s.run["layers"][1]["clock"] = 61.0
	Sim._auto_reset(s, 1, evs)
	assert_eq(evs.size(), 1, "one reset after the minimum clock")
	assert_eq(evs[0]["kind"], "reset")
	assert_eq(s.resets(1), 1)


func test_auto_reset_needs_gain_two() -> void:
	var ld = Sim.layer_def(s, 1)
	_set_life(1, float(ld.threshold) * 1.5)          # gain 1: not worth a reset
	Support.set_cash_float(s, ld.currency, 0.0)
	s.run["layers"][1]["clock"] = 600.0
	var evs: Array = []
	Sim._auto_reset(s, 1, evs)
	assert_eq(evs.size(), 0)
