extends SceneTree
## Training balance table: expected compute-bonus gain per minute for each run type at three game stages.
##
##   $GODOT --headless --path . -s tools/training_balance.gd
##
## One run is worth (1 - fail chance) x mean over the score roll of [bonus(max(best, score)) - bonus(best)], divided
## by the run's minutes and shown as a percent of the current compute bonus. A stage is a snapshot: compute stock
## (log10), training multiplier and generation best. Only the best counts, so a run that does not beat it is worth 0.
## Exits 1 if no run type is the best pick at any stage (one type dominating everywhere).

const STAGES := [
	{"name": "first hour, B=0", "stock_log": 3.0, "train": 1.0, "best": 0.0},
	{"name": "to Generation", "stock_log": 5.0, "train": 2.0, "best": 6.0},
	{"name": "late, best set earlier", "stock_log": 7.0, "train": 2.0, "best": 14.0},
]
const ROLL_STEPS := 5


func _initialize() -> void:
	var content = load("res://src/autoload/content.gd").new()
	content.load_all()
	var runs: Array = content.get_all("training_runs")
	var header := "%-24s" % "stage"
	for d in runs:
		header += " %12s" % d.id
	print(header + "   best")
	var winners := {}
	for st in STAGES:
		var best: float = st["best"]
		var row := "%-24s" % st["name"]
		var top := ""
		var top_val := -INF
		for d in runs:
			var v := _gain_per_minute(d, st, best)
			row += " %11.2f%%" % v
			if v > top_val:
				top_val = v
				top = d.id
		winners[top] = true
		print(row + "   %s" % top)
	var ok := winners.size() == runs.size()
	print("every run type is the best pick at some stage: %s" % ("yes" if ok else "NO"))
	quit(0 if ok else 1)


## Expected percent gain of the compute bonus per minute for one run of type `d` at stage `st`.
func _gain_per_minute(d, st: Dictionary, best: float) -> float:
	var stock_log: float = st["stock_log"]
	var spend_log := stock_log + log(float(d.spend_share)) / log(10.0)
	var predicted := spend_log * float(st["train"]) * float(d.score_mult)
	var now := Rules.training_bonus_for(best, best)
	var mean := 0.0
	for i in ROLL_STEPS:
		var roll := lerpf(1.0 - Sim.SCORE_ROLL, 1.0 + Sim.SCORE_ROLL, float(i) / float(ROLL_STEPS - 1))
		var score := predicted * roll
		mean += Rules.training_bonus_for(maxf(best, score), maxf(best, score)) - now
	mean /= float(ROLL_STEPS)
	var survive := 1.0 - float(d.fail_chance)
	return survive * mean / now * 100.0 / (float(d.seconds) / 60.0)
