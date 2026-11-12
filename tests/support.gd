extends RefCounted
## Shared helpers for the GUT suite. Not a test file (no test_ prefix). All state is built from the
## real content in res://content, so tests read balance values from Content instead of hard-coding them.

const ContentScript := preload("res://src/autoload/content.gd")


static func make_content() -> Node:
	var c: Node = ContentScript.new()
	c.load_all()
	return c


## Deletes a save file and everything the save system leaves beside it: <path>.bak, <path>.bad-<ms>, <path>.newer-<ms>.
static func remove_save_files(path: String) -> void:
	var dir := path.get_base_dir()
	var base := path.get_file()
	for f in DirAccess.get_files_at(dir):
		if f == base or f == base + ".bak" or f.begins_with(base + ".bad-") or f.begins_with(base + ".newer-"):
			DirAccess.remove_absolute(dir.path_join(f))


static func new_state(content: Node, seed_value: int = 1) -> GameState:
	return GameState.new(content, seed_value)


## Deep copy of Dictionary/Array data with BigNum values turned into {mantissa, exponent}.
## Lets two states be compared with `==`.
static func plain(v: Variant) -> Variant:
	if v is BigNum:
		return v.to_json()
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = plain(v[k])
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(plain(x))
		return arr
	return v


static func set_owned(s: GameState, id: String, n: int) -> void:
	s.run["layers"][0]["owned"][id] = n


static func set_cash_float(s: GameState, name: String, value: float) -> void:
	s.set_cur(name, BigNum.from_float(value))


## Near-equality for BigNums with relative tolerance.
static func bn_near(a: BigNum, b: BigNum, rel: float = 1e-9) -> bool:
	if a.is_zero() or b.is_zero():
		return a.is_zero() and b.is_zero()
	return absf(a.subtract(b).to_float()) <= rel * absf(a.to_float())


static func first_with_no_prereq(content: Node) -> String:
	for d in content.get_all("research"):
		if d.prereqs.is_empty():
			return d.id
	return ""


## Sets run/persist state so that every condition in `conds` passes. Used to build states in
## which a given event or benchmark is eligible, whatever its content says.
static func satisfy(s: GameState, conds: Array) -> void:
	for c in conds:
		var v: float = float(c.get("value", 0))
		match c["type"]:
			"owned_gte":
				s.run["layers"][0]["owned"][c["id"]] = maxi(s.owned(c["id"]), int(v))
			"currency_gte":
				if s.cur(c["id"]).lt(BigNum.from_float(v)):
					s.set_cur(c["id"], BigNum.from_float(v))
			"resets_gte":
				var k: int = int(c["layer"])
				s.run["resets_done"][k - 1] = maxi(s.resets(k), int(v))
			"training_best_gte":
				s.run["layers"][2]["best"] = maxf(float(s.run["layers"][2]["best"]), v)
			"staff_gte":
				s.run["layers"][1]["staff"][c["id"]] = maxi(int(s.run["layers"][1]["staff"].get(c["id"], 0)), int(v))
			"research_has":
				if not (c["id"] in s.run["layers"][2]["research"]):
					s.run["layers"][2]["research"].append(c["id"])
			"slider_gte":
				s.run["slider"] = maxf(float(s.run["slider"]), v)
			"stat_gte":
				s.persist["stats"][c["id"]] = maxi(int(s.persist["stats"].get(c["id"], 0)), int(v))
			"time_played_gte":
				s.persist["stats"]["time"] = maxf(float(s.persist["stats"]["time"]), v)
			"benchmark_unlocked":
				if not (c["id"] in s.persist["benchmarks"]):
					s.persist["benchmarks"].append(c["id"])
			"flag_set":
				s.run["flags"][c["id"]] = true
			"debt_gte":
				s.run["layers"][0]["debt"] = maxf(float(s.run["layers"][0]["debt"]), v)
			"compute_rate_gte":
				# Enough of the first tier that its raw output alone reaches the rate (multipliers are >= 1).
				var first = Sim.producers(s)[0]
				s.run["layers"][0]["owned"][first.id] = maxi(s.owned(first.id), ceili(v / float(first.base_output)))
			_:
				push_error("satisfy: unknown condition %s" % c["type"])
