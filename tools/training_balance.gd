extends SceneTree
## Training balance: the three run types compared in each game phase and Ops count, and the pick shares of a
## whole-game simulation. Phases are the window medians tools/simulate.gd prints as "training picks by game window"
## (seed 1, aligned). For each phase and Ops count a state is built (compute stock, training multiplier, generation
## best, best ever = generation best, Ops staff), and each run type is priced with Sim.training_preview:
##   score = survive x predicted score   (expected score a run adds to the best)
##   cash  = survive x revenue_seconds / seconds   (cash burst per run second, as a fraction of base cash income)
## survive = 1 - fail chance, with Ops applied. The pick column is Sim.pick_training, the rule auto-train uses.
##
## Gates (exit 1 on any failure):
##   a. fine_tune has the most cash per minute, in every row
##   b. frontier has the highest expected score, in every row
##   c. standard sits strictly between fine_tune and frontier on both axes, in every row
##   d. whole-game pick shares at seed 1 (tools/simulate.gd, aligned, 336 h): fine_tune >= 10%, frontier >= 10%,
##      standard >= 5%. The simulator's PICKS line is the source.
##
##   $GODOT --headless --path . -s tools/training_balance.gd

const PHASES := [
	{"name": "early", "stock_log": 4.6, "train": 1.01, "best": 4.6},
	{"name": "mid", "stock_log": 4.9, "train": 2.56, "best": 24.5},
	{"name": "late", "stock_log": 4.4, "train": 3.03, "best": 21.4},
]
const OPS := [0, 3, 8]
const SEED := 1
const FINE := "fine_tune"
const STANDARD := "standard"
const FRONTIER := "frontier"
const FINE_SHARE_MIN := 0.10
const FRONTIER_SHARE_MIN := 0.10
const STANDARD_SHARE_MIN := 0.05


func _initialize() -> void:
	var content = load("res://src/autoload/content.gd").new()
	content.load_all()
	var runs: Array = content.get_all("training_runs")
	runs.sort_custom(func(a, b) -> bool: return a.order < b.order)
	var ok := true
	var header := "%-6s %4s" % ["phase", "ops"]
	for d in runs:
		header += " | %-10s %6s" % [d.id, "cash"]
	print(header + " | pick")
	for ph in PHASES:
		for n in OPS:
			var s := _state(content, ph, n)
			var vals := {}
			var row := "%-6s %4d" % [ph["name"], n]
			for d in runs:
				var p := Sim.training_preview(s, d.id)
				var survive := 1.0 - float(p["fail_chance"])
				vals[d.id] = {
					"score": survive * float(p["predicted_score"]),
					"cash": survive * float(d.revenue_seconds) / float(d.seconds),
				}
				row += " | %-10.2f %5.1f%%" % [float(vals[d.id]["score"]), float(vals[d.id]["cash"]) * 100.0]
			print(row + " | " + Sim.pick_training(s))
			ok = _check_row(vals, ph["name"], n) and ok
	var shares := _seed_shares()
	if shares.is_empty():
		printerr("CHECK FAILED: could not read the PICKS line from tools/simulate.gd (seed %d)" % SEED)
		ok = false
	else:
		var counts: Dictionary = shares["counts"]
		var frac: Dictionary = shares["shares"]
		print("pick shares, seed %d whole game: %s %.0f%% (%d), %s %.0f%% (%d), %s %.0f%% (%d)" % [
			SEED, FINE, float(frac[FINE]) * 100.0, int(counts[FINE]),
			STANDARD, float(frac[STANDARD]) * 100.0, int(counts[STANDARD]),
			FRONTIER, float(frac[FRONTIER]) * 100.0, int(counts[FRONTIER])])
		if float(frac[FINE]) < FINE_SHARE_MIN or float(frac[FRONTIER]) < FRONTIER_SHARE_MIN or float(frac[STANDARD]) < STANDARD_SHARE_MIN:
			printerr("CHECK FAILED: pick shares outside fine_tune >= 10%, frontier >= 10%, standard >= 5%")
			ok = false
	print("training balance: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## The state a phase stands for, with n Ops staff.
func _state(content, ph: Dictionary, n: int) -> GameState:
	var s := GameState.new(content, 1)
	s.set_cur("compute", BigNum.from_float(pow(10.0, float(ph["stock_log"]))))
	s.run["layers"][0]["run_mult"]["training"] = float(ph["train"])
	s.run["layers"][2]["best"] = float(ph["best"])
	s.persist["best_all"] = float(ph["best"])
	s.run["layers"][1]["staff"]["ops"] = n
	return s


## Gates a-c on one row. Prints the failures.
func _check_row(vals: Dictionary, phase: String, n: int) -> bool:
	var fine: Dictionary = vals[FINE]
	var std: Dictionary = vals[STANDARD]
	var fr: Dictionary = vals[FRONTIER]
	var row_ok := true
	if float(fine["cash"]) <= float(std["cash"]) or float(fine["cash"]) <= float(fr["cash"]):
		printerr("CHECK FAILED (a): %s with %d Ops: fine_tune is not the best cash per minute" % [phase, n])
		row_ok = false
	if float(fr["score"]) <= float(std["score"]) or float(fr["score"]) <= float(fine["score"]):
		printerr("CHECK FAILED (b): %s with %d Ops: frontier is not the highest expected score" % [phase, n])
		row_ok = false
	var between_score := float(fine["score"]) < float(std["score"]) and float(std["score"]) < float(fr["score"])
	var between_cash := float(fr["cash"]) < float(std["cash"]) and float(std["cash"]) < float(fine["cash"])
	if not (between_score and between_cash):
		printerr("CHECK FAILED (c): %s with %d Ops: standard is not strictly between fine_tune and frontier" % [phase, n])
		row_ok = false
	return row_ok


## Whole-game pick counts and shares from a seed-1 simulation (its PICKS line), or {} when it is missing.
func _seed_shares() -> Dictionary:
	var out: Array = []
	OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/simulate.gd", "--",
		"--hours=336", "--seed=%d" % SEED, "--ending=aligned"]), out, false)
	var line := ""
	for l in "\n".join(out).split("\n"):
		if l.begins_with("PICKS "):
			line = l
	if line == "":
		return {}
	var counts := {}
	var total := 0
	for tok in line.substr(6).split(" "):
		var kv := tok.split("=")
		counts[kv[0]] = int(kv[1])
		total += int(kv[1])
	var shares := {}
	for id in counts:
		shares[id] = float(counts[id]) / float(maxi(total, 1))
	return {"counts": counts, "shares": shares}
