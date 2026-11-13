class_name Rules
## Condition checks, effect application and multiplier composition. Pure: takes GameState + content.
## Condition dict: {type, id?, layer?, value?}.  Effect dict: {type, id?, key?, value?, seconds?}.

const CONDITION_TYPES := [
	"owned_gte", "currency_gte", "resets_gte", "training_best_gte", "staff_gte", "research_has",
	"stat_gte", "slider_gte", "time_played_gte", "benchmark_unlocked", "flag_set", "debt_gte", "compute_rate_gte",
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
		"stat_gte":
			return float(s.persist["stats"].get(c["id"], 0)) >= float(c["value"])
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
			for i in range(L0["timed"].size() - 1, -1, -1):
				if L0["timed"][i]["key"] == e["key"]:
					L0["timed"].remove_at(i)
			L0["timed"].append({"key": e["key"], "value": float(e["value"]), "left": float(e["seconds"])})
		"run_mult":
			L0["run_mult"][e["key"]] = float(L0["run_mult"].get(e["key"], 1.0)) * float(e["value"])
		"perm_mult":
			s.persist["perm_mult"][e["key"]] = float(s.persist["perm_mult"].get(e["key"], 1.0)) * float(e["value"])
		"rival_progress":
			s.run["rivals"][e["id"]] = float(s.run["rivals"].get(e["id"], 0.0)) + float(e["value"])
		_:
			push_error("Unknown effect type: %s" % e["type"])


## Why effect `e` cannot be offered yet (its system is still locked), or "" when it is usable.
## Events use this to hide choices that would touch a currency or system the player has not reached.
static func effect_blocker(s: GameState, e: Dictionary) -> String:
	var need := 0
	match e["type"]:
		"add_currency":
			need = int(GameState.CURRENCY_LAYER.get(e["id"], 0))
		"add_slider", "add_debt":
			need = 2  # alignment: the slider and the debt it builds unlock with Model Generation
		"rival_progress":
			need = 4  # rivals exist from the Singularity on
	if need > 0 and s.resets(need) == 0:
		return "locked until reset %d" % need
	return ""


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
	if key == "compute":
		out.append({"id": "desk", "name": "Research desk", "value": 1.0 + float(s.run["layers"][2]["desk"]["bonus"])})
	out.append({"id": "run", "name": "Run upgrades", "value": float(L0["run_mult"].get(key, 1.0))})
	out.append_array(Upgrades.parts(s, key))
	out.append_array(Moonshots.parts(s, key))
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
	return training_bonus_for(float(s.run["layers"][2]["best"]), float(s.persist["best_all"]))


## The same bonus for given bests, e.g. to preview a score before it lands.
static func training_bonus_for(best: float, best_all: float) -> float:
	return (1.0 + 0.05 * best) * (1.0 + 0.01 * best_all)


# ---------------------------------------------------------------- progress toward goals

## Goal kinds that rank first when within BIG_BONUS of the nearest goal (see next_goals).
const BIG_KINDS := ["reset", "producer", "agi"]
const BIG_BONUS := 0.10


## Progress 0..1 toward condition `c`, for the goal rail and the benchmark bars. Exactly 1.0 when check() passes,
## otherwise capped at 0.99 so a near miss never reads as done. Currency-like amounts use log scale.
static func condition_progress(s: GameState, c: Dictionary) -> float:
	if check(s, c):
		return 1.0
	var p := 0.0
	match c["type"]:
		"currency_gte":
			p = _log_progress(s.cur(c["id"]), BigNum.from_float(float(c["value"])))
		"compute_rate_gte":
			p = _log_progress(Sim.compute_per_second(s), BigNum.from_float(float(c["value"])))
		"owned_gte":
			p = _linear(float(s.owned(c["id"])), float(c["value"]))
		"resets_gte":
			p = _linear(float(s.resets(int(c["layer"]))), float(c["value"]))
		"training_best_gte":
			p = _linear(float(s.run["layers"][2]["best"]), float(c["value"]))
		"staff_gte":
			p = _linear(float(s.run["layers"][1]["staff"].get(c["id"], 0)), float(c["value"]))
		"slider_gte":
			p = _linear(float(s.run["slider"]), float(c["value"]))
		"stat_gte":
			p = _linear(float(s.persist["stats"].get(c["id"], 0)), float(c["value"]))
		"time_played_gte":
			p = _linear(float(s.persist["stats"]["time"]), float(c["value"]))
		"debt_gte":
			p = _linear(float(s.run["layers"][0]["debt"]), float(c["value"]))
		"research_has", "benchmark_unlocked", "flag_set":
			p = 0.0  # all-or-nothing
		_:
			push_error("Unknown condition type: %s" % c["type"])
	return clampf(p, 0.0, 0.99)


## Progress of a condition list: the minimum over its conditions (1.0 for an empty list).
static func conditions_progress(s: GameState, conds: Array) -> float:
	var p := 1.0
	for c in conds:
		p = minf(p, condition_progress(s, c))
	return p


static func _linear(have: float, need: float) -> float:
	return 1.0 if need <= 0.0 else clampf(have / need, 0.0, 1.0)


## Orders of magnitude of `b`, log10(1 + b): 0 for zero, so the bar moves evenly from 1 to 1e6 and beyond.
static func _log1p10(b: BigNum) -> float:
	if b.is_zero():
		return 0.0
	if b.exponent >= 15:
		return b.log10()
	return log(1.0 + b.to_float()) / log(10.0)


static func _log_progress(have: BigNum, need: BigNum) -> float:
	var top := _log1p10(need)
	return 1.0 if top <= 0.0 else clampf(_log1p10(have) / top, 0.0, 1.0)


static func _ceil_big(b: BigNum) -> BigNum:
	var f := b.floor_value()
	return f if f.compare(b) == 0 else f.add(BigNum.from_float(1.0))


## Lifetime cash (layer k's `life`) at which a reset of layer k is worth it. reset_preview's highlight is
## gain >= 2 and gain >= 2 x holding, with gain = floor(sqrt(life / threshold)); so the gain needed is
## G = max(2, ceil(2 x holding)) and the life is threshold x G^2.
static func reset_worth_life(s: GameState, k: int) -> BigNum:
	var ld = Sim.layer_def(s, k)
	var g := _ceil_big(s.cur(ld.currency).mul_f(2.0))
	if g.compare(BigNum.from_float(2.0)) < 0:
		g = BigNum.from_float(2.0)
	return BigNum.from_float(Moonshots.threshold_for(s, k, float(ld.threshold))).multiply(g.multiply(g))


## Seconds to cover `remaining` of lifetime at `rate` per second (0 when already covered).
static func _secs(remaining: BigNum, rate: BigNum) -> float:
	if remaining.compare(BigNum.new()) <= 0:
		return 0.0
	return remaining.divide(rate).to_float()


## Reset ETA for layer k at the current income. Every layer's `life` grows by cash per second, so that is the rate.
## {worth_now: bool, worth_in: float, next_in: float}, seconds. worth_in is 0 when worth it already; next_in is the
## time until the gain rises by one. Both are INF when income is zero. An estimate: the rate may change.
static func reset_eta(s: GameState, k: int) -> Dictionary:
	var out := {"worth_now": false, "worth_in": INF, "next_in": INF}
	var ld = Sim.layer_def(s, k)
	if ld == null:
		return out
	var p := Sim.reset_preview(s, k)
	var rate := Sim.cash_per_second(s)
	var life: BigNum = s.run["layers"][k]["life"]
	out["worth_now"] = p["highlight"]
	if p["highlight"]:
		out["worth_in"] = 0.0
	if rate.is_zero():
		return out
	if not p["highlight"]:
		out["worth_in"] = _secs(reset_worth_life(s, k).subtract(life), rate)
	var g := int(p["gain"])
	var thr := Moonshots.threshold_for(s, k, float(ld.threshold))
	out["next_in"] = _secs(BigNum.from_float(thr * float(g + 1) * float(g + 1)).subtract(life), rate)
	return out


static func _goal(kind: String, id: String, title: String, progress: float, hint: String) -> Dictionary:
	return {"kind": kind, "id": id, "title": title, "progress": progress, "hint": hint}


## The n nearest unmet goals: locked benchmarks, each reset layer's worth-it point, the next producer tier not yet
## owned, the next milestone of each owned producer, and the current AGI stage once the Singularity is reachable.
## Each is {kind, id, title, progress, hint}. A locked benchmark's title is its real name: the UI hides it.
## Sorted by progress, except that a big goal (BIG_KINDS) within BIG_BONUS of the nearest ranks first.
static func next_goals(s: GameState, n: int) -> Array:
	var goals: Array = []
	for d in s.db.get_all("benchmarks"):
		if not (d.id in s.persist["benchmarks"]):
			goals.append(_goal("benchmark", d.id, d.title, conditions_progress(s, d.conditions), d.description))
	for k in range(1, 5):
		var ld = Sim.layer_def(s, k)
		if ld == null or (k > 1 and s.resets(k - 1) == 0) or Sim.reset_preview(s, k)["highlight"]:
			continue
		var p := Sim.reset_preview(s, k)
		var hint := "Gain +%d %s on reset. Worth it once the gain is at least double what you hold." % [
			int(p["gain"]), String(ld.currency).capitalize()]
		goals.append(_goal("reset", ld.id, "%s reset" % ld.title,
			_log_progress(s.run["layers"][k]["life"], reset_worth_life(s, k)), hint))
	var producers: Array = s.db.get_all("producers")
	for d in producers:
		if s.owned(d.id) == 0:
			var cost := Sim.cost_for(s, d.id, 1)
			goals.append(_goal("producer", d.id, "Buy %s" % d.title, _log_progress(s.cur("cash"), cost),
				"Costs %s cash. Each one makes %s compute/s." % [cost.format(), BigNum.from_float(float(d.base_output)).format()]))
			break
	for d in producers:
		var owned := s.owned(d.id)
		for m in Sim.MILESTONES:
			if owned >= 1 and owned < m:
				goals.append(_goal("milestone", d.id, "%s at %d" % [d.title, m], float(owned) / float(m),
					"Doubles %s output at %d owned. You have %d." % [d.title, m, owned]))
				break
	var stages: Array = s.db.get_all("agi_stages")
	var stage := int(s.run["stage"])
	if stage < stages.size() and (s.resets(3) > 0 or s.resets(4) > 0):
		var st = stages[stage]
		goals.append(_goal("agi", st.id, st.title, conditions_progress(s, st.conditions), st.description))
	goals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["progress"] + _big_bonus(a) > b["progress"] + _big_bonus(b))
	return goals.slice(0, n)


static func _big_bonus(goal: Dictionary) -> float:
	return BIG_BONUS if BIG_KINDS.has(goal["kind"]) else 0.0
