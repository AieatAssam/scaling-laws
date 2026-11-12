extends GutTest
## Content integrity: every .tres def is well-formed and every cross-reference resolves. Nothing here
## counts defs or checks balance numbers, so tuning passes and new content cannot break it.
## The asset test checks the SPEC.md manifest paths exist (fails until the art lands).

const Support := preload("res://tests/support.gd")
const MULTIPLIER_KEYS := ["compute", "cash", "training", "train_speed"]
const SPEC_ICONS := ["compute", "cash", "equity", "insights", "breakthroughs", "legacy", "data", "energy",
	"alignment", "capability", "training", "hiring", "research", "benchmarks", "events", "rivals",
	"regulation", "automation", "settings", "agi"]
const SPEC_EVENT_CATEGORIES := ["rival_launch", "regulation", "poaching", "incident", "breakthrough",
	"media", "funding", "outage"]
const SPEC_BADGES := ["bronze", "silver", "gold", "platinum", "diamond", "cosmic"]
const SPEC_BACKDROPS := ["garage_sky", "city", "orbit", "swarm", "universe"]
const SPEC_LEGACY := ["funding", "generation", "paradigm", "singularity"]
const SPEC_ENDINGS := ["aligned", "rushed", "open_sourced"]
const SPEC_WORKERS := ["researcher", "engineer", "ops"]

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _ids(type: String) -> Array:
	var out: Array = []
	for d in content.get_all(type):
		out.append(d.id)
	return out


func _check_effects(effects: Array, where: String) -> void:
	for e in effects:
		assert_true(e["type"] in Rules.EFFECT_TYPES, "%s: effect type %s" % [where, e["type"]])
		match e["type"]:
			"add_currency":
				assert_true(GameState.CURRENCY_LAYER.has(e["id"]), "%s: currency %s" % [where, e["id"]])
			"run_mult", "perm_mult", "timed_mod":
				assert_true(e["key"] in MULTIPLIER_KEYS, "%s: multiplier key %s" % [where, e["key"]])


func _check_conditions(conds: Array, where: String) -> void:
	for c in conds:
		assert_true(c["type"] in Rules.CONDITION_TYPES, "%s: condition type %s" % [where, c["type"]])
		match c["type"]:
			"owned_gte":
				assert_not_null(content.get_def("producers", c["id"]), "%s: producer %s" % [where, c["id"]])
			"currency_gte":
				assert_true(GameState.CURRENCY_LAYER.has(c["id"]), "%s: currency %s" % [where, c["id"]])
			"compute_rate_gte":
				assert_gt(float(c["value"]), 0.0, "%s: rate must be positive" % where)
			"resets_gte":
				assert_between(int(c["layer"]), 1, 4, "%s: reset layer" % where)
			"staff_gte":
				assert_not_null(content.get_def("staff", c["id"]), "%s: staff %s" % [where, c["id"]])
			"research_has":
				assert_not_null(content.get_def("research", c["id"]), "%s: research %s" % [where, c["id"]])
			"benchmark_unlocked":
				assert_not_null(content.get_def("benchmarks", c["id"]), "%s: benchmark %s" % [where, c["id"]])


func test_every_def_has_an_id_and_round_trips_through_the_lookup() -> void:
	for type in content.types():
		var seen := {}
		for d in content.get_all(type):
			assert_ne(d.id, "", "%s: has an id" % type)
			assert_false(seen.has(d.id), "%s: %s unique" % [type, d.id])
			seen[d.id] = true
			assert_eq(content.get_def(type, d.id), d, "%s/%s found by id" % [type, d.id])


func test_each_layer_index_has_a_def_and_its_currency_lives_in_that_layer() -> void:
	for k in range(1, 5):
		var ld = Sim.layer_def(_state(), k)
		assert_not_null(ld, "layer %d defined" % k)
		if ld != null:
			assert_eq(GameState.CURRENCY_LAYER[ld.currency], k, "layer %d currency sits in layer %d" % [k, k])


func test_producers_are_sane_and_ordered_without_ties() -> void:
	var orders := {}
	for d in content.get_all("producers"):
		assert_gt(float(d.base_cost), 0.0, "%s base_cost" % d.id)
		assert_gt(float(d.base_output), 0.0, "%s base_output" % d.id)
		assert_false(orders.has(d.order), "%s: order %d unique" % [d.id, d.order])
		orders[d.order] = true


func test_research_prereqs_resolve_and_branches_are_consistent() -> void:
	for d in content.get_all("research"):
		assert_gte(float(d.cost), 0.0, "%s cost" % d.id)
		for p in d.prereqs:
			assert_not_null(content.get_def("research", p), "%s prereq %s" % [d.id, p])
		# Research effects are multipliers {key, value} with no "type" (see Rules.mult).
		assert_true(d.effects.all(func(e): return e["key"] in MULTIPLIER_KEYS and float(e["value"]) > 0.0), "research %s effects" % d.id)


func test_staff_bonus_keys_are_multipliers() -> void:
	for d in content.get_all("staff"):
		assert_true(d.bonus_key in MULTIPLIER_KEYS, "%s bonus_key" % d.id)
		assert_gte(float(d.cost_growth), 1.0, "%s cost grows" % d.id)


func test_events_are_well_formed() -> void:
	for d in content.get_all("events"):
		var where := "event %s" % d.id
		assert_gt(float(d.weight), 0.0, where + " weight")
		assert_gte(float(d.cooldown), 0.0, where + " cooldown")
		assert_gt(d.choices.size(), 0, where + " has choices")
		_check_conditions(d.conditions, where)
		for c in d.choices:
			assert_true(c.has("label") and c.has("effects"), where + " choice shape")
			_check_effects(c["effects"], where)


func test_benchmarks_and_endings_reference_real_content() -> void:
	for b in content.get_all("benchmarks"):
		var where := "benchmark %s" % b.id
		assert_true(b.badge in SPEC_BADGES, where + " badge is a manifest badge")
		assert_false(b.conditions.is_empty(), where + " has a trigger")
		_check_conditions(b.conditions, where)
		_check_effects(b.effects, where)
	for e in content.get_all("endings"):
		_check_conditions(e.conditions, "ending %s" % e.id)


func test_agi_stages_and_challenges_are_well_formed() -> void:
	for st in content.get_all("agi_stages"):
		_check_conditions(st.conditions, "agi stage %d" % st.order)
	for c in content.get_all("challenges"):
		var where := "challenge %s" % c.id
		assert_gt(float(c.duration), 0.0, where + " duration")
		_check_conditions(c.goal, where + " goal")
		_check_effects(c.reward, where + " reward")
		_check_effects(c.penalty, where + " penalty")


func test_rivals_launch_after_the_start() -> void:
	for r in content.get_all("rivals"):
		assert_gt(float(r.launch_hours), 0.0, "%s launch time" % r.id)


func test_every_producer_has_a_room_image_and_every_event_category_an_image() -> void:
	for d in content.get_all("producers"):
		_assert_asset("res://assets/rooms/%s.png" % d.id)
	for cat in SPEC_EVENT_CATEGORIES:
		_assert_asset("res://assets/events/%s.png" % cat)


func test_every_asset_in_the_spec_manifest_exists() -> void:
	for p in content.get_all("producers"):
		_assert_asset("res://assets/rooms/%s.png" % p.id)
	for f in ["floor", "roof", "ground"]:
		_assert_asset("res://assets/shell/%s.png" % f)
	for w in SPEC_WORKERS:
		_assert_asset("res://assets/workers/%s.png" % w)
	for i in SPEC_ICONS:
		_assert_asset("res://assets/icons/%s.png" % i)
	for c in SPEC_EVENT_CATEGORIES:
		_assert_asset("res://assets/events/%s.png" % c)
	for b in SPEC_BADGES:
		_assert_asset("res://assets/badges/%s.png" % b)
	for b in SPEC_BACKDROPS:
		_assert_asset("res://assets/backdrops/%s.png" % b)
	for l in SPEC_LEGACY:
		_assert_asset("res://assets/legacy/%s.png" % l)
	for e in SPEC_ENDINGS:
		_assert_asset("res://assets/endings/%s.png" % e)


func _state() -> GameState:
	return Support.new_state(content, 1)


func _assert_asset(path: String) -> void:
	assert_true(FileAccess.file_exists(path), "asset exists: " + path)
