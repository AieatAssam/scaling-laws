class_name Launches
extends RefCounted
## Launch actions: pay a share of a currency for a timed boost (one timed mod per key: a new one replaces the old).
## Cooldowns are run-level (run["launches"]: id -> seconds left), so a Funding Round does not reset them.

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func all(s: GameState) -> Array:
	return s.db.get_all("launches")


static func cost(s: GameState, id: String) -> BigNum:
	var d = s.db.get_def("launches", id)
	return s.cur(d.cost_currency).mul_f(d.cost_share)


static func cooldown_left(s: GameState, id: String) -> float:
	return float(s.run["launches"].get(id, 0.0))


## Why `fire` would fail, or "" when it would succeed.
static func blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("launches", id)
	if d == null:
		return "unknown launch"
	if not Rules.check_all(s, d.conditions):
		return "locked"
	if cooldown_left(s, id) > 0.0:
		return "cooling down"
	if s.cur(d.cost_currency).compare(cost(s, id)) < 0:
		return "not enough %s" % d.cost_currency
	return ""


static func fire(s: GameState, id: String) -> Dictionary:
	var reason := blocker(s, id)
	if reason != "":
		return _fail(reason)
	var d = s.db.get_def("launches", id)
	var paid := cost(s, id)
	s.set_cur(d.cost_currency, s.cur(d.cost_currency).subtract(paid))
	for e in d.effects:
		Rules.apply(s, e)
	s.run["launches"][id] = float(d.cooldown)
	s.persist["stats"]["launches"] = int(s.persist["stats"].get("launches", 0)) + 1
	return {"ok": true, "id": id, "cost": paid}


## Counts cooldowns down; a launch is ready again at zero.
static func tick(s: GameState, dt: float) -> void:
	var cd: Dictionary = s.run["launches"]
	for id in cd.keys():
		cd[id] = float(cd[id]) - dt
		if float(cd[id]) <= 0.0:
			cd.erase(id)


## Auto-launch (Breakthroughs): fires every launch that is ready and affordable.
static func automate(s: GameState, evs: Array) -> void:
	if not ("auto_launch" in s.persist["automation"]):
		return
	for d in all(s):
		if blocker(s, d.id) == "" and fire(s, d.id)["ok"]:
			evs.append({"kind": "launch_fired", "id": d.id, "auto": true})
