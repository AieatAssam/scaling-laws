class_name Upgrades
extends RefCounted
## Lab upgrades: run-scoped, bought once with cash. State is run layer 0 `upgrades` (a list of ids), which a reset
## of any layer wipes like producers. Effects are read from the owned list on every call (see UpgradeDef).

const SYNERGY_CAP := 1.0   # synergy adds at most +100% to its tier


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func all(s: GameState) -> Array:
	return s.db.get_all("upgrades")


static func owned_ids(s: GameState) -> Array:
	return s.run["layers"][0]["upgrades"]


static func is_owned(s: GameState, id: String) -> bool:
	return id in owned_ids(s)


## Definitions of the owned upgrades, in purchase order.
static func owned_defs(s: GameState) -> Array:
	var out: Array = []
	for id in owned_ids(s):
		var d = s.db.get_def("upgrades", id)
		if d != null:
			out.append(d)
	return out


## Why `buy` would fail, or "" when it would succeed.
static func blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("upgrades", id)
	if d == null:
		return "unknown upgrade"
	if is_owned(s, id):
		return "already bought"
	for c in d.conditions:
		if not Rules.check(s, c):
			return "locked: needs %d %s" % [int(c["value"]), _title_of(s, c)]
	if s.cur("cash").compare(BigNum.from_float(d.cost)) < 0:
		return "not enough cash"
	return ""


static func _title_of(s: GameState, c: Dictionary) -> String:
	var p = s.db.get_def("producers", c.get("id", ""))
	return p.title if p != null else String(c.get("id", ""))


static func buy(s: GameState, id: String) -> Dictionary:
	var reason := blocker(s, id)
	if reason != "":
		return _fail(reason)
	var cost := BigNum.from_float(float(s.db.get_def("upgrades", id).cost))
	s.set_cur("cash", s.cur("cash").subtract(cost))
	owned_ids(s).append(id)
	return {"ok": true, "id": id, "cost": cost}


## Output multiplier of tier `id` from owned double and synergy upgrades (1.0 when none).
static func tier_mult(s: GameState, id: String) -> float:
	var m := 1.0
	for u in owned_defs(s):
		if u.target != id:
			continue
		if u.kind == "double":
			m *= 1.0 + u.value
		elif u.kind == "synergy":
			m *= 1.0 + minf(SYNERGY_CAP, u.value * s.owned(u.source))
	return m


## Factors behind tier_mult(id): {id, name, value}, for the tooltip.
static func tier_parts(s: GameState, id: String) -> Array:
	var out: Array = []
	for u in owned_defs(s):
		if u.target != id:
			continue
		if u.kind == "double":
			out.append({"id": u.id, "name": u.title, "value": 1.0 + u.value})
		elif u.kind == "synergy":
			out.append({"id": u.id, "name": u.title, "value": 1.0 + minf(SYNERGY_CAP, u.value * s.owned(u.source))})
	return out


## Price multiplier of tier `id` from owned cost upgrades (1.0 when none).
static func cost_mult(s: GameState, id: String) -> float:
	var m := 1.0
	for u in owned_defs(s):
		if u.kind == "cost" and u.target == id:
			m *= 1.0 - u.value
	return m


## Factors this module adds to multiplier `key`, for Rules.mult_parts: revenue (cash) and train_speed.
static func parts(s: GameState, key: String) -> Array:
	var out: Array = []
	for u in owned_defs(s):
		if key == "cash" and u.kind == "revenue":
			out.append({"id": u.id, "name": u.title, "value": 1.0 + u.value})
		elif key == "train_speed" and u.kind == "train_speed":
			out.append({"id": u.id, "name": u.title, "value": 1.0 / (1.0 - u.value)})
	return out


## Auto-upgrade (Breakthroughs): buys the cheapest affordable upgrade until none is affordable.
static func automate(s: GameState, evs: Array) -> void:
	if not ("auto_upgrade" in s.persist["automation"]):
		return
	while true:
		var best := ""
		var best_cost := INF
		for d in all(s):
			if d.cost < best_cost and blocker(s, d.id) == "":
				best = d.id
				best_cost = d.cost
		if best == "":
			return
		buy(s, best)
		evs.append({"kind": "upgrade_bought", "id": best, "auto": true})
