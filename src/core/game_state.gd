class_name GameState
extends RefCounted
## All game state. `persist` survives every reset and new run; `run` is what resets wipe.
## run.layers[0] = base run (cash, compute, producers). run.layers[1..4] = funding, generation,
## paradigm, singularity. Reset k keeps currency k, wipes layers 0..k-1, and zeroes layer k's life/clock.

const CURRENCY_LAYER := {
	"cash": 0, "compute": 0, "equity": 1, "insights": 2,
	"breakthroughs": 3, "data": 3, "energy": 3, "legacy": 4,
}
## Cash granted at the start of every run and after every reset, so the first producer is affordable.
const START_CASH := 20.0

var db                  # Content autoload (get_all / get_def); untyped so core stays scene-free
var rng: RandomNumberGenerator
var persist: Dictionary
var run: Dictionary


func _init(content_db = null, seed_value: int = 1) -> void:
	db = content_db
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	persist = {
		"eval_seed": seed_value,  # seeds each Endgame eval roll's own stream (see Endgame._finish_eval)
		"perm_mult": {}, "legacy_perks": {}, "automation": [], "benchmarks": [],
		"best_all": 0.0,
		"stats": {"runs": 1, "resets": 0, "time": 0.0, "trainings": 0, "failed": 0, "events": 0, "launches": 0, "news": 0, "moonshots": 0,
				"upgrades": 0, "evals_passed": 0, "evals_failed": 0, "ships": 0, "solo_full": 0, "solo_redteam": 0, "solo_ship": 0, "tier_1": 0, "tier_2": 0, "tier_3": 0},
			"redteam_uses": 0,       # community red-team runs so far: each adds RED_SPEED to rival speed (see Endgame)
			"challenge_mult": 1.0,   # product of permanent challenge rewards, capped at Endgame.CHALLENGE_CAP
		"moonshots": {"running": [], "done": []},  # see Moonshots: survives every reset
		"lifetime_resets": [0, 0, 0, 0],
		"settings": {"reduce_motion": false, "notation": "suffix"},
		"intro_seen": false,
		"saved_at": 0.0,
		"records": Records.default(0.0),   # see Records; a v3 save gets one from SaveSystem._v3_to_v4
		"seen_reveals": {},                # reveal id -> true once its "New: ..." card has been shown
		"reveals_seeded": false,           # Reveals.seed has run (see Game.start)
	}
	run = fresh_run()


static func fresh_run() -> Dictionary:
	var layers: Array = []
	for i in 5:
		layers.append(fresh_layer())
	layers[0]["cur"]["cash"] = BigNum.from_float(START_CASH)
	return {
		"layers": layers, "resets_done": [0, 0, 0, 0], "stage": 0, "slider": 0.5,
		"peak_compute_rate": 0.0, "agi_peaks": {"owned": {}, "energy": 0.0, "training_best": 0.0},
		"flags": {}, "rivals": {}, "challenges_done": [], "challenge_passed": {}, "run_over": "",
		"launches": {}, "news": {"timer": News.FIRST_SECONDS, "chip": {}},
		"agi_choices": [],     # one method per cleared AGI stage (see Endgame)
		"eval": {},            # running evaluation: {method, index, left}
		"eval_cooldown": 0.0,  # seconds until the full eval suite can run again
		"race": {"work": {}, "delay": {}, "outships": {}, "cool": {}, "acqui": []},  # rival race (see Endgame)
	}


static func fresh_layer() -> Dictionary:
	return {
		"cur": {}, "life": BigNum.new(), "clock": 0.0,
		"owned": {}, "staff": {}, "research": [],
		"best": 0.0, "debt": 0.0, "run_mult": {}, "timed": [],
		"training": {}, "cooldowns": {}, "pending": "", "event_timer": 90.0,
		"challenge": {}, "upgrades": [], "desk": {"slots": [], "timer": 1200.0, "bonus": 0.0},
	}


func cur(name: String) -> BigNum:
	var k: int = CURRENCY_LAYER.get(name, -1)
	if k < 0:
		push_error("Unknown currency: " + name)
		return BigNum.new()
	return run["layers"][k]["cur"].get(name, BigNum.new()).copy()


func set_cur(name: String, v: BigNum) -> void:
	var k: int = CURRENCY_LAYER.get(name, -1)
	if k < 0:
		push_error("Unknown currency: " + name)
		return
	run["layers"][k]["cur"][name] = BigNum.new() if v.compare(BigNum.new()) < 0 else v


func add_cur(name: String, v: BigNum) -> void:
	set_cur(name, cur(name).add(v))


func owned(id: String) -> int:
	return int(run["layers"][0]["owned"].get(id, 0))


## Number of resets of layer k (1..4) done this run.
func resets(k: int) -> int:
	if k < 1 or k > 4:
		return 0
	return int(run["resets_done"][k - 1])


## ---- Serialization (BigNum -> {mantissa, exponent}; RNG state as string to keep 64 bits) ----

func to_dict() -> Dictionary:
	Endgame.track_peaks(self)
	var layers_out: Array = []
	for L in run["layers"]:
		var o: Dictionary = L.duplicate(false)
		var cur_out := {}
		for k in L["cur"]:
			cur_out[k] = L["cur"][k].to_json()
		o["cur"] = cur_out
		o["life"] = L["life"].to_json()
		layers_out.append(o)
	var r: Dictionary = run.duplicate(false)
	r["layers"] = layers_out
	return {"persist": persist.duplicate(true), "run": r, "rng": str(rng.state)}


## Rebuilds a state from to_dict() output. Keys missing from an older or partial save are filled from a fresh
## state (see _fill); a save with no intro flag counts as seen, and a save with no lifetime counter gets this run's resets.
static func from_dict(content_db, d: Dictionary) -> GameState:
	var s := GameState.new(content_db, 1)
	var t := _template(content_db)
	var data := d.duplicate(true)
	_fill(data, t)
	_fill(data["run"], t["run"])
	var persist: Dictionary = data["persist"]
	for k in ["stats", "settings"]:  # structs: a partial one is completed key by key, never replaced wholesale
		if not (persist.get(k) is Dictionary):
			persist[k] = t["persist"][k].duplicate(true)
		_fill(persist[k], t["persist"][k])
	_fill(persist, t["persist"])
	s.persist = persist
	s.run = data["run"]
	if not s.persist.has("lifetime_resets"):  # saves older than the counter: this run's resets are the best guess
		s.persist["lifetime_resets"] = s.run["resets_done"].duplicate()
	s.rng.state = String(data["rng"]).to_int()
	var tmpl_layers: Array = t["run"]["layers"]
	var layers: Array = s.run.get("layers", [])
	while layers.size() < tmpl_layers.size():
		layers.append(tmpl_layers[layers.size()].duplicate(true))
	for i in layers.size():
		var o: Dictionary = layers[i]
		if not o.has("cur"):  # starting cash lives in the template: a save without cur gets none
			o["cur"] = {}
		if i < tmpl_layers.size():
			_fill(o, tmpl_layers[i])
	var out_layers: Array = []
	for L in layers:
		var cur_in := {}
		for k in L["cur"]:
			cur_in[k] = BigNum.from_json(L["cur"][k])
		L["cur"] = cur_in
		L["life"] = BigNum.from_json(L["life"])
		out_layers.append(L)
	s.run["layers"] = out_layers
	s._normalize_ints()
	Endgame.track_peaks(s)
	return s


## A fresh state in to_dict() form: the defaults for every key a save may lack. The intro flag defaults to seen
## (a save without it was played before the intro existed) and the lifetime counter is left out so from_dict backfills it.
static func _template(content_db) -> Dictionary:
	var t := GameState.new(content_db, 1).to_dict()
	t["persist"]["intro_seen"] = true
	t["persist"].erase("lifetime_resets")
	return t


## Copies each key that `saved` lacks from `tmpl` (maps and arrays are copied, never shared with the template).
static func _fill(saved: Dictionary, tmpl: Dictionary) -> void:
	for k in tmpl:
		if not saved.has(k):
			saved[k] = tmpl[k].duplicate(true) if (tmpl[k] is Dictionary or tmpl[k] is Array) else tmpl[k]


## JSON gives every number back as float; restore the fields that are integers.
func _normalize_ints() -> void:
	persist["eval_seed"] = int(persist.get("eval_seed", 1))
	run["stage"] = int(run["stage"])
	for i in run["resets_done"].size():
		run["resets_done"][i] = int(run["resets_done"][i])
	for L in run["layers"]:
		for id in L["owned"]:
			L["owned"][id] = int(L["owned"][id])
		for role in L["staff"]:
			L["staff"][role] = int(L["staff"][role])
	for key in persist["stats"]:
		if key != "time":
			persist["stats"][key] = int(persist["stats"][key])
	for key in persist["legacy_perks"]:
		persist["legacy_perks"][key] = int(persist["legacy_perks"][key])
	for i in persist["lifetime_resets"].size():
		persist["lifetime_resets"][i] = int(persist["lifetime_resets"][i])
	persist["records"]["agi_best"] = int(persist["records"]["agi_best"])
	persist["redteam_uses"] = int(persist["redteam_uses"])
