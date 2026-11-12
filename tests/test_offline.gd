extends GutTest
## Offline progress: 24 h cap, 50% efficiency, and the shape of the summary.

const Support := preload("res://tests/support.gd")

var content: Node


func before_each() -> void:
	content = autofree(Support.make_content())


func _producing_state() -> GameState:
	var s := Support.new_state(content, 11)
	var d = Sim.producers(s)[0]
	Support.set_owned(s, d.id, 10)
	s.set_cur("cash", BigNum.new())
	s.set_cur("compute", BigNum.new())
	# A benchmark unlocking mid-step would change the rate in the offline steps but not in one online tick.
	for b in content.get_all("benchmarks"):
		s.persist["benchmarks"].append(b.id)
	return s


func test_capped_at_24_hours() -> void:
	var s := _producing_state()
	var r := Sim.offline(s, 3.0 * Sim.OFFLINE_CAP)
	assert_eq(r["seconds"], Sim.OFFLINE_CAP)
	assert_true(r["capped"])
	assert_false(Sim.offline(_producing_state(), Sim.OFFLINE_CAP)["capped"], "exactly the cap is not capped")


func test_earns_half_the_online_rate() -> void:
	var away := _producing_state()
	var online := _producing_state()
	var r := Sim.offline(away, 600.0)
	Sim.tick(online, 600.0)
	assert_gt(online.cur("cash").to_float(), 0.0, "precondition: income")
	assert_true(Support.bn_near(r["cash"], online.cur("cash").mul_f(Sim.OFFLINE_EFF), 1e-6), "cash at 50%")
	assert_true(Support.bn_near(r["compute"], online.cur("compute").mul_f(Sim.OFFLINE_EFF), 1e-6), "compute at 50%")
	assert_true(Support.bn_near(away.cur("cash"), r["cash"]), "summary matches what was added")


func test_summary_shape() -> void:
	var r := Sim.offline(_producing_state(), 3600.0)
	var keys := r.keys()
	keys.sort()
	assert_eq(keys, ["capped", "cash", "compute", "events", "seconds"])
	assert_eq(r["seconds"], 3600.0)
	assert_true(r["cash"] is BigNum)
	assert_true(r["compute"] is BigNum)
	assert_true(r["events"] is Array)
	for e in r["events"]:
		assert_ne(e["kind"], "event", "offline play does not roll random events")


func test_zero_seconds_is_a_no_op() -> void:
	var s := _producing_state()
	var before: Dictionary = Support.plain(s.to_dict())
	var r := Sim.offline(s, 0.0)
	assert_true(r["cash"].is_zero())
	assert_eq(r["events"], [])
	assert_eq(Support.plain(s.to_dict()), before)
