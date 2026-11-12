class_name GoalRail
extends HBoxContainer
## One-line "Next" rail under the HUD: the nearest goal, a thin progress bar and the percent.
## A tap cycles the top three goals. The tooltip explains the goal and what it rewards.
## Locked benchmarks show their requirements, never their name or reward.

const TOP := 3
const RAIL_H := 14.0
const REFRESH := 0.25

var _goals: Array = []
var _index := 0
var _title: Label
var _bar: ProgressBar
var _pct: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, RAIL_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_title = PanelKit.label("", -1, false)
	_title.theme_type_variation = &"MicroLabel"
	_title.clip_text = true
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_title)
	_bar = PanelKit.bar(PanelKit.TEAL)
	_bar.max_value = 100.0
	_bar.custom_minimum_size = Vector2(64, 6)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_pct = Label.new()
	_pct.theme_type_variation = &"MicroDim"
	_pct.custom_minimum_size = Vector2(28, 0)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pct)
	Tip.attach(self, Callable(self, "_tip"))
	PanelKit.timer(self, _refresh)
	_refresh()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		_index += 1
		_refresh()
		accept_event()


func _refresh() -> void:
	_goals = Rules.next_goals(Game.state, TOP)
	if _goals.is_empty():
		_title.text = "Next: all goals met"
		_bar.value = 100.0
		_pct.text = "100%"
		return
	var g := _current()
	var p := clampf(float(g["progress"]), 0.0, 1.0)
	_title.text = _label(g)
	_bar.value = p * 100.0
	_pct.text = "%d%%" % floori(p * 100.0)


func _current() -> Dictionary:
	return _goals[posmod(_index, _goals.size())]


func _label(g: Dictionary) -> String:
	if g["kind"] == "benchmark":
		return "Benchmark: " + _requires(g)
	return "Next: %s" % g["title"]


## Requirements of a benchmark or AGI stage, as text. Empty for other goal kinds.
func _requires(g: Dictionary) -> String:
	var type := "benchmarks" if g["kind"] == "benchmark" else "agi_stages"
	var d = Content.get_def(type, g["id"])
	return PanelText.conditions(d.conditions) if d != null else ""


func _tip() -> String:
	if _goals.is_empty():
		return "All goals met\nNothing left to chase for now."
	var g := _current()
	var pct := "Progress: %d%%" % floori(clampf(float(g["progress"]), 0.0, 1.0) * 100.0)
	match g["kind"]:
		"benchmark":
			return "\n".join([
				"Next benchmark", str(g["hint"]), "Requires: " + _requires(g),
				"Reward hidden until earned.", pct])
		"agi":
			return "\n".join([str(g["title"]), str(g["hint"]), "Requires: " + _requires(g), pct])
	return "\n".join([str(g["title"]), str(g["hint"]), pct])
