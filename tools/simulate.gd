extends SceneTree
## Headless pacing simulator. It plays the real core (Sim / Rules / GameState) with a scripted strategy.
##
##   $GODOT --headless --path . -s tools/simulate.gd -- --hours=336 --seed=1 [--ending=aligned|rushed|open_sourced] [--lazy] [--verbose]
##
## Prints an unlock timeline and a pacing report. Exits 1 with "CHECK FAILED: ..." lines when a check fails.
## Times are game hours from the start of the run. The strategy: best-payback producers, staff, research on one
## architecture branch (seed % 3), training at the best expected score, events by a simple score, slider set for the
## target ending, automation, legacy, challenges. A layer is reset when it is highlighted (gain >= 2 and >= 2x its
## holding), or when its gain is >= 1 and has stopped rising for STALL_FACTOR times as long as it took to reach it.
## The strategy reads only economy state; LayerDef.target_hours is printed as the design target, nothing more.
##
## Gating checks:
##   First reset of each layer (game time):  Funding 20–45 min, Generation 3–6 h, Paradigm 24–48 h,
##     Singularity 3–8 d.  The AGI ending must come within 14 d (336 h).
##   Cycles: a layer's cycle runs from its life being zeroed (own reset or a higher one) to its own reset.
##     Within an epoch (no higher reset), the average of cycles 2.. must be at most CYCLE_SPEEDUP of the first (plus one
##     step), when the first is longer than two steps. Averaging keeps single-step jitter from failing the check.
##   Unlock gaps: an unlock is a first producer tier, staff role, research node, automation, benchmark, constraint,
##     rival, challenge, AGI stage, ending, first training, or first reset of a layer. Events are not unlocks.
##     A gap is limited by where it starts: 10 min before 1 h, 30 min before Generation, 3 h before Paradigm, 8 h after.
##   Stall: no state-changing action for more than 2 h. No NaN, inf or negative resources.
##   Training failure rate: 5–50% (when there are at least 10 runs).
## --lazy (half-efficiency: no training, acts every 10 min) is reported only, not gated.

const HOUR := 3600.0
const DAY := 86400.0
const MAX_DT := 120.0
const MIN_DT := 30.0
const TRACE_EVERY := 12.0 * HOUR
const LAZY_STEP := 600.0
const LIMIT_HOURS := 336.0
const BANDS := [[0.0, 0.0], [1.0 / 3.0, 0.75], [3.0, 6.0], [24.0, 48.0], [72.0, 192.0]]   # hours, by layer index
const GAP_LIMITS := [600.0, 1800.0, 10800.0, 28800.0]   # by gap start: <1 h, <Generation, <Paradigm, after
const STALL_LIMIT := 7200.0
const STALL_FACTOR := 4.0      # gain stalled when it has not risen for this many times the time it took to reach it
const CYCLE_SPEEDUP := 0.9    # epoch 0: cycles 2.. must be at most this fraction of cycle 1
const LATER_EPOCH_MAX := 1.25 # epochs > 0: cycles 2.. must be at most this multiple of their first cycle (no slowdown)
const ENDING_EARLIEST := 192.0 * HOUR   # 8 d: the AGI ending must not come sooner
const SLIDER_TARGET := {"aligned": 0.9, "rushed": 0.3, "open_sourced": 0.5}
const RESEARCH_COMMON := ["cluster_scheduler", "data_curation", "data_dedupe", "eval_harness", "mixed_precision", "inference_cache"]
const RESEARCH_BRANCH := {
	"dense": ["dense_base", "dense_wide", "dense_deep", "dense_rlhf", "dense_scale"],
	"moe": ["moe_base", "moe_router", "moe_experts", "moe_sparse_train", "moe_scale"],
	"ssm": ["ssm_base", "ssm_state", "ssm_long", "ssm_hybrid", "ssm_scale"],
}
const STAFF_ROLES := ["engineer", "ops", "researcher"]
const LAYER_NAMES := ["", "Funding Round", "Model Generation", "Paradigm Shift", "Singularity"]

var s: GameState
var content
var seed_value := 1
var hours := LIMIT_HOURS
var ending_target := "aligned"
var lazy := false
var verbose := false
var branch := "dense"

var unlocks: Array = []                  # [time, label], first time each unlock happens (for display)
var actions: Array = [0.0]               # times of every state-changing action (buy, hire, do, reset, benchmark...)
var seen: Dictionary = {}                # unlock keys already recorded
var first_reset: Array = [-1.0, -1.0, -1.0, -1.0, -1.0]
var first_gain1: Array = [-1.0, -1.0, -1.0, -1.0, -1.0]   # first time gain >= 1 (ignores prerequisites)
var first_gain2: Array = [-1.0, -1.0, -1.0, -1.0, -1.0]   # first time gain >= 2
var gain_at_reset: Array = [0, 0, 0, 0, 0]
var cycle_start: Array = [0.0, 0.0, 0.0, 0.0, 0.0]        # time the layer's life was last zeroed
var last_gain: Array = [0, 0, 0, 0, 0]                    # gain seen in the current cycle
var last_up: Array = [0.0, 0.0, 0.0, 0.0, 0.0]            # time that gain last rose in the current cycle
var cycles: Array = [[], [], [], [], []]                  # [length s, epoch, end time] per own reset
var last_sig := -1
var last_action := 0.0
var max_idle := 0.0
var problems: Array = []
var bad_values := 0
var ending_id := ""
var ending_t := -1.0
var lazy_step_count := 0
var peak_rate: Array = []                              # highest compute/s seen in each game day
var next_trace := 0.0


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	content = load("res://src/autoload/content.gd").new()
	content.load_all()
	s = GameState.new(content, seed_value)
	branch = ["dense", "moe", "ssm"][absi(seed_value) % 3]
	_run()
	quit(_report())


func _parse_args() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hours="):
			hours = float(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--ending="):
			ending_target = a.get_slice("=", 1)
		elif a == "--lazy":
			lazy = true
		elif a == "--verbose":
			verbose = true
		else:
			print("unknown argument: " + a)
			return false
	if not SLIDER_TARGET.has(ending_target):
		print("--ending must be aligned, rushed or open_sourced")
		return false
	return true


func now() -> float:
	return float(s.persist["stats"]["time"])


func _fmt(t: float) -> String:
	if t < DAY:
		return "%6.2f h" % (t / HOUR)
	return "%6.2f d" % (t / DAY)


func _opt_time(t: float) -> String:
	return ("%.2f h" % (t / HOUR)) if t >= 0.0 else "  never"


func _cyc(sec: float) -> String:
	return "%8.3f h" % (sec / HOUR)


func _say(msg: String) -> void:
	print(msg)


func _log(msg: String) -> void:
	if verbose:
		print("      %s  %s" % [_fmt(now()), msg])


func _unlock(label: String, key: String = "") -> void:
	if key != "":
		if seen.has(key):
			return
		seen[key] = true
	var t := now()
	unlocks.append([t, label])
	_say("  %s  UNLOCK  %s" % [_fmt(t), label])


func _problem(msg: String) -> void:
	problems.append(msg)


# ---------------------------------------------------------------- main loop

func _run() -> void:
	var t_end := hours * HOUR
	var steps := 0
	while now() < t_end and s.run["run_over"] == "" and steps < 2000000:
		steps += 1
		_policy()
		_observe()
		if s.run["run_over"] != "":
			break
		_handle(Sim.tick(s, _next_dt()))
	_observe()


## Next step: the time until the cheapest next purchase or the next layer threshold becomes affordable, capped.
func _next_dt() -> float:
	if lazy:
		return LAZY_STEP
	var dt := MAX_DT
	var rate := Sim.cash_per_second(s).to_float()
	if rate > 0.0:
		var cash := s.cur("cash").to_float()
		for d in content.get_all("producers"):
			if Sim.producer_available(s, d.id):
				var need := Sim.cost_for(s, d.id, 1).to_float() - cash
				if need > 0.0:
					dt = minf(dt, need / rate)
		for k in range(1, 5):
			var ld = Sim.layer_def(s, k)
			var need_life := float(ld.threshold) - (s.run["layers"][k]["life"] as BigNum).to_float()
			if need_life > 0.0:
				dt = minf(dt, need_life / rate)
	var training: Dictionary = s.run["layers"][0]["training"]
	if not training.is_empty():
		dt = minf(dt, float(training["left"]))
	return clampf(dt, MIN_DT, MAX_DT)


# ---------------------------------------------------------------- strategy

func _policy() -> void:
	_track_gains()
	_resolve_event()
	_buy_producers()
	_hire()
	_research()
	_automation()
	_training()
	_slider()
	_legacy()
	_challenge()
	_resets()


func _buy_producers() -> void:
	while true:
		var id := Sim.best_producer(s)
		var n := Sim.max_affordable(s, id) if id != "" else 0
		if n == 0:
			return
		if not Sim.buy_producer(s, id, n)["ok"]:
			return
		_log("buy %d x %s" % [n, id])


func _hire() -> void:
	if lazy or s.resets(1) == 0:
		return
	var more := true
	while more:
		more = false
		var roles := STAFF_ROLES.duplicate()
		roles.sort_custom(func(a, b): return _staff_count(a) < _staff_count(b))
		for role in roles:
			if Sim.hire(s, role, 1)["ok"]:
				_log("hire %s" % role)
				more = true
				break


func _staff_count(role: String) -> int:
	return int(s.run["layers"][1]["staff"].get(role, 0))


func _research() -> void:
	if s.resets(2) == 0:
		return
	var prio: Array = RESEARCH_COMMON + RESEARCH_BRANCH[branch]
	var more := true
	while more:
		more = false
		for id in prio:
			if Sim.research(s, id)["ok"]:
				_log("research %s" % id)
				more = true
				break


func _automation() -> void:
	var more := true
	while more:
		more = false
		for d in content.get_all("automation"):
			if Sim.buy_automation(s, d.id)["ok"]:
				_log("automation %s" % d.id)
				more = true
				break


func _training() -> void:
	if lazy or not (s.run["layers"][0]["training"] as Dictionary).is_empty():
		return
	var best_frac := 0.0
	var best_val := -INF
	for frac in [1.0, 0.5, 0.25]:
		var p := Sim.training_preview(s, frac)
		if not p["ok"]:
			continue
		# expected score = log10(spend) * P(success)
		var val: float = (p["spend"] as BigNum).log10() * (1.0 - float(p["fail_chance"]))
		if val > best_val:
			best_val = val
			best_frac = frac
	if best_frac > 0.0:
		Sim.start_training(s, best_frac)
		_log("train frac %.2f" % best_frac)


func _slider() -> void:
	if s.resets(2) == 0:
		return
	var target: float = SLIDER_TARGET[ending_target] if (ending_target != "aligned" or s.resets(4) > 0) else 0.5
	if absf(float(s.run["slider"]) - target) > 1e-6:
		Sim.set_slider(s, target)


func _legacy() -> void:
	if s.resets(4) == 0:
		return
	for key in ["compute", "cash"]:
		while Sim.buy_legacy(s, key)["ok"]:
			_log("legacy %s" % key)


func _challenge() -> void:
	if s.resets(4) == 0 or not (s.run["layers"][4]["challenge"] as Dictionary).is_empty():
		return
	for d in content.get_all("challenges"):
		if d.id in s.run["challenges_done"]:
			continue
		if Sim.start_challenge(s, d.id)["ok"]:
			_unlock("challenge started: %s" % d.id, "challenge:" + d.id)
		return


## Records when each layer's gain first reached 1 and 2, and when it last rose in the current cycle.
## Runs before the strategy each step, so a gain that appeared during the last tick is seen before any reset.
func _track_gains() -> void:
	for k in range(1, 5):
		var g := int(Sim.reset_preview(s, k)["gain"])
		if g >= 1 and first_gain1[k] < 0.0:
			first_gain1[k] = now()
		if g >= 2 and first_gain2[k] < 0.0:
			first_gain2[k] = now()
		if g > last_gain[k]:
			last_gain[k] = g
			last_up[k] = now()


func _resets() -> void:
	var again := true
	while again:
		again = false
		for k in range(1, 5):
			var p := Sim.reset_preview(s, k)
			if not p["allowed"] or int(p["gain"]) < 1:
				continue
			# Highlighted (gain >= 2 and >= 2x holding), or gain has stopped rising.
			if not (p["highlight"] or _stalled(k)):
				continue
			var why := "highlight" if p["highlight"] else "stall"
			var r := Sim.perform_reset(s, k)
			if r["ok"]:
				_on_reset(k, int(r["gain"]), why)
				again = true
				break


## Gain >= 1 that has not risen for STALL_FACTOR times as long as it took to reach its current value.
## Uses gain history only, not cash rate: a lower reset drops the rate, which would make every layer look stalled.
func _stalled(k: int) -> bool:
	var t_up: float = last_up[k]
	return now() - t_up > STALL_FACTOR * (t_up - float(cycle_start[k]))


func _resolve_event() -> void:
	var L0: Dictionary = s.run["layers"][0]
	if L0["pending"] == "":
		return
	var d = content.get_def("events", L0["pending"])
	var best := 0
	var best_score := -INF
	for i in d.choices.size():
		var sc := _score_choice(d.choices[i])
		if sc > best_score:
			best_score = sc
			best = i
	Sim.resolve_event(s, best)
	_log("event %s -> %s" % [d.id, d.choices[best]["label"]])


func _score_choice(ch: Dictionary) -> float:
	var sc := 0.0
	for e in ch["effects"]:
		match e["type"]:
			"add_debt":
				sc -= 2.0 * float(e["value"])
			"add_slider":
				var sign := 1.0 if ending_target == "aligned" else (-1.0 if ending_target == "rushed" else 0.0)
				sc += sign * 5.0 * float(e["value"])
			"add_flag":
				if e["id"] == "open_sourced":
					sc += 100.0 if ending_target == "open_sourced" else -100.0
			"add_currency":
				sc += 1.0 if float(e["value"]) > 0.0 else -0.5
			"timed_mod", "run_mult", "perm_mult":
				sc += 1.0 if float(e["value"]) > 1.0 else -0.5
	return sc


# ---------------------------------------------------------------- bookkeeping

func _on_reset(k: int, gain: int, why: String) -> void:
	var t := now()
	var tag := " (%s)" % why
	cycles[k].append([t - float(cycle_start[k]), _epoch(k), t])
	if first_reset[k] < 0.0:
		first_reset[k] = t
		gain_at_reset[k] = gain
		_unlock("first %s reset, gain %d%s" % [LAYER_NAMES[k], gain, tag], "reset:%d" % k)
		if k == 2:
			_unlock("constraint: alignment slider", "constraint:slider")
		if k == 3:
			_unlock("constraint: data and energy", "constraint:data")
	else:
		_log("%s reset, gain %d%s" % [LAYER_NAMES[k], gain, tag])
	for j in range(1, k + 1):
		cycle_start[j] = t
		last_gain[j] = 0
		last_up[j] = t


## Cycles of layer k are only comparable within an epoch: a reset of any higher layer wipes its economy.
func _epoch(k: int) -> int:
	var e := 0
	for j in range(k + 1, 5):
		e += s.resets(j)
	return e


func _handle(evs: Array) -> void:
	for e in evs:
		match e["kind"]:
			"training_done":
				_unlock("first training run (%s)" % ("ok" if e["ok"] else "failed"), "first_training")
				_log("training %s%s" % ["ok" if e["ok"] else "failed", (" score %.2f" % e["score"]) if e["ok"] else ""])
			"auto_train":
				_log("auto-train started")
			"reset":
				_on_reset(int(e["layer"]), int(e["gain"]), "auto")
			"challenge_done":
				_log("challenge %s %s" % [e["id"], "succeeded" if e["success"] else "failed"])
			"rival_launched":
				_unlock("rival launched: %s" % e["id"], "rival:" + e["id"])
			"agi_advanced":
				var stage = content.get_all("agi_stages")[int(e["index"]) - 1]
				_unlock("AGI stage %d: %s" % [e["index"], stage.id], "agi:%d" % int(e["index"]))
			"ending":
				ending_id = e["id"]
				ending_t = now()
				_unlock("ENDING: %s" % e["id"], "ending")
			"benchmark":
				_unlock("benchmark %s (%s)" % [e["id"], e["badge"]], "bench:" + e["id"])
			"event":
				_log("event offered: %s" % e["id"])


## Detects unlocks that happen inside tick (auto-buy, auto-reset), checks cycles, idleness and numbers.
func _observe() -> void:
	var day := int(now() / DAY)
	while peak_rate.size() <= day:
		peak_rate.append(0.0)
	peak_rate[day] = maxf(float(peak_rate[day]), Sim.compute_per_second(s).to_float())
	if now() >= next_trace:
		next_trace = now() + TRACE_EVERY
		var owned_tiers := 0
		for d in content.get_all("producers"):
			if s.owned(d.id) > 0:
				owned_tiers += 1
		print("  trace %s  cash/s %s  compute/s %s  tiers %d  resets F%d G%d P%d S%d  stage %d  life(G) %s  compute %s  energy %s" % [
			_fmt(now()), Sim.cash_per_second(s).format(), Sim.compute_per_second(s).format(), owned_tiers,
			s.resets(1), s.resets(2), s.resets(3), s.resets(4), int(s.run["stage"]),
			(s.run["layers"][2]["life"] as BigNum).format(), s.cur("compute").format(), s.cur("energy").format()])
	var tier := 0
	for d in content.get_all("producers"):
		tier += 1
		if s.owned(d.id) > 0:
			_unlock("tier %d acquired: %s" % [tier, d.id], "prod:" + d.id)
	for role in STAFF_ROLES:
		if _staff_count(role) > 0:
			_unlock("staff hired: %s" % role, "staff:" + role)
	for id in s.run["layers"][2]["research"]:
		_unlock("research: %s" % id, "res:" + id)
	for id in s.persist["automation"]:
		_unlock("automation: %s" % id, "auto:" + id)
	for key in s.persist["legacy_perks"]:
		_unlock("legacy: %s" % key, "legacy:" + key)
	var sig := _signature()
	if sig != last_sig:
		max_idle = maxf(max_idle, now() - last_action)
		last_action = now()
		actions.append(now())
		last_sig = sig
	_sanity()


func _signature() -> int:
	var n := 0
	for d in content.get_all("producers"):
		n += s.owned(d.id)
	for role in STAFF_ROLES:
		n += _staff_count(role)
	n += s.run["layers"][2]["research"].size() + s.persist["automation"].size()
	n += s.persist["benchmarks"].size() + s.run["challenges_done"].size() + int(s.run["stage"])
	n += int(s.persist["stats"]["trainings"]) + int(s.persist["stats"]["events"])
	for k in range(1, 5):
		n += 1000 * s.resets(k)
	for key in s.persist["legacy_perks"]:
		n += int(s.persist["legacy_perks"][key])
	return n


func _sanity() -> void:
	for k in range(5):
		for name in s.run["layers"][k]["cur"]:
			var v: BigNum = s.run["layers"][k]["cur"][name]
			if is_nan(v.mantissa) or is_inf(v.mantissa) or is_inf(v.to_float()) or v.mantissa < 0.0:
				bad_values += 1
				if bad_values == 1:
					_problem("bad resource %s = %s at %s" % [name, v.format(), _fmt(now())])
	var rate := Sim.cash_per_second(s).to_float()
	if is_nan(rate) or is_inf(rate) or is_nan(float(s.run["slider"])) or is_nan(float(s.run["layers"][0]["debt"])):
		bad_values += 1
		if bad_values == 1:
			_problem("non-finite rate, slider or debt at %s" % _fmt(now()))


# ---------------------------------------------------------------- report

func _report() -> int:
	max_idle = maxf(max_idle, now() - last_action)
	var tgt := ending_target
	print("")
	print("== pacing report: seed %d, branch %s, ending target %s%s, horizon %.1f h, ended at %s" % [
		seed_value, branch, tgt, ", lazy" if lazy else "", hours, _fmt(now())])
	print("first resets (game time); gain>=1 and gain>=2 are first reached, ignoring prerequisites:")
	for k in range(1, 5):
		var band: Array = BANDS[k]
		var verdict := "OK"
		var value := "never"
		if first_reset[k] < 0.0:
			verdict = "MISSING"
			_problem("%s never reset within %.1f h" % [LAYER_NAMES[k], hours])
		else:
			var h := float(first_reset[k]) / HOUR
			value = "%.2f h" % h
			if h < float(band[0]) or h > float(band[1]):
				verdict = "OUT OF BAND"
				_problem("%s first reset at %.2f h outside %.2f–%.2f h" % [LAYER_NAMES[k], h, band[0], band[1]])
		print("  %-16s gain>=1 %s  gain>=2 %s  reset %s (gain %d)  band %6.2f–%6.2f h  design %5.2f h  %s" % [
			LAYER_NAMES[k], _opt_time(first_gain1[k]), _opt_time(first_gain2[k]), value, gain_at_reset[k],
			band[0], band[1], float(Sim.layer_def(s, k).target_hours), verdict])
	print("cycles (life zeroed -> own reset), per layer and epoch (epoch = no higher reset): n, first, second, last, min")
	for k in range(1, 5):
		var list: Array = cycles[k]
		if list.is_empty():
			print("  %-16s none" % LAYER_NAMES[k])
			continue
		var by_epoch := {}
		var epochs: Array = []
		var first_of := {}   # epoch -> length of that epoch's first cycle
		for c in list:
			var e := int(c[1])
			if not by_epoch.has(e):
				by_epoch[e] = []
				epochs.append(e)
			by_epoch[e].append(float(c[0]))
		for ei in epochs.size():
			var e: int = epochs[ei]
			var d: Array = by_epoch[e]
			var lo: float = d.min()
			first_of[e] = d[0]
			if ei < 3 or ei == epochs.size() - 1:
				print("  %-16s epoch %d  %4d  %s  %s  %s  %s" % [LAYER_NAMES[k], e, d.size(), _cyc(d[0]),
					_cyc(d[1]) if d.size() > 1 else "-", _cyc(d[d.size() - 1]), _cyc(lo)])
			elif ei == 3:
				print("  %-16s ... %d more epochs" % [LAYER_NAMES[k], epochs.size() - 4])
			if d.size() < 2:
				continue
			if d[0] > 2.0 * MAX_DT:
				var later := 0.0
				for i in range(1, d.size()):
					later += float(d[i])
				later /= float(d.size() - 1)
				if e == 0:
					# Epoch 0 is the real prestige payoff: cycles 2.. must be clearly faster than the first.
					if later > CYCLE_SPEEDUP * d[0] + MAX_DT:
						_problem("%s epoch %d: cycles 2.. average %s, not meaningfully faster than the first (%s)" % [
							LAYER_NAMES[k], e, _cyc(later).strip_edges(), _cyc(d[0]).strip_edges()])
				elif later > LATER_EPOCH_MAX * d[0]:
					# Later epochs start with kept bonuses, so their first cycle is already fast: only require no slowdown.
					_problem("%s epoch %d: cycles 2.. average %s, slower than %.2fx the first (%s)" % [
						LAYER_NAMES[k], e, _cyc(later).strip_edges(), LATER_EPOCH_MAX, _cyc(d[0]).strip_edges()])
		# A later epoch's first cycle must beat epoch 0's first cycle of the same layer (kept bonuses pay off).
		if first_of.has(0):
			for e in first_of:
				if e > 0 and float(first_of[e]) >= float(first_of[0]):
					_problem("%s epoch %d: first cycle %s not faster than epoch 0's first (%s)" % [
						LAYER_NAMES[k], e, _cyc(float(first_of[e])).strip_edges(), _cyc(float(first_of[0])).strip_edges()])
	print("unlock gaps (longest, by start time):")
	var times: Array = actions.duplicate()
	times.append(now())
	var gen := float(first_reset[2]) if first_reset[2] >= 0.0 else INF
	var para := float(first_reset[3]) if first_reset[3] >= 0.0 else INF
	var worst: Array = [0.0, 0.0, 0.0, 0.0]
	var worst_at: Array = [0.0, 0.0, 0.0, 0.0]
	for i in range(1, times.size()):
		var a: float = times[i - 1]
		var g: float = times[i] - a
		var p := 0
		if a >= HOUR:
			p = 1
		if a >= gen:
			p = 2
		if a >= para:
			p = 3
		if g > float(worst[p]):
			worst[p] = g
			worst_at[p] = a
	var windows := ["first hour", "to Generation", "to Paradigm", "afterwards"]
	var gap_names := ["10 min", "30 min", "3 h", "8 h"]
	for p in 4:
		var limit: float = GAP_LIMITS[p]
		print("  %-14s %8.1f min (starts %s)  limit %s %s" % [windows[p], float(worst[p]) / 60.0,
			_fmt(float(worst_at[p])).strip_edges(), gap_names[p], "OK" if float(worst[p]) <= limit else "FAIL"])
		if float(worst[p]) > limit:
			_problem("unlock gap %.1f min starting at %s (%s) exceeds %s" % [
				float(worst[p]) / 60.0, _fmt(float(worst_at[p])).strip_edges(), windows[p], gap_names[p]])
	print("stall: longest span with no action %.2f h (limit %.1f h)" % [max_idle / HOUR, STALL_LIMIT / HOUR])
	if max_idle > STALL_LIMIT:
		_problem("stall: %.2f h without any action" % (max_idle / HOUR))
	if bad_values > 0:
		_problem("%d non-finite or negative resource readings" % bad_values)
	var trainings := int(s.persist["stats"]["trainings"])
	var failed := int(s.persist["stats"]["failed"])
	var fail_rate := float(failed) / float(maxi(trainings, 1))
	print("training: %d runs, %d failed (%.1f%%)" % [trainings, failed, fail_rate * 100.0])
	if trainings >= 10 and not lazy and (fail_rate < 0.05 or fail_rate > 0.5):
		_problem("training failure rate %.1f%% outside 5–50%%" % (fail_rate * 100.0))
	var bench_total: int = content.get_all("benchmarks").size()
	print("benchmarks unlocked: %d of %d" % [s.persist["benchmarks"].size(), bench_total])
	var reset_parts: Array = []
	for k in range(1, 5):
		reset_parts.append("%s %d" % [LAYER_NAMES[k], s.resets(k)])
	print("resets: " + ", ".join(reset_parts))
	var peaks: Array = []
	for i in peak_rate.size():
		peaks.append("d%d %s" % [i, BigNum.from_float(float(peak_rate[i])).format()])
	print("peak compute/s by game day: " + ", ".join(peaks))
	print("cash/s at end: %s   compute/s: %s" % [Sim.cash_per_second(s).format(), Sim.compute_per_second(s).format()])
	print("ending: %s" % ("none" if ending_id == "" else "%s at %s" % [ending_id, _fmt(ending_t).strip_edges()]))
	if ending_id == "":
		_problem("no AGI ending within %.1f h" % hours)
	elif ending_t < ENDING_EARLIEST:
		_problem("AGI ending %s at %s, before the 8 d floor" % [ending_id, _fmt(ending_t).strip_edges()])
	elif ending_t > LIMIT_HOURS * HOUR:
		_problem("AGI ending %s at %s, after the 14 d limit" % [ending_id, _fmt(ending_t).strip_edges()])
	elif ending_id != ending_target:
		_problem("wanted ending %s, got %s" % [ending_target, ending_id])
	if lazy:
		print("(lazy run: report only, nothing gated)")
		return 0
	if problems.is_empty():
		print("ALL CHECKS PASS")
		return 0
	for p in problems:
		printerr("CHECK FAILED: " + p)
	return 1
