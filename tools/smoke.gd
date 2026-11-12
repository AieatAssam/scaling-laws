extends SceneTree
## Headless smoke test. Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/smoke.gd
## Prints OK and exits 0, or prints FAIL lines and exits 1.

const SAVE_TMP := "user://smoke_save.json"
const EXPECTED := {
	"producers": 12, "layers": 4, "staff": 3, "research": 21, "automation": 4, "rivals": 5,
	"challenges": 5, "agi_stages": 5, "endings": 3, "events": 3, "benchmarks": 3,
}

var fails := 0


func _initialize() -> void:
	# Local instances: under -s the Content autoload may not have run _ready yet.
	var content = load("res://src/autoload/content.gd").new()
	content.load_all()
	var ss = load("res://src/autoload/save_system.gd").new()
	_run(content, ss)
	if fails == 0:
		print("OK")
		quit(0)
	else:
		print("FAILED: %d check(s)" % fails)
		quit(1)


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: " + what)


func _run(content, ss) -> void:
	# --- content: counts and every condition/effect type is known to Rules
	for t in EXPECTED:
		check(content.get_all(t).size() >= EXPECTED[t], "content count %s = %d" % [t, content.get_all(t).size()])
	for t in ["events", "benchmarks", "agi_stages", "endings"]:
		for d in content.get_all(t):
			for c in d.get("conditions"):
				check(c["type"] in Rules.CONDITION_TYPES, "%s/%s unknown condition %s" % [t, d.id, c["type"]])
	for d in content.get_all("events"):
		for ch in d.get("choices"):
			for e in ch["effects"]:
				check(e["type"] in Rules.EFFECT_TYPES, "events/%s unknown effect %s" % [d.id, e["type"]])
	for d in content.get_all("benchmarks"):
		for e in d.get("effects"):
			check(e["type"] in Rules.EFFECT_TYPES, "benchmarks/%s unknown effect %s" % [d.id, e["type"]])

	# --- BigNum
	var a := BigNum.from_float(1e6)
	check(is_equal_approx(a.add(BigNum.from_float(5e6)).to_float(), 6e6), "bignum add")
	check(BigNum.from_json(a.to_json()).compare(a) == 0, "bignum json round trip")
	check(a.format() != "", "bignum format")

	# --- state and tick
	var s: GameState = GameState.new(content, 12345)
	check(s.owned("nothing") == 0, "fresh state owns nothing")
	Sim.tick(s, 1.0)
	check(is_equal_approx(float(s.persist["stats"]["time"]), 1.0), "tick advances time")

	# --- producers
	s.set_cur("cash", BigNum.from_float(1e6))
	var pid: String = Sim.producers(s)[0].id
	var r: Dictionary = Sim.buy_producer(s, pid, -1)
	check(r["ok"] and s.owned(pid) > 0, "buy max %s: %s" % [pid, r.get("reason", "")])

	# --- training run
	s.add_cur("compute", BigNum.from_float(1e4))
	r = Sim.start_training(s, 0.25)
	check(r["ok"], "start training: %s" % r.get("reason", ""))
	var trained := false
	for e in Sim.tick(s, Sim.TRAIN_SECONDS + 1.0):
		if e["kind"] == "training_done":
			trained = true
	check(trained, "training finishes within %d s" % int(Sim.TRAIN_SECONDS))

	# --- all four resets, in sequence (each granted enough life for gain 2)
	for k in range(1, 5):
		var ld = Sim.layer_def(s, k)
		check(ld != null, "layer %d def exists" % k)
		s.run["layers"][k]["life"] = BigNum.from_float(float(ld.threshold) * 4.0)
		var p: Dictionary = Sim.reset_preview(s, k)
		check(p["allowed"] and p["gain"] == 2, "reset %d preview: %s" % [k, p.get("reason", "")])
		r = Sim.perform_reset(s, k)
		check(r["ok"] and s.resets(k) == 1, "reset %d performed: %s" % [k, r.get("reason", "")])
		check(s.cur(ld.currency).compare(BigNum.from_float(1.5)) > 0, "reset %d grants %s" % [k, ld.currency])
	check(s.owned(pid) == 0, "reset 1 wiped producers")

	# --- event resolution
	var ev_id: String = content.get_all("events")[0].id
	s.run["layers"][0]["pending"] = ev_id
	r = Sim.resolve_event(s, 0)
	check(r["ok"], "resolve event %s: %s" % [ev_id, r.get("reason", "")])

	# --- challenge start (unlocked by reset 4)
	var ch_id: String = content.get_all("challenges")[0].id
	r = Sim.start_challenge(s, ch_id)
	check(r["ok"], "start challenge %s: %s" % [ch_id, r.get("reason", "")])

	# --- save round trip
	var before := JSON.stringify(s.to_dict(), "", true, true)
	check(ss.save(s.to_dict(), SAVE_TMP), "save writes")
	var d: Dictionary = ss.load_data(SAVE_TMP)
	check(not d.is_empty(), "save reads back")
	var s2: GameState = GameState.from_dict(content, d)
	var after := JSON.stringify(s2.to_dict(), "", true, true)
	check(before == after, "save round trip is identical")
	ss.delete(SAVE_TMP)

	# --- offline progress
	var off: Dictionary = Sim.offline(s2, 600.0)
	check(is_equal_approx(float(off["seconds"]), 600.0) and not off["capped"], "offline 600 s")
	check(Sim.offline(s2, 1e9)["capped"], "offline cap flagged")

	# --- Game autoload script compiles
	var gs = load("res://src/autoload/game.gd")
	check(gs != null and gs.can_instantiate(), "game.gd compiles")
	print("autoloads under -s: Content=%s SaveSystem=%s Game=%s" % [
		root.has_node("Content"), root.has_node("SaveSystem"), root.has_node("Game")])
