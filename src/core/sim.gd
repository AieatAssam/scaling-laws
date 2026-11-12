class_name Sim
## Simulation step and player actions. Pure: all state lives in GameState, all content in s.db.
## Actions return {ok: bool, reason: String, ...}. tick() returns Array of event dicts {kind, ...}.

const REVENUE := 0.5             # cash per compute/sec (before cash mults)
const COST_GROWTH := 1.15
const MILESTONES := [25, 50, 100, 200]   # each milestone doubles that producer's output
const MIN_TRAIN_SPEND := 100.0
const TRAIN_ENERGY := 10.0
const TRAIN_DATA := 2.0
const REFUND_SHARE := 0.5        # a failed run returns this share of its spend to compute
const SCORE_ROLL := 0.02         # run score is rolled up or down by this share
const FAIL_FLOOR := 0.4          # staff can cut a run's fail chance to this share of its base at most
const AUTO_TRAIN_RUN := "standard"   # run type that auto_train starts
const DATA_RATE := 0.1           # data/sec once Paradigm Shift is done
const ENERGY_RATE := 1.0
const ENERGY_CAP := 100.0
const DEBT_RATE := 0.002         # debt/sec while slider < SLIDER_SAFE
const SLIDER_SAFE := 0.3
const EVENT_INTERVAL := 90.0
const EVENT_CHANCE := 0.5
const EVENT_MIN_SECONDS := 120.0  # no events in the first two minutes of a run (layer-0 clock)
const EVENT_MIN_PRODUCERS := 3    # ...or before a few producers exist
const OFFLINE_CAP := 86400.0
const OFFLINE_EFF := 0.5
const OFFLINE_STEP := 60.0
const LEGACY_MULT := 1.1
const AUTO_RESET_MIN_SECONDS := 60.0   # minimum layer clock before an automatic reset of that layer


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


## Best tier to buy next: available tier with the lowest cost per unit of output. "" if none.
## auto_buy waits on this tier when unaffordable instead of buying cheaper, worse tiers.
static func best_producer(s: GameState) -> String:
	var best := ""
	var best_ratio := INF
	for d in producers(s):
		if not producer_available(s, d.id):
			continue
		var n := s.owned(d.id) + 1
		var m := 1
		for ms in MILESTONES:
			if n >= ms:
				m *= 2
		var ratio := cost_for(s, d.id, 1).log10() - _log10(float(d.base_output) * m)
		if ratio < best_ratio:
			best_ratio = ratio
			best = d.id
	return best


# ---------------------------------------------------------------- economy

## Output of producer `id` per second before the compute multiplier (milestone doublings included).
static func producer_raw_rate(s: GameState, id: String) -> BigNum:
	var d = s.db.get_def("producers", id)
	var n := s.owned(id)
	var m := 1
	for ms in MILESTONES:
		if n >= ms:
			m *= 2
	return _big(float(d.base_output) * n * m)


static func raw_rate(s: GameState) -> BigNum:
	var total := BigNum.new()
	for d in producers(s):
		total = total.add(producer_raw_rate(s, d.id))
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

## Cost of hiring `count` more of `role` at the current headcount.
static func staff_cost(s: GameState, role: String, count: int = 1) -> BigNum:
	var d = s.db.get_def("staff", role)
	return _series(_big(d.base_cost), d.cost_growth, int(s.run["layers"][1]["staff"].get(role, 0)), count)


## Why `hire` would fail, or "" when it would succeed.
static func hire_blocker(s: GameState, role: String, count: int = 1) -> String:
	if s.db.get_def("staff", role) == null:
		return "unknown staff role"
	if s.resets(1) == 0:
		return "hiring unlocks after a Funding Round"
	if count < 1:
		return "count must be >= 1"
	if s.cur("equity").compare(staff_cost(s, role, count)) < 0:
		return "not enough equity"
	return ""


static func hire(s: GameState, role: String, count: int = 1) -> Dictionary:
	var reason := hire_blocker(s, role, count)
	if reason != "":
		return _fail(reason)
	var staff: Dictionary = s.run["layers"][1]["staff"]
	var cost := staff_cost(s, role, count)
	s.set_cur("equity", s.cur("equity").subtract(cost))
	staff[role] = int(staff.get(role, 0)) + count
	return {"ok": true, "count": count, "cost": cost}


## Why `research` would fail, or "" when it would succeed.
static func research_blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("research", id)
	if d == null:
		return "unknown research"
	if s.resets(2) == 0:
		return "research unlocks after a Model Generation"
	var L2: Dictionary = s.run["layers"][2]
	if id in L2["research"]:
		return "already researched"
	for p in d.prereqs:
		if not (p in L2["research"]):
			return "requires %s" % p
	if d.branch != "":
		for r in Rules.owned_research(s):
			if r.branch != "" and r.branch != d.branch:
				return "exclusive with the %s branch" % r.branch
	if s.cur("insights").compare(_big(float(d.cost))) < 0:
		return "not enough insights"
	return ""


static func research(s: GameState, id: String) -> Dictionary:
	var reason := research_blocker(s, id)
	if reason != "":
		return _fail(reason)
	var L2: Dictionary = s.run["layers"][2]
	var cost := _big(float(s.db.get_def("research", id).cost))
	s.set_cur("insights", s.cur("insights").subtract(cost))
	L2["research"].append(id)
	return {"ok": true, "cost": cost}


## Why `buy_automation` would fail, or "" when it would succeed.
static func automation_blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("automation", id)
	if d == null:
		return "unknown automation"
	if s.resets(3) == 0:
		return "automation unlocks after a Paradigm Shift"
	var owned: Array = s.persist["automation"]
	if id in owned:
		return "already owned"
	for a in s.db.get_all("automation"):
		if a.order < d.order and not (a.id in owned):
			return "requires %s" % a.id
	if s.cur("breakthroughs").compare(_big(float(d.cost))) < 0:
		return "not enough breakthroughs"
	return ""


static func buy_automation(s: GameState, id: String) -> Dictionary:
	var reason := automation_blocker(s, id)
	if reason != "":
		return _fail(reason)
	var cost := _big(float(s.db.get_def("automation", id).cost))
	s.set_cur("breakthroughs", s.cur("breakthroughs").subtract(cost))
	(s.persist["automation"] as Array).append(id)
	return {"ok": true, "cost": cost}


## Legacy price of the next perk `key`: 2^n after n purchases of it.
static func legacy_cost(s: GameState, key: String) -> BigNum:
	return _big(pow(2.0, int(s.persist["legacy_perks"].get(key, 0))))


## Why `buy_legacy` would fail, or "" when it would succeed.
static func legacy_blocker(s: GameState, key: String) -> String:
	if s.resets(4) == 0:
		return "legacy unlocks after the Singularity"
	if s.cur("legacy").compare(legacy_cost(s, key)) < 0:
		return "not enough legacy"
	return ""


static func buy_legacy(s: GameState, key: String) -> Dictionary:
	var reason := legacy_blocker(s, key)
	if reason != "":
		return _fail(reason)
	var perks: Dictionary = s.persist["legacy_perks"]
	var n := int(perks.get(key, 0))
	var cost := legacy_cost(s, key)
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
	var legacy := s.cur("legacy")  # lives in layer 4 but is persistent: a new run must not wipe it
	s.run = GameState.fresh_run()
	s.set_cur("legacy", legacy)
	s.persist["stats"]["runs"] = int(s.persist["stats"]["runs"]) + 1
	return {"ok": true}


# ---------------------------------------------------------------- training

## Training multipliers by source. `total` is the full training multiplier applied to the score.
static func training_factors(s: GameState) -> Dictionary:
	var data := 1.0
	var arch := 1.0
	for r in Rules.owned_research(s):
		for e in r.effects:
			if e["key"] == "training":
				if r.branch == "":
					data *= float(e["value"])
				else:
					arch *= float(e["value"])
	var researcher := 1.0
	for st in s.db.get_all("staff"):
		if st.bonus_key == "training":
			researcher *= 1.0 + float(st.bonus_per_hire) * int(s.run["layers"][1]["staff"].get(st.id, 0))
	return {"data": data, "architecture": arch, "researcher": researcher, "total": Rules.mult(s, "training")}


## Run type `id` from content/training_runs, or null.
static func run_def(s: GameState, id: String):
	return s.db.get_def("training_runs", id)


## Staff cut training fail chance: 1 - sum(fail_per_hire × hires), floored at FAIL_FLOOR.
static func training_fail_factor(s: GameState) -> float:
	var cut := 0.0
	for st in s.db.get_all("staff"):
		cut += float(st.fail_per_hire) * int(s.run["layers"][1]["staff"].get(st.id, 0))
	return maxf(FAIL_FLOOR, 1.0 - cut)


## What run type `id` would do now. Keys: ok, reason, id, title, spend, seconds, score_mult, base_fail, fail_factor,
## fail_chance (composed), min_compute, predicted_score (no roll), bonus_now and bonus_if_success (compute bonus
## before and after the predicted score lands), factors.
static func training_preview(s: GameState, id: String) -> Dictionary:
	var d = run_def(s, id)
	if d == null:
		return {"ok": false, "reason": "unknown run type", "id": id}
	var share: float = d.spend_share
	var spend: BigNum = s.cur("compute").mul_f(share)
	var energy_ok := s.resets(3) == 0 or (s.cur("energy").gte(_big(TRAIN_ENERGY)) and s.cur("data").gte(_big(TRAIN_DATA)))
	var factors := training_factors(s)
	var predicted := 0.0 if spend.is_zero() else spend.log10() * float(factors["total"]) * float(d.score_mult)
	var factor := training_fail_factor(s)
	var p := {
		"ok": false, "reason": "", "id": id, "title": d.title, "spend": spend, "seconds": float(d.seconds),
		"score_mult": float(d.score_mult),
		"base_fail": float(d.fail_chance), "fail_factor": factor, "fail_chance": float(d.fail_chance) * factor,
		# Smallest compute stock at which this share meets MIN_TRAIN_SPEND.
		"min_compute": _big(MIN_TRAIN_SPEND / share) if share > 0.0 else BigNum.new(),
		"predicted_score": predicted,
		"bonus_now": Rules.training_bonus(s),
		"bonus_if_success": Rules.training_bonus_for(
			maxf(float(s.run["layers"][2]["best"]), predicted), maxf(float(s.persist["best_all"]), predicted)),
		"factors": factors,
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


static func start_training(s: GameState, id: String) -> Dictionary:
	var p := training_preview(s, id)
	if not p["ok"]:
		return _fail(p["reason"])
	var spend: BigNum = p["spend"]
	s.set_cur("compute", s.cur("compute").subtract(spend))
	if s.resets(3) > 0:
		s.set_cur("energy", s.cur("energy").subtract(_big(TRAIN_ENERGY)))
		s.set_cur("data", s.cur("data").subtract(_big(TRAIN_DATA)))
	s.run["layers"][0]["training"] = {
		"type": id, "spend": spend.to_json(), "log": spend.log10(), "left": p["seconds"],
		"fail": p["fail_chance"], "score_mult": p["score_mult"],
	}
	return {"ok": true, "id": id, "spend": spend, "seconds": p["seconds"]}


## Finishes a run when its clock runs out. A failed run refunds REFUND_SHARE of its spend. A success scores
## log10(spend) × training multiplier × run score_mult × a roll of ±SCORE_ROLL, and only raises the bests.
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
		var refund := BigNum.from_json(t["spend"]).mul_f(REFUND_SHARE)
		s.add_cur("compute", refund)
		evs.append({"kind": "training_done", "ok": false, "id": t["type"], "refund": refund})
		return
	var score := float(t["log"]) * Rules.mult(s, "training") * float(t["score_mult"]) \
		* s.rng.randf_range(1.0 - SCORE_ROLL, 1.0 + SCORE_ROLL)
	var L2: Dictionary = s.run["layers"][2]
	var new_best := score > float(L2["best"])
	var new_all := score > float(s.persist["best_all"])
	L2["best"] = maxf(float(L2["best"]), score)
	s.persist["best_all"] = maxf(float(s.persist["best_all"]), score)
	evs.append({"kind": "training_done", "ok": true, "id": t["type"], "score": score,
		"new_best": new_best, "new_all_time": new_all})


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
		# gain 1 is not worth a reset: without this, holding 0 makes every cycle highlight and auto_* churns.
		"highlight": gain >= 2 and _big(float(gain)).gte(holding.mul_f(2.0)),
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
	s.persist["lifetime_resets"][k - 1] = int(s.persist["lifetime_resets"][k - 1]) + 1
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


## An event may be offered only when every choice's effects are unlocked (see Rules.effect_blocker).
static func event_eligible(s: GameState, d) -> bool:
	for ch in d.choices:
		for e in ch["effects"]:
			if Rules.effect_blocker(s, e) != "":
				return false
	return true


## Clears a pending event that a save left behind with a choice that is now locked (saves from before the gate).
static func drop_stale_pending(s: GameState) -> void:
	var L0: Dictionary = s.run["layers"][0]
	var pend: String = L0["pending"]
	var d = s.db.get_def("events", pend) if pend != "" else null
	if pend != "" and (d == null or not event_eligible(s, d)):
		L0["pending"] = ""


static func _events_open(s: GameState) -> bool:
	var owned := 0
	for d in producers(s):
		owned += s.owned(d.id)
	return float(s.run["layers"][0]["clock"]) >= EVENT_MIN_SECONDS and owned >= EVENT_MIN_PRODUCERS


static func _events_tick(s: GameState, dt: float, evs: Array) -> void:
	var L0: Dictionary = s.run["layers"][0]
	L0["event_timer"] = float(L0["event_timer"]) - dt
	if L0["pending"] != "" or float(L0["event_timer"]) > 0.0:
		return
	if not _events_open(s):
		return  # timer stays due: the first roll happens as soon as the run is underway
	L0["event_timer"] = EVENT_INTERVAL
	if s.rng.randf() >= EVENT_CHANCE:
		return
	var pool: Array = []
	var total := 0.0
	for d in s.db.get_all("events"):
		if L0["cooldowns"].has(d.id) or not Rules.check_all(s, d.conditions) or not event_eligible(s, d):
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

## Why `start_challenge` would fail, or "" when it would succeed.
static func challenge_blocker(s: GameState, id: String) -> String:
	if s.db.get_def("challenges", id) == null:
		return "unknown challenge"
	if s.resets(4) == 0:
		return "regulation challenges unlock after the Singularity"
	if not (s.run["layers"][4]["challenge"] as Dictionary).is_empty():
		return "a challenge is already running"
	if id in s.run["challenges_done"]:
		return "already completed"
	return ""


static func start_challenge(s: GameState, id: String) -> Dictionary:
	var reason := challenge_blocker(s, id)
	if reason != "":
		return _fail(reason)
	s.run["layers"][4]["challenge"] = {"id": id, "left": float(s.db.get_def("challenges", id).duration)}
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
	var passed: Dictionary = s.run.get("challenge_passed", {})
	passed[c["id"]] = success
	s.run["challenge_passed"] = passed
	L4["challenge"] = {}
	evs.append({"kind": "challenge_done", "id": c["id"], "success": success})


## Cancels the running challenge: no reward, no penalty, and it stays available to enter again.
static func abandon_challenge(s: GameState) -> Dictionary:
	var c: Dictionary = s.run["layers"][4]["challenge"]
	if c.is_empty():
		return _fail("no challenge running")
	s.run["layers"][4]["challenge"] = {}
	return {"ok": true, "id": c["id"]}


# ---------------------------------------------------------------- automation / benchmarks / AGI / rivals

## Automatic reset: when highlighted. The layer clock is zeroed by any reset of the layer, so requiring
## clock >= AUTO_RESET_MIN_SECONDS also spaces automatic resets of one layer apart.
static func _auto_reset(s: GameState, k: int, evs: Array) -> void:
	var p := reset_preview(s, k)
	var due := float(s.run["layers"][k]["clock"]) >= AUTO_RESET_MIN_SECONDS
	if p["allowed"] and p["highlight"] and due:
		var r := perform_reset(s, k)
		evs.append({"kind": "reset", "layer": k, "gain": r["gain"]})


static func _automate(s: GameState, evs: Array) -> void:
	var auto: Array = s.persist["automation"]
	if "auto_buy" in auto:
		var id := best_producer(s)
		while id != "" and max_affordable(s, id) > 0:
			buy_producer(s, id, max_affordable(s, id))
			id = best_producer(s)
	if "auto_train" in auto:
		var r := start_training(s, AUTO_TRAIN_RUN)
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


## Singularity-layer clock (seconds) at which rival `id` launches. rival_progress > 0 speeds a rival up;
## < 0 delays it (floored at 10% of its schedule).
static func rival_launch_time(s: GameState, id: String) -> float:
	var r = s.db.get_def("rivals", id)
	var progress := float(s.run["rivals"].get(id, 0.0))
	return float(r.launch_hours) * 3600.0 * maxf(0.1, 1.0 - progress)


static func _rivals(s: GameState, evs: Array) -> void:
	if s.resets(4) == 0:
		return
	var clock := float(s.run["layers"][4]["clock"])
	for r in s.db.get_all("rivals"):
		var flag := "rival_%s_launched" % r.id
		if bool(s.run["flags"].get(flag, false)):
			continue
		if clock >= rival_launch_time(s, r.id):
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
