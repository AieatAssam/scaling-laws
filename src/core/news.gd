class_name News
extends RefCounted
## Breaking news: a chip shows for CHIP_SECONDS at random (gap = MIN_GAP + exponential, mean ~4 min). Tapping it
## claims one reward; missing it costs nothing. The chip and the timer live in run["news"]; catches count in the
## persistent stat stats.news. Randomness uses the seeded state RNG, and only when a headline is picked.

const CHIP_SECONDS := 15.0
const FIRST_SECONDS := 150.0   # timer at the start of a run (fixed, so the first draw is not special)
const MIN_GAP := 90.0
const MEAN_EXTRA := 150.0      # gap = MIN_GAP + exponential(MEAN_EXTRA): mean 240 s
const REWARD_MIN := 30.0       # cash / compute rewards: seconds of current income
const REWARD_MAX := 90.0
const DOUBLE_MULT := 2.0
const DOUBLE_SECONDS := 30.0
const VIRAL_MULT := 7.0
const VIRAL_SECONDS := 15.0


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Advances the chip and the timer. `hold` (offline, or a modal is open) clears the chip and freezes the timer:
## a headline never spawns while the player cannot see the lab, and nothing is missed for free.
static func tick(s: GameState, dt: float, evs: Array, hold: bool) -> void:
	var n: Dictionary = s.run["news"]
	if hold:
		n["chip"] = {}
		return
	var chip: Dictionary = n["chip"]
	if not chip.is_empty():
		chip["left"] = float(chip["left"]) - dt
		if float(chip["left"]) <= 0.0:
			n["chip"] = {}
	n["timer"] = float(n["timer"]) - dt
	if float(n["timer"]) > 0.0 or not (n["chip"] as Dictionary).is_empty():
		return
	if Sim.compute_per_second(s).is_zero():  # rewards are priced in income: none before the first producer
		return
	var id := _pick(s)
	n["chip"] = {"id": id, "left": CHIP_SECONDS}
	n["timer"] = MIN_GAP - MEAN_EXTRA * log(1.0 - s.rng.randf())
	evs.append({"kind": "news", "id": id})


## Weighted random headline.
static func _pick(s: GameState) -> String:
	var pool: Array = s.db.get_all("news")
	var total := 0.0
	for d in pool:
		total += float(d.weight)
	var r := s.rng.randf() * total
	for d in pool:
		r -= float(d.weight)
		if r < 0.0:
			return d.id
	return pool.back().id


## Claims the chip. Returns {ok, id, title, reward, amount (cash/compute), seconds (timed boosts and income)}.
static func catch(s: GameState) -> Dictionary:
	var chip: Dictionary = s.run["news"]["chip"]
	if chip.is_empty():
		return _fail("no breaking news")
	var d = s.db.get_def("news", chip["id"])
	s.run["news"]["chip"] = {}
	var out := {"ok": true, "id": d.id, "title": d.title, "reward": d.reward}
	match d.reward:
		"cash":
			var sec := s.rng.randf_range(REWARD_MIN, REWARD_MAX)
			var cash := Sim.cash_per_second(s).mul_f(sec)
			s.add_cur("cash", cash)
			_add_life(s, cash)
			out["amount"] = cash
			out["seconds"] = sec
		"compute":
			var sec := s.rng.randf_range(REWARD_MIN, REWARD_MAX)
			var compute := Sim.compute_per_second(s).mul_f(sec)
			s.add_cur("compute", compute)
			out["amount"] = compute
			out["seconds"] = sec
		"double_cash":
			Rules.apply(s, {"type": "timed_mod", "key": "cash", "value": DOUBLE_MULT, "seconds": DOUBLE_SECONDS})
			out["seconds"] = DOUBLE_SECONDS
		"viral":
			Rules.apply(s, {"type": "timed_mod", "key": "cash", "value": VIRAL_MULT, "seconds": VIRAL_SECONDS})
			out["seconds"] = VIRAL_SECONDS
	s.persist["stats"]["news"] = int(s.persist["stats"].get("news", 0)) + 1
	return out


## Income paid out counts toward every reset layer's lifetime, as income does (see Sim.tick).
static func _add_life(s: GameState, amount: BigNum) -> void:
	for k in range(1, 5):
		s.run["layers"][k]["life"] = (s.run["layers"][k]["life"] as BigNum).add(amount)
