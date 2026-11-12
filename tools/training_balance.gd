extends SceneTree
## Training balance: which run type the simulator's own pick rule (tools/simulate.gd, _training) chooses in each game
## phase, per Ops count, with the value it compares.
##
##   $GODOT --headless --path . -s tools/training_balance.gd
##
## Phases are the simulator's pick states: tools/simulate.gd prints "training picks by game window" (seed 1, aligned);
## log10 stock, training multiplier and generation best are the window medians.
## For each run type: pred = (log10 stock + log10 spend share) x training multiplier x score_mult,
## survive = 1 - fail chance (Ops applied), per_min = 60 / seconds.
##   gain = survive x max(0, pred - best) x per_min   (score gained per run minute over the current best)
##   raw  = survive x pred x per_min                  (used only when no run beats the best, as in the simulator)
## The pick is the highest gain, or the highest raw when every gain is 0 (the table says which rule applied).
##
## Gate (exit 1 on violation):
##   - WANT: each (phase, Ops) pick is the expected one by MARGIN over the runner-up.
##   - every run type is the pick in at least one phase and Ops count.

const PHASES := [
	{"name": "early", "stock_log": 4.5, "train": 1.01, "best": 6.7},
	{"name": "mid", "stock_log": 5.0, "train": 2.56, "best": 24.0},
	{"name": "late", "stock_log": 4.4, "train": 3.03, "best": 23.3},
]
const OPS := [0, 3, 8]
const MARGIN := 0.15
## Which run type must be the pick in which phase, at which Ops count.
const WANT := [
	{"phase": "early", "ops": 0, "id": "fine_tune"},
	{"phase": "mid", "ops": 0, "id": "standard"},
	{"phase": "late", "ops": 0, "id": "frontier"},
	{"phase": "late", "ops": 8, "id": "frontier"},
]


func _initialize() -> void:
	var content = load("res://src/autoload/content.gd").new()
	content.load_all()
	var runs: Array = content.get_all("training_runs")
	var header := "%-6s %4s" % ["phase", "ops"]
	for d in runs:
		header += " %12s" % d.id
	print(header + "   pick       rule    margin over runner-up")
	var table := {}     # "phase/ops" -> {id: value}
	var winners := {}
	for ph in PHASES:
		for n in OPS:
			var any_gain := false
			var parts := {}
			for d in runs:
				parts[d.id] = _values(content, d, ph, n)
				any_gain = any_gain or float(parts[d.id]["gain"]) > 0.0
			var key := "gain" if any_gain else "raw"
			var vals := {}
			for id in parts:
				vals[id] = parts[id][key]
			table["%s/%d" % [ph["name"], n]] = vals
			var ranked := _ranked(vals)
			var top: String = ranked[0]
			winners[top] = true
			var margin := "inf" if float(vals[ranked[1]]) <= 0.0 else \
				"%.0f%%" % ((float(vals[top]) / float(vals[ranked[1]]) - 1.0) * 100.0)
			var row := "%-6s %4d" % [ph["name"], n]
			for d in runs:
				row += " %12.4f" % float(vals[d.id])
			print(row + "   %-10s %-5s  %s" % [top, key, margin])
	var ok := true
	for w in WANT:
		var vals: Dictionary = table["%s/%d" % [w["phase"], w["ops"]]]
		var ranked := _ranked(vals)
		if ranked[0] != w["id"] or not _margin_ok(vals, ranked):
			ok = false
			printerr("CHECK FAILED: %s with %d Ops: %s is not the pick by %d%% (ranking %s)" % [
				w["phase"], w["ops"], w["id"], int(MARGIN * 100.0), ", ".join(ranked)])
	for d in runs:
		if not winners.has(d.id):
			ok = false
			printerr("CHECK FAILED: %s is the pick nowhere" % d.id)
	print("picks as wanted by %d%%, every run type picked somewhere: %s" % [int(MARGIN * 100.0), "yes" if ok else "NO"])
	quit(0 if ok else 1)


## Run type ids sorted by value, best first.
func _ranked(vals: Dictionary) -> Array:
	var ids := vals.keys()
	ids.sort_custom(func(a, b): return float(vals[a]) > float(vals[b]))
	return ids


func _margin_ok(vals: Dictionary, ranked: Array) -> bool:
	var runner := float(vals[ranked[1]])
	return runner <= 0.0 or float(vals[ranked[0]]) >= runner * (1.0 + MARGIN)


## Fail chance composed with n Ops, using the real staff formula.
func _fail_chance(content, d, n: int) -> float:
	var s := GameState.new(content, 1)
	s.run["layers"][1]["staff"]["ops"] = n
	return float(d.fail_chance) * Sim.training_fail_factor(s)


## gain and raw value (score units per minute) of run type d in phase ph with n Ops; see the header.
func _values(content, d, ph: Dictionary, n: int) -> Dictionary:
	var survive := 1.0 - _fail_chance(content, d, n)
	var best := float(ph["best"])
	var pred := (float(ph["stock_log"]) + log(float(d.spend_share)) / log(10.0)) * float(ph["train"]) * float(d.score_mult)
	var per_min := 60.0 / float(d.seconds)
	return {"gain": survive * maxf(0.0, pred - best) * per_min, "raw": survive * pred * per_min}
