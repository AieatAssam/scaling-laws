extends "res://tools/simulate.gd"
## Reward-gap study. Extends tools/simulate.gd, so the scripted strategy, ticks and resets are the parent's, unchanged.
## This script only watches and reports. Members are prefixed rg_; every override calls its super.
##
##   $GODOT --headless --path . -s tools/reward_gaps.gd -- --hours=336 --seed=1 --ending=aligned
##
## Reward kinds and class:
##   BIG:   tier (first purchase of a tier, ever), automation, moonshot (completed), reset (any layer), agi, ending,
##          unlock (a tab, system, constraint, the first event, the first training run)
##   small: milestone (25/50/100/200 owned, each run), hire, research, legacy, training (new best score),
##          benchmark, challenge (regulation completed, pass or fail), rival (launch; the code has no "overtake"),
##          upgrade (bought, manual or automatic), launch (fired), paper (desk choice resolved)
##   novel: first-of-kind only: first tier, first reset of each layer, unlock, automation, moonshot, agi, ending.
## Gaps run between reward moments: rewards in one sim step form one moment. Steps are 30–120 s apart, so gap
## lengths are good to about ±2 min.
## Dry stretches are steps at which nothing is affordable:
##   purchase-dry: no affordable producer, hire, research, automation or legacy.
##   decision-dry: also no pending event, highlighted reset, startable challenge or startable training run.
## Repeat purchases are not rewards by definition, so a long gap marks where the player sees nothing new.

const RG_BIG := ["tier", "automation", "moonshot", "reset", "agi", "ending", "unlock"]
const RG_KINDS := ["tier", "milestone", "hire", "research", "automation", "legacy", "training", "benchmark",
	"challenge", "rival", "upgrade", "launch", "paper", "moonshot", "reset", "agi", "ending", "unlock"]
const RG_PHASES := [[0.0, 1.0], [1.0, 4.0], [4.0, 12.0], [12.0, 24.0], [24.0, 48.0], [48.0, 72.0], [72.0, 1e9]]
const RG_PHASE_NAMES := ["0-1 h", "1-4 h", "4-12 h", "12-24 h", "day 2", "day 3", "day 4+"]
const RG_TABS := ["", "Funding", "Generation", "Paradigm", "Singularity"]
# Flag letters, in this order: F G P Y = tabs Funding, Generation, Paradigm, Singularity.
# H hiring. R research tree. S alignment slider. U automation. D data and energy. L legacy.
# C regulation challenges. V rival labs. E first event. T first training run.
const RG_FLAGS := "FGPYHRSUDLCVET"
const RG_MILESTONES := [25, 50, 100, 200]
const RG_DRY_MIN := 600.0
const RG_TOP := 15

var rg_rewards: Array = []          # {t, kind, big, novel, label, state}
var rg_seen := {}                   # flag letter -> true, once an unlock fired
var rg_ever_tier := {}              # producer id -> true, first purchase ever
var rg_first_reset: Array = [false, false, false, false, false]
var rg_prev_owned := {}             # producer id -> owned at the last observe (this run)
var rg_prev_staff := {}
var rg_prev_research: Array = []
var rg_prev_auto: Array = []
var rg_prev_legacy := {}
var rg_prev_upgrades: Array = []
var rg_prev_launches := 0
var rg_dry := {"p": [], "d": []}    # key -> [start, end, what ended it, state at start]
var rg_dry_start := {"p": -1.0, "d": -1.0}
var rg_dry_state := {"p": {}, "d": {}}
var rg_evs := {}                    # event kind -> count seen by _handle
var rg_end := 0.0


# ---------------------------------------------------------------- hooks (every one calls super)

func _say(_msg: String) -> void:
	pass   # the parent's unlock lines; this tool reports its own


func _policy() -> void:
	# Checked before and after the strategy acts. The step length is chosen so the next purchase is affordable at
	# the next call, so checking only before would miss the wait, which happens inside the tick. A stretch opens when
	# nothing is affordable after the strategy's purchases and closes at the first call where something is.
	_rg_dry_mark()
	super._policy()
	_rg_dry_mark()


func _observe() -> void:
	super._observe()
	for d in content.get_all("producers"):
		var n: int = s.owned(d.id)
		var old: int = rg_prev_owned.get(d.id, 0)
		if n > 0 and not rg_ever_tier.has(d.id):
			rg_ever_tier[d.id] = true
			_reward("tier", "first %s" % d.title, true)
		for m in RG_MILESTONES:
			if n >= m and old < m:
				_reward("milestone", "%s: %d owned" % [d.title, m], false)
		rg_prev_owned[d.id] = n
	for role in STAFF_ROLES:
		var n: int = _staff_count(role)
		for i in range(int(rg_prev_staff.get(role, 0)), n):
			_reward("hire", "hired %s (%d)" % [role, i + 1], false)
		rg_prev_staff[role] = n
	var res: Array = s.run["layers"][2]["research"]
	for id in res:
		if not (id in rg_prev_research):
			_reward("research", "research %s" % id, false)
	rg_prev_research = res.duplicate()
	var auto: Array = s.persist["automation"]
	for id in auto:
		if not (id in rg_prev_auto):
			_reward("automation", "automation %s" % id, true)
	rg_prev_auto = auto.duplicate()
	var perks: Dictionary = s.persist["legacy_perks"]
	for key in perks:
		for i in range(int(rg_prev_legacy.get(key, 0)), int(perks[key])):
			_reward("legacy", "legacy perk %s (%d)" % [key, i + 1], false)
	rg_prev_legacy = perks.duplicate()
	var ups: Array = Upgrades.owned_ids(s)
	for id in ups:
		if not (id in rg_prev_upgrades):
			_reward("upgrade", "upgrade %s" % id, false)
	rg_prev_upgrades = ups.duplicate()
	var launched := int(s.persist["stats"]["launches"])
	for i in range(rg_prev_launches, launched):
		_reward("launch", "launch fired (%d)" % (i + 1), false)
	rg_prev_launches = launched
	for k in range(1, 5):
		# Mirrors the panels' is_unlocked(): layer k shows after a reset of k-1 or k, or once its gain reaches 1.
		var shown: bool = s.resets(k) > 0 or (k > 1 and s.resets(k - 1) > 0) or int(Sim.reset_preview(s, k)["gain"]) >= 1
		_unlock_once(RG_FLAGS.substr(k - 1, 1), shown, "tab: %s" % RG_TABS[k])
	_unlock_once("H", s.resets(1) > 0, "system: hiring (staff)")
	_unlock_once("R", s.resets(2) > 0, "system: research tree")
	_unlock_once("S", s.resets(2) > 0, "constraint: alignment slider")
	_unlock_once("U", s.resets(3) > 0, "system: automation")
	_unlock_once("D", s.resets(3) > 0, "constraint: data and energy")
	_unlock_once("L", s.resets(4) > 0, "system: legacy")
	_unlock_once("C", s.resets(4) > 0, "system: regulation challenges")
	_unlock_once("V", s.resets(4) > 0, "system: rival labs")


func _handle(evs: Array) -> void:
	for e in evs:
		rg_evs[e["kind"]] = int(rg_evs.get(e["kind"], 0)) + 1
		match e["kind"]:
			"training_done":
				_unlock_once("T", true, "first training run (%s)" % ("ok" if e["ok"] else "failed"))
				if e["ok"]:
					if e["new_best"]:
						_reward("training", "new best score %.2f (%s)" % [e["score"], e["id"]], false)
			"event":
				_unlock_once("E", true, "first event offered (%s)" % e["id"])
			"benchmark":
				_reward("benchmark", "benchmark %s (%s)" % [e["id"], e["badge"]], false)
			"challenge_done":
				_reward("challenge", "regulation %s %s" % [e["id"], "passed" if e["success"] else "failed"], false)
			"rival_launched":
				_reward("rival", "rival launched: %s" % e["id"], false)
			"agi_advanced":
				var stage = content.get_all("agi_stages")[int(e["index"]) - 1]
				_reward("agi", "AGI stage %d: %s" % [int(e["index"]), stage.id], true)
			"ending":
				_reward("ending", "ENDING %s" % e["id"], true)
			"moonshot_done":
				_reward("moonshot", "moonshot %s" % e["id"], true)
			"paper_resolved":
				_reward("paper", "paper %s (choice %d)" % [e["id"], int(e["choice"])], false)
	super._handle(evs)


func _on_reset(k: int, gain: int, why: String) -> void:
	var first: bool = not rg_first_reset[k]
	rg_first_reset[k] = true
	_reward("reset", "%s reset, gain %d (%s)" % [LAYER_NAMES[k], gain, why], first)
	super._on_reset(k, gain, why)


func _report() -> int:
	for key in ["p", "d"]:
		_rg_dry_close(key)
	rg_end = now()
	var hashes: Array = []
	OS.execute("git", ["hash-object", "tools/simulate.gd", "src/core/sim.gd"], hashes)
	print("")
	print("== reward gaps: seed %d, branch %s, ending target %s, game length %s, ending %s" % [
		seed_value, branch, ending_target, _rg_t(rg_end),
		("%s at %s" % [ending_id, _rg_t(ending_t)]) if ending_id != "" else "none"])
	print("code: git hash-object tools/simulate.gd src/core/sim.gd = %s" % ("".join(hashes).strip_edges().replace("\n", " ")))
	print("flags: F Funding tab, G Generation tab, P Paradigm tab, Y Singularity tab, H hiring, R research, S slider, U automation, D data+energy, L legacy, C challenges, V rivals, E first event, T first training")
	_rg_counts()
	_rg_gap_section("longest gaps between any two reward moments:", "all")
	_rg_gap_section("longest gaps between BIG reward moments:", "big")
	_rg_gap_section("longest gaps between novel (first-of-kind) moments:", "novel")
	_rg_phase_table()
	_rg_dry_section("p", "purchase-dry stretches (nothing affordable to buy), longest first:")
	_rg_dry_section("d", "decision-dry stretches (nothing to buy or decide), longest first:")
	_rg_unlocks()
	_rg_checks()
	return 0


# ---------------------------------------------------------------- recording

func _reward(kind: String, label: String, novel: bool) -> void:
	rg_rewards.append({"t": now(), "kind": kind, "big": RG_BIG.has(kind), "novel": novel, "label": label,
		"state": _state()})


func _unlock_once(flag: String, cond: bool, label: String) -> void:
	if cond and not rg_seen.has(flag):
		rg_seen[flag] = true
		_reward("unlock", label, true)


func _state() -> Dictionary:
	var top := "none"
	for d in content.get_all("producers"):
		var n: int = s.owned(d.id)
		if n > 0:
			top = "%s x%d" % [d.title, n]
	var gp := int(Sim.reset_preview(s, 3)["gain"])
	var gs := int(Sim.reset_preview(s, 4)["gain"])
	return {"layers": "F%d G%d P%d S%d" % [s.resets(1), s.resets(2), s.resets(3), s.resets(4)], "top": top,
		"flags": _rg_flags(), "stage": int(s.run["stage"]), "bt": s.cur("breakthroughs").format(),
		"next": "P gain %d, S gain %d" % [gp, gs], "rate": Sim.compute_per_second(s).format()}


func _rg_flags() -> String:
	var out := ""
	for i in RG_FLAGS.length():
		var c := RG_FLAGS.substr(i, 1)
		out += c if rg_seen.has(c) else "."
	return out


## What the player could buy (and, with decisions, decide) right now. "" when nothing.
func _first_action(decisions: bool) -> String:
	for d in content.get_all("producers"):
		if Sim.producer_available(s, d.id) and Sim.max_affordable(s, d.id) > 0:
			return "buy " + d.id
	if s.resets(1) > 0:
		for role in STAFF_ROLES:
			if Sim.hire_blocker(s, role) == "":
				return "hire " + role
	if s.resets(2) > 0:
		for d in content.get_all("research"):
			if Sim.research_blocker(s, d.id) == "":
				return "research " + d.id
	for d in content.get_all("automation"):
		if Sim.automation_blocker(s, d.id) == "":
			return "automation " + d.id
	if s.resets(4) > 0:
		for key in ["compute", "cash"]:
			if Sim.legacy_blocker(s, key) == "":
				return "legacy " + key
	if not decisions:
		return ""
	var pending := String(s.run["layers"][0]["pending"])
	if pending != "":
		return "event " + pending
	for k in range(1, 5):
		var p := Sim.reset_preview(s, k)
		if p["allowed"] and p["highlight"]:
			return "reset " + LAYER_NAMES[k]
	if s.resets(4) > 0 and (s.run["layers"][4]["challenge"] as Dictionary).is_empty():
		for d in content.get_all("challenges"):
			if d.id in s.run["challenges_done"]:
				continue
			if Sim.challenge_blocker(s, d.id) == "":
				return "challenge " + d.id
	if (s.run["layers"][0]["training"] as Dictionary).is_empty():
		var pick := Sim.pick_training(s)
		if pick != "":
			return "train " + pick
	return ""


func _rg_dry_mark() -> void:
	var pur := _first_action(false)
	var dec := pur if pur != "" else _first_action(true)
	_rg_dry_set("p", pur)
	_rg_dry_set("d", dec)


## what == "" means dry. A stretch closes when something becomes actionable; `what` names that thing.
func _rg_dry_set(key: String, what: String) -> void:
	if what == "":
		if float(rg_dry_start[key]) < 0.0:
			rg_dry_start[key] = now()
			rg_dry_state[key] = _state()
	elif float(rg_dry_start[key]) >= 0.0:
		rg_dry[key].append([rg_dry_start[key], now(), what, rg_dry_state[key]])
		rg_dry_start[key] = -1.0


func _rg_dry_close(key: String) -> void:
	if float(rg_dry_start[key]) >= 0.0:
		rg_dry[key].append([rg_dry_start[key], now(), "(game end)", rg_dry_state[key]])
		rg_dry_start[key] = -1.0


# ---------------------------------------------------------------- report

func _rg_t(t: float) -> String:
	return "%.2f h" % (t / HOUR)


func _rg_len(sec: float) -> String:
	return ("%.0f min" % (sec / 60.0)) if sec < 3600.0 else ("%.2f h" % (sec / HOUR))


func _rg_clip(text: String, n: int) -> String:
	return text if text.length() <= n else text.substr(0, n - 2) + ".."


func _rg_moments(filter: String) -> Array:
	var out: Array = []
	for r in rg_rewards:
		if (filter == "big" and not r["big"]) or (filter == "novel" and not r["novel"]):
			continue
		if out.is_empty() or absf(float(out[-1]["t"]) - float(r["t"])) > 1e-6:
			out.append({"t": r["t"], "labels": [], "state": r["state"]})
		out[-1]["labels"].append(r["label"])
		out[-1]["state"] = r["state"]
	return out


func _rg_gaps(filter: String) -> Array:
	var m := _rg_moments(filter)
	m.push_front({"t": 0.0, "labels": ["game start"], "state": {}})
	m.append({"t": rg_end, "labels": ["game end"], "state": {}})
	var gaps: Array = []
	for i in range(m.size() - 1):
		gaps.append({"from": m[i], "to": m[i + 1], "len": float(m[i + 1]["t"]) - float(m[i]["t"])})
	gaps.sort_custom(func(a, b): return float(a["len"]) > float(b["len"]))
	return gaps.slice(0, RG_TOP)


func _rg_counts() -> void:
	var n := {}
	var big := 0
	var novel := 0
	for r in rg_rewards:
		n[r["kind"]] = int(n.get(r["kind"], 0)) + 1
		big += 1 if r["big"] else 0
		novel += 1 if r["novel"] else 0
	print("reward counts (raw):")
	for kind in RG_KINDS:
		print("  %-11s %4d  %s" % [kind, int(n.get(kind, 0)), "BIG" if RG_BIG.has(kind) else "small"])
	print("  total %d: BIG %d, small %d; novel %d; reward moments %d" % [rg_rewards.size(), big,
		rg_rewards.size() - big, novel, _rg_moments("all").size()])


func _rg_gap_section(title: String, filter: String) -> void:
	print("")
	print(title)
	var i := 0
	for g in _rg_gaps(filter):
		i += 1
		var frm: Dictionary = g["from"]
		var nxt: Dictionary = g["to"]
		var st: Dictionary = frm["state"]
		var at := "-" if st.is_empty() else "%s, top %s, systems %s, stage %d, breakthroughs %s, compute/s %s, next reset gains: %s" % [
			st["layers"], st["top"], st["flags"], st["stage"], st["bt"], st["rate"], st["next"]]
		print("  %2d. %s -> %s  (%s)" % [i, _rg_t(float(frm["t"])), _rg_t(float(nxt["t"])), _rg_len(float(g["len"]))])
		print("      state at start: %s" % at)
		print("      last: %s" % _rg_clip(" | ".join(PackedStringArray(frm["labels"])), 120))
		print("      next: %s" % _rg_clip(" | ".join(PackedStringArray(nxt["labels"])), 120))


func _rg_phase_table() -> void:
	print("")
	print("per phase (raw rewards per game hour; dry = share of phase time with nothing affordable):")
	print("  phase     hours   small/h   big/h  novel   purchase-dry  decision-dry")
	var end_h := rg_end / HOUR
	for i in RG_PHASES.size():
		var a: float = RG_PHASES[i][0]
		var b := minf(float(RG_PHASES[i][1]), end_h)
		var span := b - a
		if span <= 0.0:
			print("  %-8s  not reached" % RG_PHASE_NAMES[i])
			continue
		var small := 0
		var big := 0
		var novel := 0
		for r in rg_rewards:
			var h := float(r["t"]) / HOUR
			if h >= a and h < b:
				if r["big"]:
					big += 1
				else:
					small += 1
				if r["novel"]:
					novel += 1
		print("  %-8s %6.2f  %8.2f  %6.2f  %5d  %11.0f%%  %11.0f%%" % [RG_PHASE_NAMES[i], span, small / span,
			big / span, novel, 100.0 * _rg_dry_in("p", a, b) / (span * HOUR), 100.0 * _rg_dry_in("d", a, b) / (span * HOUR)])


func _rg_dry_in(key: String, a: float, b: float) -> float:
	var total := 0.0
	for d in rg_dry[key]:
		total += maxf(0.0, minf(float(d[1]), b * HOUR) - maxf(float(d[0]), a * HOUR))
	return total


func _rg_dry_section(key: String, title: String) -> void:
	var rows: Array = []
	var total := 0.0
	var all_dry := 0.0
	for d in rg_dry[key]:
		var length := float(d[1]) - float(d[0])
		all_dry += length
		if length >= RG_DRY_MIN:
			rows.append(d)
			total += length
	print("")
	print("%s  [%d stretches >= %d min, %.2f h total; all dry time %.2f h = %.0f%% of game]" % [
		title, rows.size(), int(RG_DRY_MIN / 60.0), total / HOUR, all_dry / HOUR, 100.0 * all_dry / maxf(rg_end, 1.0)])
	rows.sort_custom(func(a, b): return (float(a[1]) - float(a[0])) > (float(b[1]) - float(b[0])))
	for i in mini(rows.size(), 8):
		var d: Array = rows[i]
		var st: Dictionary = d[3]
		print("  %s -> %s (%s)  state: %s, top %s, systems %s  | ended by: %s" % [_rg_t(float(d[0])), _rg_t(float(d[1])),
			_rg_len(float(d[1]) - float(d[0])), st.get("layers", "-"), st.get("top", "-"), st.get("flags", "-"), d[2]])


func _rg_unlocks() -> void:
	print("")
	print("tabs, systems and constraints as they first unlock (flags after each):")
	for r in rg_rewards:
		if r["kind"] == "unlock":
			print("  %s  %-40s [%s]" % [_rg_t(float(r["t"])), r["label"], r["state"]["flags"]])
	var firsts: Array = []
	for r in rg_rewards:
		if r["kind"] == "tier":
			firsts.append("%s @ %s" % [str(r["label"]).trim_prefix("first "), _rg_t(float(r["t"]))])
	print("producer tiers first bought: " + "; ".join(PackedStringArray(firsts)))


func _rg_checks() -> void:
	var fired := {}
	for r in rg_rewards:
		fired[r["kind"]] = true
	print("")
	for kind in ["tier", "milestone", "hire", "research", "automation", "moonshot", "upgrade", "launch", "paper", "training", "benchmark", "reset", "agi", "unlock"]:
		if not fired.has(kind):
			print("WARN: no %s reward fired" % kind)
	if ending_id == "":
		print("WARN: no ending within %.1f h" % hours)
	for kind in ["training_done", "benchmark", "agi_advanced", "event"]:
		if not rg_evs.has(kind):
			print("WARN: no %s event reached _handle" % kind)
	if ending_id != "" and not rg_evs.has("ending"):
		print("WARN: ending reached but no ending event reached _handle")
	if s.resets(4) > 0:
		for kind in ["challenge_done", "rival_launched"]:
			if not rg_evs.has(kind):
				print("WARN: no %s event reached _handle" % kind)
	for p in problems:
		print("parent check: %s" % p)
	print("events seen by _handle: %s" % str(rg_evs))
	print("trainings %d, failed %d" % [int(s.persist["stats"]["trainings"]), int(s.persist["stats"]["failed"])])
