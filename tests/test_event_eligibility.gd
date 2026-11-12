extends GutTest
## Event eligibility: nothing fires in the first minutes of a run or before a few producers exist, and no choice
## offers an effect in a currency or system the player has not reached yet (Rules.effect_blocker).

const Support := preload("res://tests/support.gd")

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _fresh(seed_value: int = 7) -> GameState:
	return Support.new_state(content, seed_value)


## Ticks `seconds` in small steps, collecting event offers. Clears each pending event so the next one can roll.
func _run_collect(s: GameState, seconds: float) -> Array:
	var offered: Array = []
	var t := 0.0
	while t < seconds:
		for e in Sim.tick(s, 0.5):
			if e["kind"] == "event":
				offered.append(e["id"])
				s.run["layers"][0]["pending"] = ""
		t += 0.5
	return offered


func test_effect_blocker_gates_each_system_on_its_reset() -> void:
	var s := _fresh()
	assert_ne(Rules.effect_blocker(s, {"type": "add_currency", "id": "equity", "value": -1.0}), "", "equity before a Funding Round")
	assert_ne(Rules.effect_blocker(s, {"type": "add_currency", "id": "insights", "value": 1.0}), "", "insights before Generation")
	assert_ne(Rules.effect_blocker(s, {"type": "add_currency", "id": "data", "value": 1.0}), "", "data before Paradigm")
	assert_ne(Rules.effect_blocker(s, {"type": "add_debt", "value": 1.0}), "", "debt before Generation")
	assert_ne(Rules.effect_blocker(s, {"type": "add_slider", "value": 0.05}), "", "slider before Generation")
	assert_ne(Rules.effect_blocker(s, {"type": "rival_progress", "id": "aurora", "value": -0.1}), "", "rivals before Singularity")
	assert_eq(Rules.effect_blocker(s, {"type": "add_currency", "id": "compute", "value": -5.0}), "", "compute is always open")
	assert_eq(Rules.effect_blocker(s, {"type": "timed_mod", "key": "cash", "value": 1.1, "seconds": 60.0}), "", "timed mods are open")
	s.run["resets_done"][0] = 1
	assert_eq(Rules.effect_blocker(s, {"type": "add_currency", "id": "equity", "value": -1.0}), "", "equity after a Funding Round")
	assert_ne(Rules.effect_blocker(s, {"type": "add_currency", "id": "insights", "value": 1.0}), "", "insights still locked after reset 1")


func test_no_event_in_the_first_two_minutes_even_with_producers() -> void:
	var s := _fresh()
	# A new legacy keeps the lifetime play time, so time-played conditions pass at once. The run clock must still gate.
	s.persist["stats"]["time"] = 99999.0
	s.run["layers"][0]["owned"][Sim.producers(s)[0].id] = 10
	var early := _run_collect(s, Sim.EVENT_MIN_SECONDS - 5.0)
	assert_eq(early.size(), 0, "no event before %d s of run time" % int(Sim.EVENT_MIN_SECONDS))


func test_no_event_before_a_few_producers_exist() -> void:
	var s := _fresh()
	s.persist["stats"]["time"] = 99999.0
	s.run["layers"][0]["owned"][Sim.producers(s)[0].id] = Sim.EVENT_MIN_PRODUCERS - 1
	var offered := _run_collect(s, 1200.0)
	assert_eq(offered.size(), 0, "no event with %d producers" % (Sim.EVENT_MIN_PRODUCERS - 1))


func test_offered_events_never_touch_a_locked_system() -> void:
	# Across seeds and a long run with plenty of producers, every event offered must have all choices unlocked
	# and its conditions met. Run at each reset stage so the gate is exercised at every layer.
	for stage in range(0, 5):
		for seed_value in range(1, 9):
			var s := _fresh(seed_value)
			s.persist["stats"]["time"] = 99999.0
			for k in range(1, stage + 1):
				s.run["resets_done"][k - 1] = 1
			for d in Sim.producers(s):
				s.run["layers"][0]["owned"][d.id] = 5
			s.add_cur("cash", BigNum.from_float(1e12))
			for id in _run_collect(s, 1800.0):
				var d = content.get_def("events", id)
				assert_true(Sim.event_eligible(s, d), "stage %d seed %d: %s offered while a choice is locked" % [stage, seed_value, id])
				for ch in d.choices:
					for e in ch["effects"]:
						assert_eq(Rules.effect_blocker(s, e), "", "stage %d: %s effect %s" % [stage, id, e["type"]])


func test_tech_blog_is_not_offered_with_no_equity_in_a_new_legacy() -> void:
	# The bug report: a new run after a legacy (lifetime play time over 10 min, no Funding Round yet) offered
	# "Hold a press call" costing equity the player did not have.
	var s := _fresh()
	s.persist["stats"]["time"] = 99999.0
	for d in Sim.producers(s):
		s.run["layers"][0]["owned"][d.id] = 5
	assert_false(Sim.event_eligible(s, content.get_def("events", "md_leak_rumor")), "locked by equity and debt")


func test_stale_pending_event_is_dropped_on_load() -> void:
	var s := _fresh()
	s.run["layers"][0]["pending"] = "md_leak_rumor"
	Sim.drop_stale_pending(s)
	assert_eq(s.run["layers"][0]["pending"], "", "a pending event with locked choices is cleared")
	s.run["resets_done"][0] = 1
	s.run["resets_done"][1] = 1
	s.run["resets_done"][2] = 1
	s.run["layers"][0]["pending"] = "md_leak_rumor"
	Sim.drop_stale_pending(s)
	assert_eq(s.run["layers"][0]["pending"], "md_leak_rumor", "an unlocked pending event is kept")
