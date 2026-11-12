extends GutTest

const Support := preload("res://tests/support.gd")
var content: Node
var s: GameState

func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content, 7)
	s.persist["lifetime_resets"][1] = 1

func test_timing_cap_offline_and_save() -> void:
	Desk.tick(s, 1199.0, [])
	assert_eq(Desk.state(s)["slots"].size(), 0)
	Desk.tick(s, 1.0, [])
	assert_eq(Desk.state(s)["slots"].size(), 1)
	Sim.offline(s, 10000.0)
	assert_eq(Desk.state(s)["slots"].size(), 3)
	var restored := GameState.from_dict(content, s.to_dict())
	assert_eq(Desk.state(restored), Desk.state(s))

func test_effects_and_cap() -> void:
	s.run["layers"][0]["owned"]["intern_laptop"] = 1
	var desk := Desk.state(s)
	desk["slots"].append({"id": "paper_02", "landmark": true})
	assert_true(Desk.resolve(s, 0, 0)["ok"])
	assert_almost_eq(float(s.run["layers"][0]["timed"][0]["value"]), 1.01, 0.00001)
	desk["slots"].append({"id": "paper_02", "landmark": false})
	Desk.resolve(s, 0, 0)
	assert_eq(s.run["layers"][0]["timed"].size(), 1)
	var before := s.cur("cash")
	desk["slots"].append({"id": "paper_02", "landmark": false})
	Desk.resolve(s, 0, 1)
	assert_true(s.cur("cash").compare(before) > 0)
	for i in 260:
		desk["slots"].append({"id": "paper_01", "landmark": false})
		Desk.resolve(s, 0, 0)
	assert_almost_eq(float(desk["bonus"]), 0.5, 0.00001)
	assert_eq(int(s.persist["stats"]["landmarks"]), 1)

func test_content_never_grants_prestige_currency() -> void:
	assert_gte(content.get_all("papers").size(), 24)
	for d in content.get_all("papers"):
		for ch in d.choices:
			for e in ch["effects"]:
				assert_false(e.get("id", "") in ["insights", "equity", "breakthroughs", "legacy"])

func test_reset_scope() -> void:
	Desk.tick(s, 1200.0, [])
	for k in [1, 2]:
		s.run["resets_done"][0] = 1
		s.run["layers"][k]["life"] = BigNum.from_float(float(Sim.layer_def(s, k).threshold) * 4.0)
		assert_true(Sim.perform_reset(s, k)["ok"])
		assert_eq(Desk.state(s)["slots"].size(), 1 if k == 1 else 0)

func test_training_and_rival_effects() -> void:
	var desk := Desk.state(s)
	desk["slots"].append({"id": "paper_02", "landmark": false})
	assert_true(Desk.resolve(s, 0, 2)["ok"])
	assert_eq(s.run["layers"][0]["timed"][0]["key"], "training")
	desk["slots"].append({"id": "paper_23", "landmark": true})
	assert_true(Desk.resolve(s, 0, 0)["ok"])
	assert_almost_eq(float(s.run["rivals"]["aurora"]), -0.02, 0.00001)
