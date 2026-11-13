class_name Moonshots
extends RefCounted
## Moonshots: long real-time projects on the Paradigm tab. Start for breakthroughs (and cash), run for `hours` of game
## time, then apply their effects once. State is persist.moonshots = {running: [{id, left}], done: [id]}, which no reset
## touches. Progress uses raw dt, so offline catch-up advances them at full speed. Passive rewards are read by id.

const BAY_SLOTS := 2       # slots once second_bay is done
const FUNDING_TIER_MAX := 3  # seed_capital: producers granted at a Funding Round (the first three by order)
const SEED_OWNED := 10
const LAB_KEEP_ORDER := 6   # institutional_memory: lab upgrades with order <= this survive a Funding Round
const GAIN_MULT := 1.25     # funding_multiplier / generation_multiplier
const SURGE_MULT := 1.25    # agi_surge
const FAST_LAUNCH := 0.75   # launch_pad
const FAST_HIRE := 0.8      # talent_pipeline
const FAST_FAIL := 0.8      # efficient_training
const CHEAP_PRODUCER := 0.9 # bulk_pricing
const NEWS_LONGER := 1.5    # news_desk
const PROGRAMME_MAX := 25
const PROGRAMME_BASE_COST := 0.35
const PROGRAMME_COST_GROWTH := 1.4
const PROGRAMME_BONUS := 1.03


static func all(s: GameState) -> Array:
	return s.db.get_all("moonshots")


static func _data(s: GameState) -> Dictionary:
	return s.persist["moonshots"]


static func done(s: GameState, id: String) -> bool:
	return id in _data(s)["done"]


static func running(s: GameState) -> Array:
	return _data(s)["running"]


static func is_running(s: GameState, id: String) -> bool:
	for m in running(s):
		if m["id"] == id:
			return true
	return false


static func slots(s: GameState) -> int:
	return BAY_SLOTS if done(s, "second_bay") else 1


static func programme_level(s: GameState) -> int:
	return int(_data(s)["programme"]["level"])


static func programme_cost(s: GameState) -> float:
	return PROGRAMME_BASE_COST * pow(PROGRAMME_COST_GROWTH, programme_level(s))


static func programme_hours(s: GameState) -> int:
	return mini(4 + floori(programme_level(s) / 6.0), 8)


static func programme_left(s: GameState) -> float:
	return float(_data(s)["programme"]["left"])


static func programme_blocker(s: GameState) -> String:
	if s.resets(3) == 0:
		return "locked"
	if programme_level(s) >= PROGRAMME_MAX:
		return "max level"
	if programme_left(s) > 0.0:
		return "in progress"
	if s.cur("breakthroughs").compare(BigNum.from_float(programme_cost(s))) < 0:
		return "not enough breakthroughs"
	return ""


static func start_programme(s: GameState) -> Dictionary:
	var reason := programme_blocker(s)
	if reason != "":
		return {"ok": false, "reason": reason}
	s.set_cur("breakthroughs", s.cur("breakthroughs").subtract(BigNum.from_float(programme_cost(s))))
	_data(s)["programme"]["left"] = programme_hours(s) * 3600.0
	return {"ok": true, "level": programme_level(s) + 1}


## Why `start` would fail, or "" when it would succeed.
static func blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("moonshots", id)
	if d == null:
		return "unknown moonshot"
	if done(s, id):
		return "done"
	if is_running(s, id):
		return "running"
	if not Rules.check_all(s, d.conditions):
		return "locked"
	for p in d.prereqs:
		if not done(s, p):
			return "needs " + s.db.get_def("moonshots", p).title
	if running(s).size() >= slots(s):
		return "no free project slot"
	if s.cur("breakthroughs").compare(BigNum.from_float(d.breakthroughs)) < 0:
		return "not enough breakthroughs"
	if s.cur("cash").compare(BigNum.from_float(d.cash)) < 0:
		return "not enough cash"
	return ""


static func start(s: GameState, id: String) -> Dictionary:
	var reason := blocker(s, id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var d = s.db.get_def("moonshots", id)
	s.set_cur("breakthroughs", s.cur("breakthroughs").subtract(BigNum.from_float(d.breakthroughs)))
	s.set_cur("cash", s.cur("cash").subtract(BigNum.from_float(d.cash)))
	running(s).append({"id": id, "left": d.hours * 3600.0})
	return {"ok": true, "id": id}


## Advances running projects by dt seconds; a finished one applies its effects and emits moonshot_done.
static func tick(s: GameState, dt: float, evs: Array) -> void:
	var programme: Dictionary = _data(s)["programme"]
	if float(programme["left"]) > 0.0:
		programme["left"] = maxf(0.0, float(programme["left"]) - dt)
		if float(programme["left"]) == 0.0:
			programme["level"] += 1
			s.persist["perm_mult"]["compute"] = float(s.persist["perm_mult"].get("compute", 1.0)) * PROGRAMME_BONUS
			evs.append({"kind": "moonshot_done", "id": "research_programme"})
	var r := running(s)
	for i in range(r.size() - 1, -1, -1):
		r[i]["left"] = float(r[i]["left"]) - dt
		if float(r[i]["left"]) > 0.0:
			continue
		var id: String = r[i]["id"]
		r.remove_at(i)
		_data(s)["done"].append(id)
		s.persist["stats"]["moonshots"] = _data(s)["done"].size()
		for e in s.db.get_def("moonshots", id).effects:
			Rules.apply(s, e)
		evs.append({"kind": "moonshot_done", "id": id})


## Seconds left on a running project, or -1 when it is not running.
static func time_left(s: GameState, id: String) -> float:
	for m in running(s):
		if m["id"] == id:
			return float(m["left"])
	return -1.0


# ---------------------------------------------------------------- rewards read by the core (one hook each)

## Factor on a producer's price (Upgrades.cost_mult).
static func producer_cost_mult(s: GameState) -> float:
	return CHEAP_PRODUCER if done(s, "bulk_pricing") else 1.0


## Factor on a launch cooldown (Launches.fire).
static func cooldown_mult(s: GameState) -> float:
	return FAST_LAUNCH if done(s, "launch_pad") else 1.0


## Factor on hiring cost (Sim.staff_cost).
static func staff_cost_mult(s: GameState) -> float:
	return FAST_HIRE if done(s, "talent_pipeline") else 1.0


## Factor on the training fail chance (Sim.training_fail_factor).
static func fail_mult(s: GameState) -> float:
	return FAST_FAIL if done(s, "efficient_training") else 1.0


## Factor on a breaking news chip's duration (News.tick).
static func chip_mult(s: GameState) -> float:
	return NEWS_LONGER if done(s, "news_desk") else 1.0


## Research desk slots (Desk.cap).
static func desk_slots(s: GameState) -> int:
	return 1 if done(s, "data_flywheel") else 0


## Threshold for layer k's reset, with the gain multiplier folded in: gain is floor(sqrt(life / threshold)), so a
## threshold divided by GAIN_MULT^2 gives GAIN_MULT times the gain (Sim.reset_preview, Rules.reset_worth_life, reset_eta).
static func threshold_for(s: GameState, k: int, threshold: float) -> float:
	var on := (k == 1 and done(s, "funding_multiplier")) or (k == 2 and done(s, "generation_multiplier"))
	return threshold / (GAIN_MULT * GAIN_MULT) if on else threshold


## Extra currency a reset of layer k pays on top of its gain: a Paradigm Shift or a Singularity.
static func bonus_gain(s: GameState, k: int) -> float:
	if k == 3 and done(s, "paradigm_dividend"):
		return 1.0
	if k == 4 and done(s, "legacy_tithe"):
		return 1.0
	return 0.0


## Factors on mult(s, key) (Rules.mult_parts). AGI Surge only while the AGI road is in progress.
static func parts(s: GameState, key: String) -> Array:
	var out: Array = []
	if key == "compute" and done(s, "agi_surge") and int(s.run["stage"]) >= 1 and s.run["run_over"] == "":
		out.append({"id": "agi_surge", "name": "AGI Surge", "value": SURGE_MULT})
	return out


# ---------------------------------------------------------------- Funding Round (layer 1) carry, around the wipe

## Captures reset carry before lower layers are wiped: Singularity keeps Breakthroughs; moonshots are persistent;
## Funding Round carry is gated by its moonshots.
static func before_wipe(s: GameState, k: int) -> Dictionary:
	var keep := {}
	if k == 4:
		keep["breakthroughs"] = s.cur("breakthroughs")
	if k != 1:
		return keep
	var L0: Dictionary = s.run["layers"][0]
	if done(s, "second_cluster") and not (L0["training"] as Dictionary).is_empty():
		keep["training"] = (L0["training"] as Dictionary).duplicate(true)
	if done(s, "institutional_memory"):
		var ids: Array = []
		for id in Upgrades.owned_ids(s):
			var d = s.db.get_def("upgrades", id)
			if d != null and int(d.order) <= LAB_KEEP_ORDER:
				ids.append(id)
		keep["upgrades"] = ids
	return keep


## Puts back what before_wipe kept and grants seed capital, after the wipe and before the reset gain.
static func after_wipe(s: GameState, k: int, keep: Dictionary) -> void:
	var L0: Dictionary = s.run["layers"][0]
	if keep.has("breakthroughs"):
		s.set_cur("breakthroughs", keep["breakthroughs"])
	if keep.has("training"):
		L0["training"] = keep["training"]
	if keep.has("upgrades"):
		L0["upgrades"] = keep["upgrades"]
	if k == 1 and done(s, "seed_capital"):
		var ps: Array = s.db.get_all("producers")
		ps.sort_custom(func(a, b): return a.order < b.order)
		for d in ps.slice(0, FUNDING_TIER_MAX):
			L0["owned"][d.id] = SEED_OWNED
