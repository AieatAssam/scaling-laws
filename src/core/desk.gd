class_name Desk
extends RefCounted

const INTERVAL := 1200.0
const CAP := 3

static func state(s: GameState) -> Dictionary:
	return s.run["layers"][2]["desk"]

static func unlocked(s: GameState) -> bool:
	return int(s.persist["lifetime_resets"][1]) > 0

static func tick(s: GameState, dt: float, evs: Array) -> void:
	if not unlocked(s):
		return
	var desk := state(s)
	if desk["slots"].size() >= CAP:
		return
	desk["timer"] = float(desk["timer"]) - dt
	while float(desk["timer"]) <= 0.0 and desk["slots"].size() < CAP:
		var pool: Array = []
		var total := 0.0
		for d in s.db.get_all("papers"):
			if Rules.check_all(s, d.conditions) and Sim.event_eligible(s, d) and d.weight > 0.0:
				pool.append(d)
				total += d.weight
		if pool.is_empty():
			desk["timer"] = INTERVAL
			return
		var roll := s.rng.randf() * total
		var pick = pool.back()
		for d in pool:
			roll -= d.weight
			if roll < 0.0:
				pick = d
				break
		var landmark := int(s.persist["lifetime_resets"][2]) > 0 and s.rng.randf() < 0.1
		desk["slots"].append({"id": pick.id, "landmark": landmark})
		desk["timer"] = float(desk["timer"]) + INTERVAL
		evs.append({"kind": "paper_offered", "id": pick.id})
		if "auto_review" in s.persist["automation"]:
			var result := resolve(s, desk["slots"].size() - 1, best_cash(s, desk["slots"].back()))
			if result["ok"]:
				evs.append({"kind": "paper_resolved", "id": pick.id, "choice": result["choice"]})
	if desk["slots"].size() >= CAP:
		desk["timer"] = INTERVAL

static func best_cash(s: GameState, card: Dictionary) -> int:
	var d = s.db.get_def("papers", card["id"])
	var best := 0
	var score := -INF
	for i in d.choices.size():
		var n := 0.0
		for e in d.choices[i]["effects"]:
			if e["type"] == "cash_seconds":
				n += float(e["value"])
			elif e["type"] == "timed_mod" and e["key"] == "cash":
				n += (float(e["value"]) - 1.0) * float(e["seconds"])
		if n > score:
			score = n
			best = i
	return best

static func resolve(s: GameState, slot: int, choice: int) -> Dictionary:
	var desk := state(s)
	if slot < 0 or slot >= desk["slots"].size():
		return {"ok": false, "reason": "no such paper"}
	var card: Dictionary = desk["slots"][slot]
	var d = s.db.get_def("papers", card["id"])
	if d == null or choice < 0 or choice >= d.choices.size():
		return {"ok": false, "reason": "no such choice"}
	var ch: Dictionary = d.choices[choice]
	var cost: Dictionary = ch.get("cost", {})
	if not cost.is_empty():
		var amount := BigNum.from_float(float(cost["value"]))
		if s.cur(cost["id"]).lt(amount):
			return {"ok": false, "reason": "not enough " + String(cost["id"])}
		s.set_cur(cost["id"], s.cur(cost["id"]).subtract(amount))
	var scale := 2.0 if card["landmark"] else 1.0
	for effect in ch["effects"]:
		var e: Dictionary = effect.duplicate(true)
		match e["type"]:
			"cash_seconds":
				var cash := Sim.cash_per_second(s).mul_f(float(e["value"]) * scale)
				s.add_cur("cash", cash)
				for k in range(1, 5):
					s.run["layers"][k]["life"] = (s.run["layers"][k]["life"] as BigNum).add(cash)
			"generation_mult":
				desk["bonus"] = minf(0.5, float(desk["bonus"]) + float(e["value"]) * scale)
			"timed_mod":
				e["value"] = 1.0 + (float(e["value"]) - 1.0) * scale
				Rules.apply(s, e)
			_:
				if e.has("value"):
					e["value"] = float(e["value"]) * scale
				Rules.apply(s, e)
	desk["slots"].remove_at(slot)
	s.persist["stats"]["papers"] = int(s.persist["stats"].get("papers", 0)) + 1
	if card["landmark"]:
		s.persist["stats"]["landmarks"] = int(s.persist["stats"].get("landmarks", 0)) + 1
	return {"ok": true, "id": d.id, "choice": choice}
