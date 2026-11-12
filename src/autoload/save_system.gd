extends Node
## Versioned JSON save. File = {"version": VERSION, "state": <GameState.to_dict()>}.

const VERSION := 1
const DEFAULT_PATH := "user://save.json"


## Writes `state` (a plain Dictionary from GameState.to_dict) to `path`. Returns true on success.
func save(state: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": VERSION, "state": state}, "", true, true))
	return true


## Returns the saved state Dictionary (migrated to the current version), or {} if missing or unreadable.
func load_data(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not parsed.has("state"):
		push_error("SaveSystem: %s is not a valid save" % path)
		return {}
	return migrate(parsed)


func delete(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Upgrades an older wrapper to VERSION. Add one `if v < N:` block per schema change.
func migrate(wrapper: Dictionary) -> Dictionary:
	var v := int(wrapper.get("version", 0))
	if v > VERSION:
		push_error("SaveSystem: save version %d is newer than %d" % [v, VERSION])
		return {}
	var state: Dictionary = wrapper["state"]
	# if v < 2: state = _v1_to_v2(state)
	return state
