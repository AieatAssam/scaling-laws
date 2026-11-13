extends GutTest
## Statistics and reveals: completion maths, record updates (first reset is a baseline, later faster ones are records,
## Game.record_set fires), v3 -> v4 save migration, and reveal scheduling/seeding. Pure core plus the Game signal hook.

const Support := preload("res://tests/support.gd")
const SaveScript := preload("res://src/autoload/save_system.gd")

var content: Node
var s: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	s = Support.new_state(content)


func _at(t: float) -> void:
	s.persist["stats"]["time"] = t


func test_fresh_completion_is_zero_with_ten_parts() -> void:
	var c := Records.completion(s)
	assert_eq(c["parts"].size(), 10)
	assert_eq(float(c["percent"]), 0.0)


func test_one_producer_counts_as_one_ninth_of_the_producer_part() -> void:
	var d: Dictionary = {}
	for p in s.db.get_all("producers"):
		d = {"id": p.id}
		break
	Records.note(s.persist, "producers", d["id"])
	var part := _part(Records.completion(s), "producers")
	assert_eq(int(part["done"]), 1)
	assert_eq(int(part["total"]), s.db.get_all("producers").size())


func test_reset_layers_and_agi_count_in_completion() -> void:
	s.persist["lifetime_resets"][0] = 3
	s.persist["lifetime_resets"][2] = 1
	var layers := _part(Records.completion(s), "resets")
	assert_eq(int(layers["done"]), 2)
	assert_eq(int(layers["total"]), Records.LAYERS)
	Records.note_agi(s.persist, 3)
	Records.note_agi(s.persist, 2)  # the best is kept, not the latest
	var agi := _part(Records.completion(s), "agi")
	assert_eq(int(agi["done"]), 3)
	s.persist["moonshots"]["done"].append("launch_pad")
	var moons := _part(Records.completion(s), "moonshots")
	assert_eq(int(moons["done"]), 1)
	assert_eq(int(moons["total"]), s.db.get_all("moonshots").size())


func test_percent_is_the_mean_of_the_part_fractions() -> void:
	# Every part fully done gives 100; this checks the weighting with one part only.
	var total := 0.0
	var c := Records.completion(s)
	for part in c["parts"]:
		total += float(part["done"]) / maxf(float(part["total"]), 1.0)
	assert_almost_eq(float(c["percent"]), 100.0 * total / 10.0, 0.0001)


func test_first_reset_sets_baseline_not_record() -> void:
	_at(100.0)
	var r := Records.note_reset(s.persist, 1)
	assert_true(r["first"])
	assert_false(r["record"])
	assert_eq(float(r["secs"]), 100.0)
	assert_eq(float(s.persist["records"]["fastest"]["1"]), 100.0)


func test_faster_cycle_is_a_record_slower_is_not() -> void:
	_at(100.0)
	Records.note_reset(s.persist, 1)     # baseline: 100 s
	_at(150.0)
	var slower := Records.note_reset(s.persist, 1)  # 50 s since the last clear: a record
	assert_true(slower["record"])
	assert_eq(float(slower["secs"]), 50.0)
	_at(400.0)
	var worse := Records.note_reset(s.persist, 1)  # 250 s: not a record, the best stays 50
	assert_false(worse["record"])
	assert_eq(float(s.persist["records"]["fastest"]["1"]), 50.0)


func test_higher_reset_clears_lower_layer_clocks() -> void:
	_at(100.0)
	Records.note_reset(s.persist, 2)
	var cs: Array = s.persist["records"]["cycle_start"]
	assert_eq(float(cs[0]), 100.0)
	assert_eq(float(cs[1]), 100.0)
	assert_eq(float(cs[2]), 100.0)
	assert_eq(float(cs[3]), 0.0, "layer 3 is above the reset and keeps its clock")


func test_layer_reset_signal_emits_record_set_on_a_record() -> void:
	var saved := Game.state
	Game.state = s
	watch_signals(Game)
	_at(100.0)
	Game.layer_reset.emit(1, 0)  # baseline: no record_set
	assert_signal_not_emitted(Game, "record_set")
	_at(160.0)
	Game.layer_reset.emit(1, 0)  # 60 s: a record
	assert_signal_emitted(Game, "record_set")
	assert_signal_emit_count(Game, "record_set", 1)
	Game.state = saved


func test_v3_save_is_migrated_with_records() -> void:
	var state := s.to_dict()
	state["persist"].erase("records")
	state["persist"].erase("seen_reveals")
	state["persist"].erase("reveals_seeded")
	state["persist"]["stats"]["time"] = 500.0
	var saver: Node = autofree(SaveScript.new())
	var migrated: Dictionary = saver.migrate({"version": 3, "state": state})
	var r: Dictionary = migrated["persist"]["records"]
	assert_eq((r["fastest"] as Dictionary).size(), 0)
	assert_eq(float(r["cycle_start"][1]), 500.0)
	assert_eq(float(r["run_start"]), 500.0)


func test_absorb_counts_what_a_loaded_save_holds() -> void:
	var p := s.persist
	p["records"] = Records.default(0.0)
	var pid: String = s.db.get_all("producers")[0].id
	s.run["layers"][0]["owned"][pid] = 2
	Records.absorb(s)
	assert_true(p["records"]["producers"].has(pid))


func test_reveal_is_due_once_its_conditions_hold() -> void:
	_at(0.0)
	assert_eq(Reveals.next_due(s), "")
	_at(1300.0)
	assert_eq(Reveals.next_due(s), "hiring")
	Reveals.mark_seen(s, "hiring")
	assert_eq(Reveals.next_due(s), "training")
	Reveals.mark_seen(s, "training")
	assert_eq(Reveals.next_due(s), "")


func test_seed_marks_met_reveals_seen_once() -> void:
	_at(1300.0)
	Reveals.seed(s)
	assert_true(Reveals.is_seen(s, "hiring"))
	assert_true(Reveals.is_seen(s, "training"))
	assert_false(Reveals.is_seen(s, "agi"))
	assert_true(bool(s.persist["reveals_seeded"]))
	_at(20000.0)
	Reveals.seed(s)  # later calls do nothing
	assert_false(Reveals.is_seen(s, "agi"))


func test_every_reveal_points_at_a_real_help_topic() -> void:
	var topics := {}
	for h in content.get_all("help"):
		topics[h.id] = true
	for r in Reveals.LIST:
		assert_true(topics.has(r["topic"]), "reveal %s -> help topic %s" % [r["id"], r["topic"]])


func test_format_duration() -> void:
	assert_eq(Records.format_duration(45.0), "45s")
	assert_eq(Records.format_duration(724.0), "12m 04s")
	assert_eq(Records.format_duration(3780.0), "1h 03m")


func _part(c: Dictionary, id: String) -> Dictionary:
	for part in c["parts"]:
		if part["id"] == id:
			return part
	return {}


func test_absorb_records_outpaced_rivals_and_the_best_agi_stage() -> void:
	var p := s.persist
	p["records"] = Records.default(0.0)
	var rid: String = s.db.get_all("rivals")[0].id
	s.run["flags"]["outpaced_%s" % rid] = true
	s.run["stage"] = 3
	Records.absorb(s)
	assert_true(p["records"]["outpaced"].has(rid))
	assert_eq(int(p["records"]["agi_best"]), 3)
