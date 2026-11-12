extends Node
## Scans res://content/<type>/**/*.tres at startup. Folder name = type; any .tres whose root is a ContentDef is indexed by id.

const ROOT := "res://content"

var _defs: Dictionary = {}   # type -> { id -> ContentDef }
var _sorted: Dictionary = {} # type -> Array[ContentDef], sorted by (order, id)


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_sorted.clear()
	_scan(ROOT, "")
	for type in _defs:
		var list: Array = _defs[type].values()
		list.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))
		_sorted[type] = list


func get_def(type: String, id: String) -> ContentDef:
	return _defs.get(type, {}).get(id)


func get_all(type: String) -> Array:
	return _sorted.get(type, [])


func types() -> Array:
	return _defs.keys()


func _sort_key(d) -> String:
	return "%06d:%s" % [d.order if "order" in d else 0, d.id]


func _scan(dir: String, type: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + sub, type if type != "" else sub)
	if type == "":
		return
	for file in DirAccess.get_files_at(dir):
		# Exported builds list .remap stubs; load() of the trimmed path resolves them.
		var name: String = file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res = load(dir + "/" + name)
		if not (res is ContentDef) or res.id == "":
			push_error("Content: %s/%s is not a ContentDef with an id" % [dir, name])
			continue
		var bucket: Dictionary = _defs.get_or_add(type, {})
		if bucket.has(res.id):
			push_error("Content: duplicate %s id '%s' (%s)" % [type, res.id, name])
			continue
		bucket[res.id] = res
