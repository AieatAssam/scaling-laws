class_name Records
extends RefCounted
## Progress statistics and records (pure helpers, no UI). They live in persist.records, which survives resets:
##   fastest        layer key ("1".."4") -> seconds of the quickest cycle of that reset layer
##   cycle_start    per layer index 0..4 -> game time (persist.stats.time) at which that layer was last cleared
##   run_start      game time at which this run began
##   producers, research, challenges, endings, outpaced   id -> true, every item ever achieved
##   agi_best       AGI stages reached (0..5), the best over all runs
##   best_gain      layer key -> the largest gain of one reset of that layer (absent in older saves: shows as unknown)
## Game connects its signals to these functions; the Stats screen reads completion() and the times.
## A save from before records existed is migrated (SaveSystem._v3_to_v4) with cycle_start at the migration time, so the
## first reset of each layer after that sets its baseline time rather than a record.

## Reset layers are 1..4; index 0 is the producers layer, which every reset also clears.
const LAYERS := 4


static func default(now: float) -> Dictionary:
	return {
		"fastest": {}, "cycle_start": [now, now, now, now, now], "run_start": now,
		"producers": {}, "research": {}, "challenges": {}, "endings": {}, "outpaced": {},
		"agi_best": 0, "best_gain": {},
	}


## Largest gain of one reset of layer k so far.
static func note_gain(persist: Dictionary, k: int, gain: float) -> void:
	var r: Dictionary = persist["records"]
	var best: Dictionary = r.get("best_gain", {})
	r["best_gain"] = best
	best[str(k)] = maxf(float(best.get(str(k), 0.0)), gain)


## Called on every layer reset (manual or automatic). Returns {layer, secs, first, record}. The first reset of a layer
## sets its time without being a record; later ones are records only when faster than the best so far.
static func note_reset(persist: Dictionary, k: int) -> Dictionary:
	var r: Dictionary = persist["records"]
	var now := float(persist["stats"]["time"])
	var secs := maxf(now - float(r["cycle_start"][k]), 0.0)
	var key := str(k)
	var first := not (r["fastest"] as Dictionary).has(key)
	var record := not first and secs < float(r["fastest"][key])
	if first or record:
		r["fastest"][key] = secs
	for j in range(0, k + 1):  # a reset of layer k clears layers 0..k
		r["cycle_start"][j] = now
	return {"layer": k, "secs": secs, "first": first, "record": record}


static func new_run(persist: Dictionary) -> void:
	var r: Dictionary = persist["records"]
	var now := float(persist["stats"]["time"])
	r["run_start"] = now
	for j in r["cycle_start"].size():
		r["cycle_start"][j] = now


## Marks an achievement: group is producers, research, challenges, endings or outpaced; id is the content id.
static func note(persist: Dictionary, group: String, id: String) -> void:
	(persist["records"][group] as Dictionary)[id] = true


static func note_agi(persist: Dictionary, index: int) -> void:
	persist["records"]["agi_best"] = maxi(int(persist["records"]["agi_best"]), index)


## An ending ends the run: every rival that has not launched yet was outpaced.
static func note_ending(s: GameState, id: String) -> void:
	note(s.persist, "endings", id)
	for r in s.db.get_all("rivals"):
		if not bool(s.run["flags"].get("rival_%s_launched" % r.id, false)):
			note(s.persist, "outpaced", r.id)


## Adds whatever the current state already shows (called when a save is loaded, so older saves count what they have).
static func absorb(s: GameState) -> void:
	var p := s.persist
	for id in s.run["layers"][0]["owned"]:
		if int(s.run["layers"][0]["owned"][id]) > 0:
			note(p, "producers", id)
	for L in s.run["layers"]:
		for id in L["research"]:
			note(p, "research", id)
	var passed: Dictionary = s.run.get("challenge_passed", {})
	for id in passed:
		if bool(passed[id]):
			note(p, "challenges", id)
	if String(s.run["run_over"]) != "":
		note(p, "endings", String(s.run["run_over"]))
	note_agi(p, int(s.run["stage"]))


## Completion over every system, equal weight per part. Each part: {id, label, done, total}; percent is 0..100.
static func completion(s: GameState) -> Dictionary:
	var p := s.persist
	var parts: Array = [
		_part("producers", "Producer tiers", s.db.get_all("producers"), p["records"]["producers"]),
		_part("benchmarks", "Benchmarks", s.db.get_all("benchmarks"), _to_set(p["benchmarks"])),
		_part("research", "Research", s.db.get_all("research"), p["records"]["research"]),
		_part("automation", "Automation", s.db.get_all("automation"), _to_set(p["automation"])),
		_part("resets", "Reset layers", null, {}, LAYERS, _layers_reset(p)),
		_part("challenges", "Challenges", s.db.get_all("challenges"), p["records"]["challenges"]),
		_part("rivals", "Rivals outpaced", s.db.get_all("rivals"), p["records"]["outpaced"]),
		_part("agi", "AGI stages", null, {}, s.db.get_all("agi_stages").size(), int(p["records"]["agi_best"])),
		_part("endings", "Endings", s.db.get_all("endings"), p["records"]["endings"]),
	]
	var sum := 0.0
	for part in parts:
		sum += float(part["done"]) / maxf(float(part["total"]), 1.0)
	return {"percent": 100.0 * sum / parts.size(), "parts": parts}


## One part: `defs` are the content defs (their ids count), `have` maps achieved ids to true. Passing `total` and
## `done` directly (defs null) covers the counted parts (reset layers, AGI stages).
static func _part(id: String, label: String, defs, have: Dictionary, total := -1, done := -1) -> Dictionary:
	if defs == null:
		return {"id": id, "label": label, "done": done, "total": total}
	var n := 0
	for d in defs:
		if have.has(d.id):
			n += 1
	return {"id": id, "label": label, "done": n, "total": (defs as Array).size()}


static func _to_set(ids: Array) -> Dictionary:
	var d := {}
	for id in ids:
		d[id] = true
	return d


static func _layers_reset(p: Dictionary) -> int:
	var n := 0
	for k in LAYERS:
		if int(p["lifetime_resets"][k]) > 0:
			n += 1
	return n


## Seconds played in this run.
static func run_seconds(persist: Dictionary) -> float:
	return maxf(float(persist["stats"]["time"]) - float(persist["records"]["run_start"]), 0.0)


## "45s", "12m 04s", "1h 03m".
static func format_duration(secs: float) -> String:
	var t := int(secs)
	if t >= 3600:
		return "%dh %02dm" % [t / 3600, (t % 3600) / 60]
	if t >= 60:
		return "%dm %02ds" % [t / 60, t % 60]
	return "%ds" % t


## Display name of reset layer k (1..4), from its content def.
static func layer_title(s: GameState, k: int) -> String:
	for d in s.db.get_all("layers"):
		if int(d.index) == k:
			return str(d.title)
	return "Layer %d" % k
