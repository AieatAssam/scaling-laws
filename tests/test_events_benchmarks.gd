extends GutTest
## Events and benchmarks: condition evaluation, choice effects, alignment debt, benchmark unlock + bonus.
## Expectations come from the content defs and the documented effect semantics, not from hard-coded values.

const Support := preload("res://tests/support.gd")

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _fresh(seed_value: int = 5) -> GameState:
	return Support.new_state(content, seed_value)


func _def(type: String, id: String):
	return content.get_def(type, id)


## Plain numbers for every field an effect can touch.
func _snap(s: GameState) -> Dictionary:
	var cur := {}
	for name in GameState.CURRENCY_LAYER:
		cur[name] = s.cur(name).to_float()
	return {
		"cur": cur, "debt": float(s.run["layers"][0]["debt"]), "slider": float(s.run["slider"]),
		"flags": s.run["flags"].duplicate(), "timed": s.run["layers"][0]["timed"].size(),
		"run_mult": s.run["layers"][0]["run_mult"].duplicate(), "perm_mult": s.persist["perm_mult"].duplicate(),
		"rivals": s.run["rivals"].duplicate(),
	}


## Reference semantics of each effect type (docs/API.md), applied to a snapshot.
func _apply_ref(snap: Dictionary, e: Dictionary) -> void:
	match e["type"]:
		"add_currency":
			snap["cur"][e["id"]] = maxf(0.0, snap["cur"].get(e["id"], 0.0) + float(e["value"]))
		"add_debt":
			snap["debt"] = maxf(0.0, snap["debt"] + float(e["value"]))
		"add_slider":
			snap["slider"] = clampf(snap["slider"] + float(e["value"]), 0.0, 1.0)
		"add_flag":
			snap["flags"][e["id"]] = true
		"timed_mod":
			snap["timed"] += 1
		"run_mult":
			snap["run_mult"][e["key"]] = snap["run_mult"].get(e["key"], 1.0) * float(e["value"])
		"perm_mult":
			snap["perm_mult"][e["key"]] = snap["perm_mult"].get(e["key"], 1.0) * float(e["value"])
		"rival_progress":
			snap["rivals"][e["id"]] = snap["rivals"].get(e["id"], 0.0) + float(e["value"])
		_:
			fail_test("unknown effect " + e["type"])


func _assert_snap_matches(got: Dictionary, want: Dictionary, what: String) -> void:
	for name in want["cur"]:
		assert_almost_eq(got["cur"][name], want["cur"][name], 1e-9 * maxf(1.0, absf(want["cur"][name])), "%s: %s" % [what, name])
	assert_almost_eq(got["debt"], want["debt"], 1e-9, what + ": debt")
	assert_almost_eq(got["slider"], want["slider"], 1e-9, what + ": slider")
	assert_eq(got["flags"], want["flags"], what + ": flags")
	assert_eq(got["timed"], want["timed"], what + ": timed mods")
	for key in ["run_mult", "perm_mult", "rivals"]:
		assert_eq(got[key].keys().size(), want[key].keys().size(), "%s: %s keys" % [what, key])
		for k in want[key]:
			assert_almost_eq(float(got[key][k]), float(want[key][k]), 1e-9, "%s: %s.%s" % [what, key, k])


# ---------------------------------------------------------------- conditions

func test_every_condition_type_passes_only_when_satisfied() -> void:
	var sample := {
		"owned_gte": {"id": Sim.producers(_fresh())[0].id, "value": 3},
		"currency_gte": {"id": "cash", "value": 1e6},
		"resets_gte": {"layer": 1, "value": 1},
		"training_best_gte": {"value": 5.0},
		"staff_gte": {"id": content.get_all("staff")[0].id, "value": 2},
		"research_has": {"id": Support.first_with_no_prereq(content)},
		"slider_gte": {"value": 0.9},
		"time_played_gte": {"value": 100.0},
		"stat_gte": {"id": "papers", "value": 3},
		"benchmark_unlocked": {"id": content.get_all("benchmarks")[0].id},
		"flag_set": {"id": "test_flag"},
		"debt_gte": {"value": 4.0},
		"compute_rate_gte": {"value": 1000.0},
	}
	assert_eq(sample.size(), Rules.CONDITION_TYPES.size(), "a sample for every condition type")
	for type in Rules.CONDITION_TYPES:
		var c: Dictionary = sample[type].duplicate()
		c["type"] = type
		var s := _fresh()
		assert_false(Rules.check(s, c), "%s fails on a fresh state" % type)
		Support.satisfy(s, [c])
		assert_true(Rules.check(s, c), "%s passes once satisfied" % type)


func test_value_thresholds_are_inclusive() -> void:
	var s := _fresh()
	var pid: String = Sim.producers(s)[0].id
	Support.set_owned(s, pid, 4)
	assert_true(Rules.check(s, {"type": "owned_gte", "id": pid, "value": 4}))
	assert_false(Rules.check(s, {"type": "owned_gte", "id": pid, "value": 5}))


# ---------------------------------------------------------------- events

func test_events_are_only_offered_when_eligible() -> void:
	var offered := 0
	for seed_value in range(1, 200):
		var s := _fresh(seed_value)
		for d in content.get_all("events"):
			Support.satisfy(s, d.conditions)  # every event is eligible; the pool decides which one comes up
		s.run["layers"][0]["clock"] = Sim.EVENT_MIN_SECONDS  # past the run-start gate
		Support.set_owned(s, Sim.producers(s)[0].id, Sim.EVENT_MIN_PRODUCERS)
		s.run["layers"][0]["event_timer"] = 0.0
		for e in Sim.tick(s, 0.0):
			if e["kind"] != "event":
				continue
			offered += 1
			var d = _def("events", e["id"])
			assert_true(Rules.check_all(s, d.conditions), "%s offered with conditions met" % e["id"])
			assert_false(s.run["layers"][0]["cooldowns"].has(e["id"]), "%s not on cooldown" % e["id"])
	assert_gt(offered, 0, "some event is offered across seeds")


func test_each_choice_applies_its_effects_and_closes_the_event() -> void:
	for d in content.get_all("events"):
		for ci in d.choices.size():
			var s := _fresh(ci + 1)
			Support.satisfy(s, d.conditions)
			s.run["layers"][0]["pending"] = d.id
			var want := _snap(s)
			for e in d.choices[ci]["effects"]:
				_apply_ref(want, e)

			var r := Sim.resolve_event(s, ci)
			assert_true(r["ok"], "%s choice %d: %s" % [d.id, ci, str(r.get("reason", ""))])
			_assert_snap_matches(_snap(s), want, "%s choice %d" % [d.id, ci])
			assert_eq(s.run["layers"][0]["pending"], "")
			assert_almost_eq(float(s.run["layers"][0]["cooldowns"][d.id]), float(d.cooldown), 1e-9)
			assert_eq(s.persist["stats"]["events"], 1)


func test_resolve_refuses_missing_event_or_bad_choice() -> void:
	var s := _fresh()
	assert_false(Sim.resolve_event(s, 0)["ok"], "nothing pending")
	var d = content.get_all("events")[0]
	s.run["layers"][0]["pending"] = d.id
	assert_false(Sim.resolve_event(s, -1)["ok"])
	assert_false(Sim.resolve_event(s, d.choices.size())["ok"])
	assert_eq(s.run["layers"][0]["pending"], d.id, "still pending after refusal")


func test_alignment_debt_accrues_only_below_the_safe_slider_after_generation() -> void:
	var s := _fresh()
	Sim.tick(s, 1000.0)
	assert_eq(float(s.run["layers"][0]["debt"]), 0.0, "no debt before Model Generation")

	s.run["resets_done"][1] = 1
	s.run["slider"] = Sim.SLIDER_SAFE * 0.5
	Sim.tick(s, 1000.0)
	var debt: float = s.run["layers"][0]["debt"]
	assert_gt(debt, 0.0, "debt accrues under the safe slider")

	s.run["slider"] = minf(1.0, Sim.SLIDER_SAFE + 0.2)
	Sim.tick(s, 1000.0)
	assert_eq(float(s.run["layers"][0]["debt"]), debt, "no debt above the safe slider")


func test_debt_worsens_output_monotonically() -> void:
	var s := _fresh()
	var d = Sim.producers(s)[0]
	Support.set_owned(s, d.id, 10)
	var rates := []
	for debt in [0.0, 25.0, 100.0, 400.0]:
		s.run["layers"][0]["debt"] = debt
		rates.append(Sim.compute_per_second(s).to_float())
	for i in range(1, rates.size()):
		assert_lt(rates[i], rates[i - 1], "more debt, less compute")
	assert_gt(rates[-1], 0.0, "debt never zeroes output")


# ---------------------------------------------------------------- benchmarks

func test_each_benchmark_unlocks_once_and_applies_its_bonus() -> void:
	for b in content.get_all("benchmarks"):
		var s := _fresh()
		for other in content.get_all("benchmarks"):
			if other.id != b.id:
				s.persist["benchmarks"].append(other.id)  # isolate this benchmark's own bonus
		Support.satisfy(s, b.conditions)
		var want := _snap(s)
		for e in b.effects:
			_apply_ref(want, e)

		var evs := Sim.tick(s, 0.0)
		var unlocks := evs.filter(func(e): return e["kind"] == "benchmark" and e["id"] == b.id)
		assert_eq(unlocks.size(), 1, "%s announced once" % b.id)
		assert_eq(unlocks[0]["badge"], b.badge)
		assert_eq(s.persist["benchmarks"].count(b.id), 1, "%s recorded once" % b.id)
		_assert_snap_matches(_snap(s), want, "%s bonus" % b.id)

		var again := Sim.tick(s, 0.0).filter(func(e): return e["kind"] == "benchmark" and e["id"] == b.id)
		assert_true(again.is_empty(), "%s not re-awarded" % b.id)
