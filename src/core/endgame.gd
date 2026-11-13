class_name Endgame
extends RefCounted
## Singularity finale. Pure: state in GameState, content in s.db.
##   AGI: run.stage counts stages unlocked (threshold met). Each cleared stage appends its method to run.agi_choices.
##   A stage is cleared by "full" (AGI safety eval suite), "redteam" (community red-team) or "ship" (instant).
##   The ending is the majority of the five choices; a tie goes to the method chosen most recently (rfind).
##   Rivals: each races from the moment its target stage (RivalDef.outpace_stage) unlocks. Outship delays it,
##   Acqui-hire slows it. Clearing the target stage first is "outpaced".
##   Challenge tiers: tier N+1 needs tier N passed ever (records.challenges); perm rewards share a cap.

const METHODS := ["full", "redteam", "ship"]
const TITLES := {"full": "Full eval suite", "redteam": "Community red-team", "ship": "Ship it"}
const COUNTER := {"full": "Assurance", "redteam": "Openness", "ship": "Recklessness"}
const FULL_SECONDS := 43200.0
const FULL_BASE := 0.5
const FULL_SLIDER := 0.4
const FULL_OPS := 0.02
const FULL_CAP := 0.97
const FULL_COOLDOWN := 3600.0
const RED_SECONDS := 21600.0
const RED_PASS := 0.7
const RED_SPEED := 0.05          # rival speed per community red-team run, persistent (persist.redteam_uses)
const SHIP_CUT := 0.7            # the stage after a Ship it choice needs 30% less of each numeric requirement
const RECK_RIVAL := 0.1          # rival speed per Ship it choice in this run (rivals hear about the release)
const RECK_SEVERITY := 0.25      # bad events: alignment and reputation losses per Ship it choice in this run
const BAD_CATEGORIES := ["incident", "outage"]
const RECK_CURRENCY := "equity"  # the reputation-like currency that bad events cost under recklessness
const ACQUI_SPEED := 0.75
const ACQUI_CASH_SECONDS := 7200.0
const ACQUI_COOLDOWN := 3600.0
const OUTSHIP_COST := 1e6
const OUTSHIP_COST_GROWTH := 4.0
const OUTSHIP_GAIN := 0.5        # each Outship adds this share of the delay still missing
const OUTSHIP_MAX := 1.0         # total delay capped at +100% of a rival's base schedule
const OUTSHIP_COOLDOWN := 1800.0
const CHALLENGE_CAP := 1.4       # total permanent multiplier from challenge rewards


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ---------------------------------------------------------------- choices and endings

## Choices made so far, by method: {full, redteam, ship}.
static func counts(choices: Array) -> Dictionary:
	var c := {"full": 0, "redteam": 0, "ship": 0}
	for m in choices:
		c[m] = int(c[m]) + 1
	return c


## The method that wins the run; "" with no choices. Ties go to the method chosen most recently.
static func majority(choices: Array) -> String:
	var c := counts(choices)
	var top := 0
	for m in METHODS:
		top = maxi(top, int(c[m]))
	var best := ""
	var best_at := -1
	for m in METHODS:
		if top > 0 and int(c[m]) == top and choices.rfind(m) > best_at:
			best_at = choices.rfind(m)
			best = m
	return best


static func ending_for(s: GameState, method: String):
	for e in s.db.get_all("endings"):
		if String(e.method) == method:
			return e
	return null


## Title of the ending the choices so far point at, or "" when there are none yet.
static func trajectory(s: GameState) -> String:
	var e = ending_for(s, majority(s.run["agi_choices"]))
	return String(e.title) if e != null else ""


## Index of the AGI stage waiting for a choice (unlocked, not yet cleared), or -1.
static func pending_index(s: GameState) -> int:
	var idx := (s.run["agi_choices"] as Array).size()
	return idx if idx < int(s.run["stage"]) and idx < s.db.get_all("agi_stages").size() else -1


## Conditions of the stage at `index` (0-based) as they now stand. A Ship it choice as the last decision cuts the next
## stage's numeric requirements by SHIP_CUT; integer gates (resets_gte, owned counts stay whole) are cut the same way
## except resets_gte, which is a layer-reset gate and never cut.
static func stage_conditions(s: GameState, index: int) -> Array:
	var stages: Array = s.db.get_all("agi_stages")
	var conds: Array = stages[index].conditions
	var choices: Array = s.run["agi_choices"]
	var ship_cut: bool = not choices.is_empty() and choices.back() == "ship"
	var out: Array = []
	for c in conds:
		var d: Dictionary = c.duplicate()
		if ["compute_rate_gte", "owned_gte", "currency_gte", "training_best_gte"].has(d["type"]):
			d["_agi_peak"] = true
		if ship_cut and d["type"] != "resets_gte" and d.has("value"):
			d["value"] = float(d["value"]) * SHIP_CUT
		out.append(d)
	return out


## AGI milestones use maxima held for this Singularity run, across lower-layer wipes.
static func track_peaks(s: GameState) -> void:
	s.run["peak_compute_rate"] = maxf(float(s.run.get("peak_compute_rate", 0.0)), Sim.compute_per_second(s).to_float())
	var peaks: Dictionary = s.run.get("agi_peaks", {"owned": {}, "energy": 0.0, "training_best": 0.0})
	var owned: Dictionary = peaks.get("owned", {})
	for d in s.db.get_all("agi_stages"):
		for c in d.conditions:
			match c["type"]:
				"owned_gte":
					owned[c["id"]] = maxi(int(owned.get(c["id"], 0)), s.owned(c["id"]))
				"currency_gte":
					if c["id"] == "energy":
						peaks["energy"] = maxf(float(peaks.get("energy", 0.0)), s.cur("energy").to_float())
				"training_best_gte":
					peaks["training_best"] = maxf(float(peaks.get("training_best", 0.0)), float(s.run["layers"][2]["best"]))
	peaks["owned"] = owned
	s.run["agi_peaks"] = peaks


static func peak_value(s: GameState, c: Dictionary):
	match c["type"]:
		"compute_rate_gte": return BigNum.from_float(float(s.run.get("peak_compute_rate", 0.0)))
		"owned_gte": return int(s.run["agi_peaks"].get("owned", {}).get(c["id"], 0))
		"currency_gte": return BigNum.from_float(float(s.run["agi_peaks"].get("energy", 0.0)))
		"training_best_gte": return float(s.run["agi_peaks"].get("training_best", 0.0))
	return null


static func unlock_stages(s: GameState, evs: Array) -> void:
	var stages: Array = s.db.get_all("agi_stages")
	while int(s.run["stage"]) < stages.size() and int(s.run["stage"]) <= (s.run["agi_choices"] as Array).size() and Rules.check_all(s, stage_conditions(s, int(s.run["stage"]))):
		s.run["stage"] = int(s.run["stage"]) + 1
		evs.append({"kind": "agi_advanced", "index": s.run["stage"]})


# ---------------------------------------------------------------- evals

static func seconds(method: String) -> float:
	match method:
		"full":
			return FULL_SECONDS
		"redteam":
			return RED_SECONDS
	return 0.0


static func ops_staff(s: GameState) -> int:
	return int(s.run["layers"][1]["staff"].get("ops", 0))


## Chance that `method` clears the pending stage. Ship it always clears.
static func pass_chance(s: GameState, method: String) -> float:
	match method:
		"full":
			return minf(FULL_CAP, FULL_BASE + FULL_SLIDER * float(s.run["slider"]) + FULL_OPS * ops_staff(s))
		"redteam":
			return RED_PASS
	return 1.0


static func choice_blocker(s: GameState, method: String) -> String:
	if not METHODS.has(method):
		return "unknown method"
	if String(s.run["run_over"]) != "":
		return "the run is over"
	if pending_index(s) < 0:
		return "no AGI stage is waiting for a choice"
	if not (s.run["eval"] as Dictionary).is_empty():
		return "an evaluation is already running"
	if method == "full" and float(s.run["eval_cooldown"]) > 0.0:
		return "full suite cooling down"
	return ""


## Clears the pending stage with `method`: Ship it at once, the others start an evaluation.
## Returns {ok, reason, index, method, events}. Events are dispatched by Game.
static func start_choice(s: GameState, method: String) -> Dictionary:
	var reason := choice_blocker(s, method)
	if reason != "":
		return _fail(reason)
	var idx := pending_index(s)
	var evs: Array = []
	if method == "ship":
		_clear(s, idx, "ship", evs)
	else:
		s.run["eval"] = {"method": method, "index": idx, "left": seconds(method)}
	return {"ok": true, "index": idx, "method": method, "events": evs}


## Unlocks AGI stages, then runs evaluations, the full-suite cooldown and the rival race. Full speed offline too (raw dt).
static func tick(s: GameState, dt: float, evs: Array) -> void:
	track_peaks(s)
	unlock_stages(s, evs)
	s.run["eval_cooldown"] = maxf(float(s.run["eval_cooldown"]) - dt, 0.0)
	var ev: Dictionary = s.run["eval"]
	if not ev.is_empty():
		ev["left"] = float(ev["left"]) - dt
		if float(ev["left"]) <= 0.0:
			_finish_eval(s, evs)
	var cool: Dictionary = s.run["race"]["cool"]
	for k in cool.keys():
		cool[k] = float(cool[k]) - dt
		if float(cool[k]) <= 0.0:
			cool.erase(k)
	race_tick(s, dt, evs)


static func _finish_eval(s: GameState, evs: Array) -> void:
	var ev: Dictionary = s.run["eval"]
	s.run["eval"] = {}
	var m := String(ev["method"])
	var idx := int(ev["index"])
	# Own stream per roll: the shared rng would shift every later event and desk draw by however many evals ran,
	# so two endings with the same choices would drift apart. Seeded from the run seed and a roll counter.
	s.persist["eval_rolls"] = int(s.persist.get("eval_rolls", 0)) + 1
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([int(s.persist.get("eval_seed", 1)), int(s.persist["eval_rolls"])])
	var passed := roll.randf() < pass_chance(s, m)
	if m == "redteam":
		s.persist["redteam_uses"] = int(s.persist.get("redteam_uses", 0)) + 1
	if passed:
		_clear(s, idx, m, evs)
	else:
		if m == "full":
			s.run["eval_cooldown"] = FULL_COOLDOWN
		evs.append({"kind": "agi_failed", "index": idx, "method": m})


## Records a cleared stage: its choice, the counters, outpaced rivals and, after the fifth, the ending.
static func _clear(s: GameState, idx: int, m: String, evs: Array) -> void:
	var choices: Array = s.run["agi_choices"]
	choices.append(m)
	var stats: Dictionary = s.persist["stats"]
	var key := "ships" if m == "ship" else "evals_passed"
	stats[key] = int(stats.get(key, 0)) + 1
	evs.append({"kind": "agi_cleared", "index": idx, "method": m})
	for r in s.db.get_all("rivals"):
		if int(r.outpace_stage) == idx + 1 and racing(s, r):
			s.run["flags"]["outpaced_%s" % r.id] = true
			Records.note(s.persist, "outpaced", r.id)
			evs.append({"kind": "rival_outpaced", "id": r.id})
	if choices.size() >= s.db.get_all("agi_stages").size() and String(s.run["run_over"]) == "":
		var win := majority(choices)
		if int(counts(choices)[win]) == choices.size():
			stats["solo_%s" % win] = int(stats.get("solo_%s" % win, 0)) + 1
		var e = ending_for(s, win)
		s.run["run_over"] = e.id
		s.add_cur("legacy", BigNum.from_float(float(e.legacy_payout)))
		evs.append({"kind": "ending", "id": e.id})


# ---------------------------------------------------------------- rival race

## Rival `r` is in the race: its target stage has unlocked and it has neither launched nor been outpaced.
static func racing(s: GameState, r) -> bool:
	if int(s.run["stage"]) < int(r.outpace_stage):
		return false
	var flags: Dictionary = s.run["flags"]
	return not flags.get("rival_%s_launched" % r.id, false) and not flags.get("outpaced_%s" % r.id, false)


## Work per second of rival `id`: +RED_SPEED per red-team run (persistent), +RECK_RIVAL per Ship it this run,
## ×ACQUI_SPEED once acqui-hired.
static func rival_speed(s: GameState, id: String) -> float:
	var sp := (1.0 + RED_SPEED * float(int(s.persist.get("redteam_uses", 0)))) * (1.0 + RECK_RIVAL * float(reckless(s)))
	if id in s.run["race"]["acqui"]:
		sp *= ACQUI_SPEED
	return sp


## Race seconds rival `id` needs: base schedule × (1 + Outship delay), shortened by rival_progress (events).
static func launch_seconds(s: GameState, id: String) -> float:
	var r = s.db.get_def("rivals", id)
	var delay := float(s.run["race"]["delay"].get(id, 0.0))
	var progress := float(s.run["rivals"].get(id, 0.0))
	return float(r.launch_hours) * 3600.0 * (1.0 + delay) * maxf(0.1, 1.0 - progress)


static func race_progress(s: GameState, id: String) -> float:
	var work := float(s.run["race"]["work"].get(id, 0.0))
	return clampf(work / launch_seconds(s, id), 0.0, 1.0)


## Seconds until rival `id` launches at its current speed (INF when it is not racing).
static func race_eta(s: GameState, id: String) -> float:
	var r = s.db.get_def("rivals", id)
	if r == null or not racing(s, r):
		return INF
	var work := float(s.run["race"]["work"].get(id, 0.0))
	return maxf(launch_seconds(s, id) - work, 0.0) / rival_speed(s, id)


static func race_tick(s: GameState, dt: float, evs: Array) -> void:
	var work: Dictionary = s.run["race"]["work"]
	for r in s.db.get_all("rivals"):
		if not racing(s, r):
			continue
		var w := float(work.get(r.id, 0.0)) + dt * rival_speed(s, r.id)
		work[r.id] = w
		if w >= launch_seconds(s, r.id):
			s.run["flags"]["rival_%s_launched" % r.id] = true
			evs.append({"kind": "rival_launched", "id": r.id})


static func _race_cooldown(s: GameState, key: String) -> float:
	return float(s.run["race"]["cool"].get(key, 0.0))


## Why an Outship or Acqui-hire on rival `id` would fail, or "" when it would succeed.
static func race_blocker(s: GameState, id: String) -> String:
	var r = s.db.get_def("rivals", id)
	if r == null:
		return "unknown rival"
	if not racing(s, r):
		return "not in the race"
	return ""


## Delays rival `id` by OUTSHIP_GAIN of the missing share (capped at OUTSHIP_MAX), for compute that grows 4x each time.
static func outship(s: GameState, id: String) -> Dictionary:
	var reason := race_blocker(s, id)
	var race: Dictionary = s.run["race"]
	var delay := float(race["delay"].get(id, 0.0))
	var n := int(race["outships"].get(id, 0))
	var cost := BigNum.from_float(OUTSHIP_COST * pow(OUTSHIP_COST_GROWTH, n))
	if reason == "" and _race_cooldown(s, "outship:" + id) > 0.0:
		reason = "cooling down"
	if reason == "" and s.cur("compute").compare(cost) < 0:
		reason = "not enough compute"
	if reason != "":
		return _fail(reason)
	s.set_cur("compute", s.cur("compute").subtract(cost))
	race["delay"][id] = minf(OUTSHIP_MAX, delay + OUTSHIP_GAIN * (OUTSHIP_MAX - delay))
	race["outships"][id] = n + 1
	race["cool"]["outship:" + id] = OUTSHIP_COOLDOWN
	return {"ok": true, "cost": cost}


## Hires rival `id`'s lead researcher: cash (ACQUI_CASH_SECONDS of income), +1 researcher, rival slowed. Once per rival per run.
## ponytail: the researcher sits in layer 1 and goes with the next Singularity reset, like any hire.
static func acqui(s: GameState, id: String) -> Dictionary:
	var reason := race_blocker(s, id)
	var race: Dictionary = s.run["race"]
	if reason == "" and id in race["acqui"]:
		reason = "already acquired"
	if reason == "" and _race_cooldown(s, "acqui") > 0.0:
		reason = "cooling down"
	if reason != "":
		return _fail(reason)
	var gain := Sim.cash_per_second(s).mul_f(ACQUI_CASH_SECONDS)
	s.add_cur("cash", gain)
	for k in range(1, 5):
		s.run["layers"][k]["life"] = (s.run["layers"][k]["life"] as BigNum).add(gain)
	var staff: Dictionary = s.run["layers"][1]["staff"]
	staff["researcher"] = int(staff.get("researcher", 0)) + 1
	race["acqui"].append(id)
	race["cool"]["acqui"] = ACQUI_COOLDOWN
	return {"ok": true, "cash": gain}


# ---------------------------------------------------------------- challenge tiers

## Why challenge `id` is locked by its tier, or "" (tier N+1 needs tier N passed at least once, ever).
static func tier_blocker(s: GameState, id: String) -> String:
	var d = s.db.get_def("challenges", id)
	if d == null or d.requires == "":
		return ""
	if not (d.requires in s.persist["records"]["challenges"]):
		return "pass %s first" % s.db.get_def("challenges", d.requires).title
	return ""


## Records a challenge pass. Each challenge counts once in its tier (stats.tier_N) the first time it is passed.
static func challenge_won(s: GameState, d) -> void:
	if d.id in s.persist["records"]["challenges"]:
		return
	Records.note(s.persist, "challenges", d.id)
	var key := "tier_%d" % int(d.tier)
	s.persist["stats"][key] = int(s.persist["stats"].get(key, 0)) + 1


## A challenge reward as applied: perm_mult rewards are cut so the product of all of them stays under CHALLENGE_CAP.
static func challenge_effect(s: GameState, e: Dictionary) -> Dictionary:
	if e["type"] != "perm_mult":
		return e
	var cur := float(s.persist.get("challenge_mult", 1.0))
	var f := minf(float(e["value"]), CHALLENGE_CAP / cur)
	s.persist["challenge_mult"] = cur * f
	var out: Dictionary = e.duplicate()
	out["value"] = f
	return out


# ---------------------------------------------------------------- recklessness (bad events)

## Ship it choices this run: more and worse bad events.
static func reckless(s: GameState) -> int:
	return int(counts(s.run["agi_choices"])["ship"])


## Pool weight of an event. Recklessness does not make events likelier: it makes their costs harsher (see event_effect).
static func event_weight(_s: GameState, d) -> float:
	return float(d.weight)


## An event effect as applied: bad events' alignment and reputation losses are scaled by severity. Extra alignment
## loss stops at the slider value where debt starts, so recklessness cannot add a production penalty.
static func event_effect(s: GameState, d, e: Dictionary) -> Dictionary:
	var n := reckless(s)
	if n == 0 or not BAD_CATEGORIES.has(d.category):
		return e
	var sev := 1.0 + RECK_SEVERITY * float(n)
	var v := float(e.get("value", 0.0))
	var out: Dictionary = e.duplicate()
	var reputation: bool = e["type"] == "add_currency" and e.get("id", "") == RECK_CURRENCY
	if e["type"] == "add_slider" and v < 0.0:
		out["value"] = maxf(v * sev, Sim.SLIDER_SAFE - float(s.run["slider"]))
	elif reputation and v < 0.0:
		out["value"] = v * sev
	return out
