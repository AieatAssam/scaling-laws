class_name Rules
## Condition checks, effect application and multiplier composition. Pure: takes GameState + content.
## Condition dict: {type, id?, layer?, value?}.  Effect dict: {type, id?, key?, value?, seconds?}.

const CONDITION_TYPES := [
	"owned_gte", "currency_gte", "resets_gte", "training_best_gte", "staff_gte", "research_has",
	"slider_gte", "time_played_gte", "benchmark_unlocked", "flag_set", "debt_gte", "compute_rate_gte",
]
const EFFECT_TYPES := [
	"add_currency", "add_debt", "add_slider", "add_flag", "timed_mod", "run_mult", "perm_mult", "rival_progress",
]


static func check_all(s: GameState, conds: Array) -> bool:
	for c in conds:
		if not check(s, c):
			return false
	return true


static func check(s: GameState, c: Dictionary) -> bool:
	match c["type"]:
		"owned_gte":
			return s.owned(c["id"]) >= int(c["value"])
		"currency_gte":
			return s.cur(c["id"]).compare(BigNum.from_float(float(c["value"]))) >= 0
		"resets_gte":
			return s.resets(int(c["layer"])) >= int(c["value"])
		"training_best_gte":
			return float(s.run["layers"][2]["best"]) >= float(c["value"])
		"staff_gte":
			return int(s.run["layers"][1]["staff"].get(c["id"], 0)) >= int(c["value"])
		"research_has":
			return c["id"] in s.run["layers"][2]["research"]
		"slider_gte":
			return float(s.run["slider"]) >= float(c["value"])
		"time_played_gte":
			return float(s.persist["stats"]["time"]) >= float(c["value"])
		"benchmark_unlocked":
			return c["id"] in s.persist["benchmarks"]
		"flag_set":
			return bool(s.run["flags"].get(c["id"], false))
		"debt_gte":
			return float(s.run["layers"][0]["debt"]) >= float(c["value"])
		"compute_rate_gte":  # sustained output: compute per second after every multiplier, not a held stock
			return Sim.compute_per_second(s).gte(BigNum.from_float(float(c["value"])))
		_:
			push_error("Unknown condition type: %s" % c["type"])
			return false


static func apply(s: GameState, e: Dictionary) -> void:
	var L0: Dictionary = s.run["layers"][0]
	match e["type"]:
		"add_currency":
			s.add_cur(e["id"], BigNum.from_float(float(e["value"])))
		"add_debt":
			L0["debt"] = maxf(0.0, float(L0["debt"]) + float(e["value"]))
		"add_slider":
			s.run["slider"] = clampf(float(s.run["slider"]) + float(e["value"]), 0.0, 1.0)
		"add_flag":
			s.run["flags"][e["id"]] = true
		"timed_mod":
			L0["timed"].append({"key": e["key"], "value": float(e["value"]), "left": float(e["seconds"])})
		"run_mult":
			L0["run_mult"][e["key"]] = float(L0["run_mult"].get(e["key"], 1.0)) * float(e["value"])
		"perm_mult":
			s.persist["perm_mult"][e["key"]] = float(s.persist["perm_mult"].get(e["key"], 1.0)) * float(e["value"])
		"rival_progress":
			s.run["rivals"][e["id"]] = float(s.run["rivals"].get(e["id"], 0.0)) + float(e["value"])
		_:
			push_error("Unknown effect type: %s" % e["type"])


## Product of every multiplier for `key` (cash, compute, training).
static func mult(s: GameState, key: String) -> float:
	var m := 1.0
	for p in mult_parts(s, key):
		m *= float(p["value"])
	return m


## Each factor that makes up mult(s, key): {id, name, value}. Same order and inputs as mult().
static func mult_parts(s: GameState, key: String) -> Array:
	var L0: Dictionary = s.run["layers"][0]
	var out: Array = []
	out.append({"id": "perm", "name": "Legacy perks", "value": float(s.persist["perm_mult"].get(key, 1.0))})
	out.append({"id": "run", "name": "Run upgrades", "value": float(L0["run_mult"].get(key, 1.0))})
	for t in L0["timed"]:
		if t["key"] == key:
			out.append({"id": "timed", "name": "Timed boost", "value": float(t["value"])})
	for r in owned_research(s):
		for e in r.effects:
			if e["key"] == key:
				out.append({"id": r.id, "name": r.title, "value": float(e["value"])})
	for st in s.db.get_all("staff"):
		if st.bonus_key == key:
			var n := int(s.run["layers"][1]["staff"].get(st.id, 0))
			out.append({"id": st.id, "name": st.title, "value": 1.0 + float(st.bonus_per_hire) * n})
	if key == "compute":
		out.append({"id": "capability", "name": "Alignment", "value": capability(s)})
		out.append({"id": "debt", "name": "Debt", "value": debt_factor(s)})
		out.append({"id": "training", "name": "Training score", "value": training_bonus(s)})
	return out


static func owned_research(s: GameState) -> Array:
	var out: Array = []
	for id in s.run["layers"][2]["research"]:
		var d = s.db.get_def("research", id)
		if d != null:
			out.append(d)
	return out


## Alignment slider below 1.0 buys raw capability once Model Generation is done.
static func capability(s: GameState) -> float:
	if s.resets(2) > 0:
		return 1.0 + 0.5 * (1.0 - float(s.run["slider"]))
	return 1.0


static func debt_factor(s: GameState) -> float:
	return 1.0 / (1.0 + 0.02 * float(s.run["layers"][0]["debt"]))


## Generation-best training score (per run of layer 2) plus a reduced bonus from the all-time best.
static func training_bonus(s: GameState) -> float:
	return (1.0 + 0.05 * float(s.run["layers"][2]["best"])) * (1.0 + 0.01 * float(s.persist["best_all"]))
