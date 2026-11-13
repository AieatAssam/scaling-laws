extends Node
## Versioned JSON save. File = {"version": VERSION, "state": <GameState.to_dict()>}.
## Recovery: a damaged main file is set aside as <path>.bad-<ms> and the rolling backup <path>.bak is tried;
## a file from a newer version is set aside as <path>.newer-<ms> and never overwritten. `last_notice` says
## what load_data had to do (empty when nothing happened); Game shows it to the player.

const VERSION := 10
const DEFAULT_PATH := "user://save.json"

var last_notice := ""


## Writes `state` (a plain Dictionary from GameState.to_dict) to `path`. Returns true on success.
## The previous good file is copied to <path>.bak first; a damaged or missing file is not copied over it.
## Refuses (false) to overwrite a file written by a newer version.
func save(state: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var status := String(_parse(path)["status"])
	if status == "newer":
		push_error("SaveSystem: %s was written by a newer version; not overwriting it" % path)
		return false
	if status == "ok":
		DirAccess.copy_absolute(path, path + ".bak")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": VERSION, "state": state}, "", true, true))
	return true


## Returns the saved state Dictionary (migrated to the current version), or {} for a new game.
## Sets last_notice when a damaged file was set aside or a backup was used.
func load_data(path: String = DEFAULT_PATH) -> Dictionary:
	last_notice = ""
	var main := _parse(path)
	match main["status"]:
		"missing":
			return {}
		"ok":
			return migrate(main["wrapper"])
		"newer":
			var kept := _set_aside(path, "newer")
			last_notice = "This save was made by a newer version of the game. It was kept as %s, and a new game was started." % kept.get_file()
			push_warning("SaveSystem: %s is from a newer version; kept as %s" % [path, kept])
			return {}
	var bad := _set_aside(path, "bad")
	var backup := _parse(path + ".bak")
	if backup["status"] == "ok":
		last_notice = "Your save was damaged. The last backup was restored; the damaged file was kept as %s." % bad.get_file()
		push_warning("SaveSystem: %s was damaged; restored %s.bak (kept as %s)" % [path, path, bad])
		return migrate(backup["wrapper"])
	last_notice = "Your save was damaged and no backup could be read. A new game was started; the damaged file was kept as %s." % bad.get_file()
	push_warning("SaveSystem: %s is not a valid save; kept as %s" % [path, bad])
	return {}


## Deletes the save and its rolling backup (Settings > Hard reset).
func delete(path: String = DEFAULT_PATH) -> void:
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Upgrades an older wrapper to VERSION. Add one `if v < N:` block per schema change.
func migrate(wrapper: Dictionary) -> Dictionary:
	var v := _version_of(wrapper)
	if v > VERSION:
		push_error("SaveSystem: save version %d is newer than %d" % [v, VERSION])
		return {}
	var state: Dictionary = wrapper.get("state", {})
	if v < 2:
		state = _v1_to_v2(state)
	if v < 3:
		state = _v2_to_v3(state)
	if v < 4:
		state = _v3_to_v4(state)
	if v < 5:
		state = _v4_to_v5(state)
	if v < 6:
		state = _v5_to_v6(state)
	if v < 7:
		state = _v6_to_v7(state)
	if v < 8:
		state = _v7_to_v8(state)
	if v < 9:
		state = _v8_to_v9(state)
	if v < 10:
		state = _v9_to_v10(state)
	return state


static func _v9_to_v10(state: Dictionary) -> Dictionary:
	var persist: Dictionary = state.get("persist", {})
	var moonshots: Dictionary = persist.get("moonshots", {"running": [], "done": []})
	if not moonshots.has("programme"):
		moonshots["programme"] = {"level": 0, "left": 0.0}
	persist["moonshots"] = moonshots
	state["persist"] = persist
	return state


static func _v8_to_v9(state: Dictionary) -> Dictionary:
	var persist: Dictionary = state.get("persist", {})
	var records: Dictionary = persist.get("records", {})
	records["offline_seconds"] = float(records.get("offline_seconds", 0.0))
	if not records.has("deployment_burst_cash"):
		records["deployment_burst_cash"] = BigNum.new().to_json()
	persist["records"] = records
	state["persist"] = persist
	return state


## Adds Singularity-run AGI maxima; GameState.from_dict seeds them from the loaded live values.
static func _v7_to_v8(state: Dictionary) -> Dictionary:
	var run: Dictionary = state.get("run", {})
	if not run.has("peak_compute_rate"):
		run["peak_compute_rate"] = 0.0
	if not run.has("agi_peaks"):
		run["agi_peaks"] = {"owned": {}, "energy": 0.0, "training_best": 0.0}
	state["run"] = run
	return state


## Adds the AGI choices of the run (run.agi_choices). Stages already cleared before evals existed were passed by
## shipping: a run that has ended maps its ending to the method that wins it (aligned full, open_sourced red-team,
## rushed ship). New run and persist keys are filled from defaults by GameState.from_dict; no counters are added.
static func _v6_to_v7(state: Dictionary) -> Dictionary:
	var run: Dictionary = state.get("run", {})
	if not run.has("agi_choices"):
		var over := String(run.get("run_over", ""))
		var method: String = {"aligned": "full", "open_sourced": "redteam"}.get(over, "ship")
		var n := int(run.get("stage", 0))
		if over != "":
			n = 5
		var choices: Array = []
		for i in n:
			choices.append(method if over != "" else "ship")
		run["agi_choices"] = choices
	state["run"] = run
	return state


## Adds persist.records (Records) to a save from before the statistics screen. Its clocks start now: the first reset of
## each layer after this sets that layer's baseline time.
static func _v3_to_v4(state: Dictionary) -> Dictionary:
	var persist: Dictionary = state.get("persist", {})
	var stats: Dictionary = persist.get("stats", {})
	if not persist.has("records"):
		persist["records"] = Records.default(float(stats.get("time", 0.0)))
	state["persist"] = persist
	return state


## Adds the lab upgrade list (layer 0), run-level launch cooldowns and breaking-news state, and their catch counters.
## Missing keys get their empty values; a save that already has them is left as it is.
static func _v4_to_v5(state: Dictionary) -> Dictionary:
	var run: Dictionary = state.get("run", {})
	var persist: Dictionary = state.get("persist", {})
	var layers: Array = run.get("layers", [])
	if layers.size() > 0 and layers[0] is Dictionary and not layers[0].has("upgrades"):
		layers[0]["upgrades"] = []
	if not run.has("launches"):
		run["launches"] = {}
	if not run.has("news"):
		run["news"] = {"timer": News.FIRST_SECONDS, "chip": {}}
	var stats: Dictionary = persist.get("stats", {})
	for k in ["launches", "news"]:
		if not stats.has(k):
			stats[k] = 0
	persist["stats"] = stats
	state["run"] = run
	state["persist"] = persist
	return state


## Adds Moonshots state (persist.moonshots: running projects and completed ids) and its stats counter.
static func _v5_to_v6(state: Dictionary) -> Dictionary:
	var persist: Dictionary = state.get("persist", {})
	if not persist.has("moonshots"):
		persist["moonshots"] = {"running": [], "done": []}
	var stats: Dictionary = persist.get("stats", {})
	if not stats.has("moonshots"):
		stats["moonshots"] = 0
	persist["stats"] = stats
	state["persist"] = persist
	return state


static func _v2_to_v3(state: Dictionary) -> Dictionary:
	var run: Dictionary = state.get("run", {})
	var layers: Array = run.get("layers", [])
	if layers.size() > 2 and layers[2] is Dictionary and not layers[2].has("desk"):
		layers[2]["desk"] = {"slots": [], "timer": 1200.0, "bonus": 0.0}
	return state


## Reads `path` without migrating. status is missing, corrupt, newer or ok; ok also carries the wrapper.
func _parse(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing"}
	# JSON.new().parse reports bad text through its return code; parse_string would also log an engine error.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"status": "corrupt"}
	var wrapper: Variant = json.data
	if not (wrapper is Dictionary) or not (wrapper.get("state") is Dictionary):
		return {"status": "corrupt"}
	if _version_of(wrapper) > VERSION:
		return {"status": "newer"}
	if not _shape_ok(wrapper["state"]):
		return {"status": "corrupt"}
	return {"status": "ok", "wrapper": wrapper}


static func _version_of(wrapper: Dictionary) -> int:
	var v: Variant = wrapper.get("version", 0)
	return int(v) if (v is float or v is int) else 0


## The structure from_dict relies on. Anything else is treated as damage, not migrated.
static func _shape_ok(state: Dictionary) -> bool:
	for k in ["persist", "run"]:
		if state.has(k) and not (state[k] is Dictionary):
			return false
	var run: Dictionary = state.get("run", {})
	if run.has("layers"):
		if not (run["layers"] is Array):
			return false
		for L in run["layers"]:
			if not (L is Dictionary) or (L.has("cur") and not (L["cur"] is Dictionary)):
				return false
	return true


## Moves `path` aside to a free name "<path>.<kind>-<ms>" so nothing is overwritten. Returns the new path.
func _set_aside(path: String, kind: String) -> String:
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var dest := "%s.%s-%d" % [path, kind, stamp]
	while FileAccess.file_exists(dest):
		stamp += 1
		dest = "%s.%s-%d" % [path, kind, stamp]
	DirAccess.rename_absolute(path, dest)
	return dest


## Training runs used to store a compute share ("frac"), not a run type. A run still in flight is refunded in full
## (its spend is 10^log) so it cannot break the new run types. Missing keys are tolerated.
static func _v1_to_v2(state: Dictionary) -> Dictionary:
	var run: Variant = state.get("run", {})
	if not (run is Dictionary) or not (run.get("layers") is Array) or (run["layers"] as Array).is_empty():
		return state
	var L0: Variant = run["layers"][0]
	if not (L0 is Dictionary):
		return state
	var t: Variant = L0.get("training", {})
	if t is Dictionary and not t.is_empty() and not t.has("type"):
		var cur: Dictionary = L0.get("cur", {})
		var compute := BigNum.from_json(cur["compute"]) if cur.get("compute") is Dictionary else BigNum.new()
		var spent := BigNum.from_float(pow(10.0, float(t.get("log", 0.0))))
		cur["compute"] = compute.add(spent).to_json()
		L0["cur"] = cur
		L0["training"] = {}
	return state
