class_name Sim
## Simulation step and player actions. Pure: all state lives in GameState, all content in s.db.
## Actions return {ok: bool, reason: String, ...}. tick() returns Array of event dicts {kind, ...}.

const REVENUE := 0.5             # cash per compute/sec (before cash mults)
const COST_GROWTH := 1.15
const MILESTONES := [25, 50, 100, 200]   # each milestone doubles that producer's output
const TRAIN_SECONDS := 60.0
const MIN_TRAIN_SPEND := 100.0
const TRAIN_ENERGY := 10.0
const TRAIN_DATA := 2.0
const DATA_RATE := 0.1           # data/sec once Paradigm Shift is done
const ENERGY_RATE := 1.0
const ENERGY_CAP := 100.0
const FAIL_BASE := 0.05
const FAIL_PER_FRAC := 0.3
const DEBT_RATE := 0.002         # debt/sec while slider < SLIDER_SAFE
const SLIDER_SAFE := 0.3
const EVENT_INTERVAL := 90.0
const EVENT_CHANCE := 0.5
const OFFLINE_CAP := 86400.0
const OFFLINE_EFF := 0.5
const OFFLINE_STEP := 60.0
const LEGACY_MULT := 1.1


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _log10(x: float) -> float:
	return log(x) / log(10.0)


static func _big(x: float) -> BigNum:
	return BigNum.from_float(x)


# ---------------------------------------------------------------- costs

## Sum of base * g^k for k in [owned, owned+count): closed form.
static func _series(base: BigNum, growth: float, owned: int, count: int) -> BigNum:
	var g := _big(growth)
	var num: BigNum = g.power(float(count)).subtract(_big(1.0))
	return base.multiply(g.power(float(owned))).multiply(num).mul_f(1.0 / (growth - 1.0))


static func producers(s: GameState) -> Array:
	return s.db.get_all("producers")


static func cost_for(s: GameState, id: String, count: int) -> BigNum:
	var d = s.db.get_def("producers", id)
	return _series(_big(d.base_cost), COST_GROWTH, s.owned(id), count)


static func max_affordable(s: GameState, id: String) -> int:
	var d = s.db.get_def("producers", id)
	var cash: BigNum = s.cur("cash")
	if cash.is_zero() or d == null:
		return 0
	# n = floor(log_g(1 + cash*(g-1)/(base*g^owned)))
	var owned := s.owned(id)
	var lg := _log10(COST_GROWTH)
	var l := cash.log10() + _log10(COST_GROWTH - 1.0) - _log10(float(d.base_cost)) - owned * lg
	var x: float = l if l > 15.0 else _log10(1.0 + pow(10.0, l))
	var n := int(minf(floor(x / lg), 1e6))
	# The log estimate is off by one either way near exact costs; correct both directions.
	while n > 0 and cost_for(s, id, n).compare(cash) > 0:
		n -= 1
	while n < 1000000 and cost_for(s, id, n + 1).compare(cash) <= 0:
		n += 1
	return maxi(n, 0)


static func producer_available(s: GameState, id: String) -> bool:
	var list: Array = producers(s)
	for i in list.size():
		if list[i].id == id:
			return i == 0 or s.owned(list[i - 1].id) > 0
	return false


# ---------------------------------------------------------------- economy

static func raw_rate(s: GameState) -> BigNum:
	var total := BigNum.new()
	for d in producers(s):
		var n := s.owned(d.id)
		if n == 0:
			continue
		var m := 1
		for ms in MILESTONES:
			if n >= ms:
				m *= 2
		total = total.add(_big(float(d.base_output) * n * m))
	return total


static func compute_per_second(s: GameState) -> BigNum:
	return raw_rate(s).mul_f(Rules.mult(s, "compute"))


static func cash_per_second(s: GameState) -> BigNum:
	return compute_per_second(s).mul_f(REVENUE * Rules.mult(s, "cash"))


static func buy_producer(s: GameState, id: String, count: int = 1) -> Dictionary:
	var d = s.db.get_def("producers", id)
	if d == null:
		return _fail("unknown producer")
	if not producer_available(s, id):
		return _fail("locked: buy the previous tier first")
	if count < 0:
		count = max_affordable(s, id)
	if count == 0:
		return _fail("cannot afford")
	var cost := cost_for(s, id, count)
	if s.cur("cash").compare(cost) < 0:
		return _fail("not enough cash")
	s.set_cur("cash", s.cur("cash").subtract(cost))
	var owned_map: Dictionary = s.run["layers"][0]["owned"]
	owned_map[id] = s.owned(id) + count
	return {"ok": true, "count": count, "cost": cost}


# ---------------------------------------------------------------- staff / research / automation / legacy

static func hire(s: GameState, role: String, count: int = 1) -> Dictionary:
	var d = s.db.get_def("staff", role)
	if d == null:
		return _fail("unknown staff role")
	if s.resets(1) == 0:
		return _fail("hiring unlocks after a Funding Round")
	if count < 1:
		return _fail("count must be >= 1")
	var staff: Dictionary = s.run["layers"][1]["staff"]
	var n := int(staff.get(role, 0))
	var cost := _series(_big(d.base_cost), d.cost_growth, n, count)
	if s.cur("equity").compare(cost) < 0:
		return _fail("not enough equity")
	s.set_cur("equity", s.cur("equity").subtract(cost))
	staff[role] = n + count
	return {"ok": true, "count": count, "cost": cost}


static func research(s: GameState, id: String) -> Dictionary:
	var d = s.db.get_def("research", id)
	if d == null:
		return _fail("unknown research")
	if s.resets(2) == 0:
		return _fail("research unlocks after a Model Generation")
	var L2: Dictionary = s.run["layers"][2]
	if id in L2["research"]:
		return _fail("already researched")
	for p in d.prereqs:
		if not (p in L2["research"]):
			return _fail("requires %s" % p)
	if d.branch != "":
		for r in Rules.owned_research(s):
			if r.branch != "" and r.branch != d.branch:
				return _fail("exclusive with the %s branch" % r.branch)
	var cost := _big(float(d.cost))
	if s.cur("insights").compare(cost) < 0:
		return _fail("not enough insights")
	s.set_cur("insights", s.cur("insights").subtract(cost))
	L2["research"].append(id)
	return {"ok": true, "cost": cost}


static func buy_automation(s: GameState, id: String) -> Dictionary:
	var d = s.db.get_def("automation", id)
	if d == null:
		return _fail("unknown automation")
	if s.resets(3) == 0:
		return _fail("automation unlocks after a Paradigm Shift")
	var owned: Array = s.persist["automation"]
	if id in owned:
		return _fail("already owned")
	for a in s.db.get_all("automation"):
		if a.order < d.order and not (a.id in owned):
			return _fail("requires %s" % a.id)
	var cost := _big(float(d.cost))
	if s.cur("breakthroughs").compare(cost) < 0:
		return _fail("not enough breakthroughs")
	s.set_cur("breakthroughs", s.cur("breakthroughs").subtract(cost))
	owned.append(id)
	return {"ok": true, "cost": cost}


static func buy_legacy(s: GameState, key: String) -> Dictionary:
	if s.resets(4) == 0:
		return _fail("legacy unlocks after the Singularity")
	var perks: Dictionary = s.persist["legacy_perks"]
	var n := int(perks.get(key, 0))
	var cost := _big(pow(2.0, n))
	if s.cur("legacy").compare(cost) < 0:
		return _fail("not enough legacy")
	s.set_cur("legacy", s.cur("legacy").subtract(cost))
	s.persist["perm_mult"][key] = float(s.persist["perm_mult"].get(key, 1.0)) * LEGACY_MULT
	perks[key] = n + 1
	return {"ok": true, "cost": cost}


static func set_slider(s: GameState, value: float) -> Dictionary:
	if s.resets(2) == 0:
		return _fail("alignment slider unlocks after a Model Generation")
	s.run["slider"] = clampf(value, 0.0, 1.0)
	return {"ok": true, "value": s.run["slider"]}


## Starts a new run once the current one has ended. Persistent state is kept.
static func new_run(s: GameState) -> Dictionary:
	if s.run["run_over"] == "":
		return _fail("run not finished")
	s.run = GameState.fresh_run()
	s.persist["stats"]["runs"] = int(s.persist["stats"]["runs"]) + 1
	return {"ok": true}


# ---------------------------------------------------------------- training

static func training_preview(s: GameState, frac: float) -> Dictionary:
	var spend: BigNum = s.cur("compute").mul_f(frac)
	var energy_ok := s.resets(3) == 0 or (s.cur("energy").gte(_big(TRAIN_ENERGY)) and s.cur("data").gte(_big(TRAIN_DATA)))
	var p := {
		"ok": false, "reason": "", "spend": spend, "seconds": TRAIN_SECONDS,
		"fail_chance": FAIL_BASE + FAIL_PER_FRAC * frac,
	}
	if not (s.run["layers"][0]["training"] as Dictionary).is_empty():
		p["reason"] = "already training"
	elif spend.compare(_big(MIN_TRAIN_SPEND)) < 0:
		p["reason"] = "needs at least %d compute" % int(MIN_TRAIN_SPEND)
	elif not energy_ok:
		p["reason"] = "not enough energy or data"
	else:
		p["ok"] = true
	return p


static func start_training(s: GameState, frac: float) -> Dictionary:
	if not (frac in [0.25, 0.5, 1.0]):
		return _fail("frac must be 0.25, 0.5 or 1.0")
	var p := training_preview(s, frac)
	if not p["ok"]:
		return _fail(p["reason"])
	var spend: BigNum = p["spend"]
	s.set_cur("compute", s.cur("compute").subtract(spend))
	if s.resets(3) > 0:
		s.set_cur("energy", s.cur("energy").subtract(_big(TRAIN_ENERGY)))
		s.set_cur("data", s.cur("data").subtract(_big(TRAIN_DATA)))
	s.run["layers"][0]["training"] = {
		"frac": frac, "log": spend.log10(), "left": TRAIN_SECONDS, "fail": p["fail_chance"],
	}
	return {"ok": true, "spend": spend, "seconds": TRAIN_SECONDS}


static func _train_tick(s: GameState, dt: float, evs: Array) -> void:
	var L0: Dictionary = s.run["layers"][0]
	var t: Dictionary = L0["training"]
	if t.is_empty():
		return
	t["left"] = float(t["left"]) - dt
	if float(t["left"]) > 0.0:
		return
	L0["training"] = {}
	s.persist["stats"]["trainings"] = int(s.persist["stats"]["trainings"]) + 1
	if s.rng.randf() < float(t["fail"]):
		s.persist["stats"]["failed"] = int(s.persist["stats"]["failed"]) + 1
		evs.append({"kind": "training_done", "ok": false})
		return
	var score := float(t["log"]) * Rules.mult(s, "training") * s.rng.randf_range(0.95, 1.05)
	var L2: Dictionary = s.run["layers"][2]
	L2["best"] = maxf(float(L2["best"]), score)
	s.persist["best_all"] = maxf(float(s.persist["best_all"]), score)
	evs.append({"kind": "training_done", "ok": true, "score": score})


# ---------------------------------------------------------------- resets

static func layer_def(s: GameState, k: int):
	for d in s.db.get_all("layers"):
		if d.index == k:
			return d
	return null


static func reset_preview(s: GameState, k: int) -> Dictionary:
	var ld = layer_def(s, k)
	if ld == null:
		return {"layer": k, "currency": "", "gain": 0, "holding": BigNum.new(), "highlight": false, "allowed": false, "reason": "no such layer"}
	var L: Dictionary = s.run["layers"][k]
	# Plain floats: BigNum divide leaves 3.9999... for exact ratios, which would floor one short.
	var q: float = (L["life"] as BigNum).to_float() / float(ld.threshold)
	var gain := int(minf(floor(sqrt(q) + 1e-9), 1e15))
	var holding: BigNum = s.cur(ld.currency)
	var reason := ""
	if gain < 1:
		reason = "no gain yet"
	elif k > 1 and s.resets(k - 1) == 0:
		reason = "finish reset %d first" % (k - 1)
	return {
		"layer": k, "currency": ld.currency, "gain": gain, "holding": holding,
		"highlight": gain > 0 and _big(float(gain)).gte(holding.mul_f(2.0)),
		"allowed": reason == "", "reason": reason,
	}


static func perform_reset(s: GameState, k: int) -> Dictionary:
	var p := reset_preview(s, k)
	if not p["allowed"]:
		return _fail(p["reason"])
	for j in k:
		s.run["layers"][j] = GameState.fresh_layer()
	s.set_cur("cash", BigNum.from_float(GameState.START_CASH))  # layer 0 was wiped; bootstrap income
	var L: Dictionary = s.run["layers"][k]
	L["life"] = BigNum.new()
	L["clock"] = 0.0
	s.add_cur(p["currency"], _big(float(p["gain"])))
	s.run["resets_done"][k - 1] = int(s.run["resets_done"][k - 1]) + 1
	s.persist["stats"]["resets"] = int(s.persist["stats"]["resets"]) + 1
	return {"ok": true, "layer": k, "gain": p["gain"], "currency": p["currency"]}


# ---------------------------------------------------------------- events

static func resolve_event(s: GameState, choice: int) -> Dictionary:
	var L0: Dictionary = s.run["layers"][0]
	if L0["pending"] == "":
		return _fail("no pending event")
	var d = s.db.get_def("events", L0["pending"])
	if choice < 0 or choice >= d.choices.size():
		return _fail("no such choice")
	for e in d.choices[choice]["effects"]:
		Rules.apply(s, e)
	L0["cooldowns"][d.id] = float(d.cooldown)
	L0["pending"] = ""
	s.persist["stats"]["events"] = int(s.persist["stats"]["events"]) + 1
	return {"ok": true, "id": d.id, "choice": choice}


static func _events_tick(s: GameState, dt: float, evs: Array) -> void:
	var L0: Dictionary = s.run["layers"][0]
	L0["event_timer"] = float(L0["event_timer"]) - dt
	if L0["pending"] != "" or float(L0["event_timer"]) > 0.0:
		return
	L0["event_timer"] = EVENT_INTERVAL
	if s.rng.randf() >= EVENT_CHANCE:
		return
	var pool: Array = []
	var total := 0.0
	for d in s.db.get_all("events"):
		if L0["cooldowns"].has(d.id) or not Rules.check_all(s, d.conditions):
			continue
		pool.append(d)
		total += float(d.weight)
	if pool.is_empty():
		return
	var r := s.rng.randf() * total
	var pick = pool.back()
	for d in pool:
		r -= float(d.weight)
		if r < 0.0:
			pick = d
			break
	L0["pending"] = pick.id
	evs.append({"kind": "event", "id": pick.id})


# ---------------------------------------------------------------- challenges (singularity)

static func start_challenge(s: GameState, id: String) -> Dictionary:
	var d = s.db.get_def("challenges", id)
	if d == null:
		return _fail("unknown challenge")
	if s.resets(4) == 0:
		return _fail("regulation challenges unlock after the Singularity")
	if not (s.run["layers"][4]["challenge"] as Dictionary).is_empty():
		return _fail("a challenge is already running")
	if id in s.run["challenges_done"]:
		return _fail("already completed")
	s.run["layers"][4]["challenge"] = {"id": id, "left": float(d.duration)}
	return {"ok": true}


static func _challenge_tick(s: GameState, dt: float, evs: Array) -> void:
	var L4: Dictionary = s.run["layers"][4]
	var c: Dictionary = L4["challenge"]
	if c.is_empty():
		return
	c["left"] = float(c["left"]) - dt
	if float(c["left"]) > 0.0:
		return
	var d = s.db.get_def("challenges", c["id"])
	var success := Rules.check_all(s, d.goal)
	for e in (d.reward if success else d.penalty):
		Rules.apply(s, e)
	s.run["challenges_done"].append(c["id"])
	L4["challenge"] = {}
	evs.append({"kind": "challenge_done", "id": c["id"], "success": success})


# ---------------------------------------------------------------- automation / benchmarks / AGI / rivals

static func _auto_reset(s: GameState, k: int, evs: Array) -> void:
	var p := reset_preview(s, k)
	if p["allowed"] and p["highlight"]:
		var r := perform_reset(s, k)
		evs.append({"kind": "reset", "layer": k, "gain": r["gain"]})


static func _automate(s: GameState, evs: Array) -> void:
	var auto: Array = s.persist["automation"]
	if "auto_buy" in auto:
		for d in producers(s):
			var n := max_affordable(s, d.id)
			if n > 0 and producer_available(s, d.id):
				buy_producer(s, d.id, n)
	if "auto_train" in auto:
		var r := start_training(s, 0.25)
		if r["ok"]:
			evs.append({"kind": "auto_train"})
	if "auto_fund" in auto:
		_auto_reset(s, 1, evs)
	if "auto_gen" in auto:
		_auto_reset(s, 2, evs)


static func _benchmarks(s: GameState, evs: Array) -> void:
	for b in s.db.get_all("benchmarks"):
		if b.id in s.persist["benchmarks"] or not Rules.check_all(s, b.conditions):
			continue
		s.persist["benchmarks"].append(b.id)
		for e in b.effects:
			Rules.apply(s, e)
		evs.append({"kind": "benchmark", "id": b.id, "badge": b.badge})


static func _agi(s: GameState, evs: Array) -> void:
	var stages: Array = s.db.get_all("agi_stages")
	while s.run["stage"] < stages.size() and Rules.check_all(s, stages[s.run["stage"]].conditions):
		s.run["stage"] = int(s.run["stage"]) + 1
		evs.append({"kind": "agi_advanced", "index": s.run["stage"]})
	if s.run["stage"] >= stages.size() and s.run["run_over"] == "":
		for e in s.db.get_all("endings"):
			if Rules.check_all(s, e.conditions):
				s.run["run_over"] = e.id
				evs.append({"kind": "ending", "id": e.id})
				break


static func _rivals(s: GameState, evs: Array) -> void:
	if s.resets(4) == 0:
		return
	var clock := float(s.run["layers"][4]["clock"])
	for r in s.db.get_all("rivals"):
		var flag := "rival_%s_launched" % r.id
		if bool(s.run["flags"].get(flag, false)):
			continue
		var progress := float(s.run["rivals"].get(r.id, 0.0))
		# rival_progress > 0 speeds a rival up; < 0 delays it (floor at 10% of its schedule)
		var at := float(r.launch_hours) * 3600.0 * maxf(0.1, 1.0 - progress)
		if clock >= at:
			s.run["flags"][flag] = true
			evs.append({"kind": "rival_launched", "id": r.id})


# ---------------------------------------------------------------- tick

## Advances the game by dt seconds. offline=true halves income and skips random events.
static func tick(s: GameState, dt: float, offline: bool = false) -> Array:
	var evs: Array = []
	var eff := OFFLINE_EFF if offline else 1.0
	var L0: Dictionary = s.run["layers"][0]

	var compute_gain := compute_per_second(s).mul_f(dt * eff)
	var cash_gain := cash_per_second(s).mul_f(dt * eff)
	s.add_cur("compute", compute_gain)
	s.add_cur("cash", cash_gain)
	for k in range(1, 5):
		s.run["layers"][k]["life"] = (s.run["layers"][k]["life"] as BigNum).add(cash_gain)

	for k in 5:
		s.run["layers"][k]["clock"] = float(s.run["layers"][k]["clock"]) + dt
	s.persist["stats"]["time"] = float(s.persist["stats"]["time"]) + dt
	for id in L0["cooldowns"].keys():
		L0["cooldowns"][id] = float(L0["cooldowns"][id]) - dt
		if L0["cooldowns"][id] <= 0.0:
			L0["cooldowns"].erase(id)
	for i in range(L0["timed"].size() - 1, -1, -1):
		L0["timed"][i]["left"] = float(L0["timed"][i]["left"]) - dt
		if L0["timed"][i]["left"] <= 0.0:
			L0["timed"].remove_at(i)

	_train_tick(s, dt, evs)
	if s.resets(3) > 0:
		s.add_cur("data", _big(DATA_RATE * dt * eff))
		var energy := s.cur("energy").add(_big(ENERGY_RATE * dt * eff))
		s.set_cur("energy", energy if energy.compare(_big(ENERGY_CAP)) <= 0 else _big(ENERGY_CAP))
	if s.resets(2) > 0 and float(s.run["slider"]) < SLIDER_SAFE:
		L0["debt"] = float(L0["debt"]) + DEBT_RATE * dt * eff

	_automate(s, evs)
	_benchmarks(s, evs)
	_agi(s, evs)
	_rivals(s, evs)
	_challenge_tick(s, dt, evs)
	if not offline:
		_events_tick(s, dt, evs)
	return evs


## Simulates `seconds` away from the game in 60 s steps, capped at 24 h.
static func offline(s: GameState, seconds: float) -> Dictionary:
	var secs := minf(seconds, OFFLINE_CAP)
	var c0 := s.cur("cash")
	var k0 := s.cur("compute")
	var events: Array = []
	var left := secs
	while left > 0.0:
		var step := minf(OFFLINE_STEP, left)
		events.append_array(tick(s, step, true))
		left -= step
	return {
		"seconds": secs, "capped": seconds > OFFLINE_CAP,
		"cash": s.cur("cash").subtract(c0), "compute": s.cur("compute").subtract(k0),
		"events": events,
	}
