class_name StatsPanel
extends PanelBase
## Statistics overlay: completion across every system, this run and all time, the fastest cycle of each reset layer and
## lifetime resets. Opened from Settings > Statistics (the shell's open_stats); Close or Back hides it. Reads only:
## Records and the persist counters are kept elsewhere.

var _percent: Label
var _parts := {}        # part id -> {count: Label, bar: ProgressBar}
var _run: Label
var _all: Label
var _fastest: Label
var _lifetime: Label


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	page.add_child(top)
	var head := Label.new()
	head.text = "Statistics"
	head.theme_type_variation = &"Heading"
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	top.add_child(PanelKit.button("Close", hide, true))

	page.add_child(PanelKit.label("Completion", PanelKit.GOLD))
	_percent = PanelKit.label("", PanelKit.BRIGHT)
	page.add_child(_percent)
	for part in Records.completion(Game.state)["parts"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		page.add_child(row)
		var name_lbl := PanelKit.label(str(part["label"]), PanelKit.TEXT, false)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var count := PanelKit.label("", PanelKit.MUTED, false)
		row.add_child(count)
		var bar := PanelKit.bar(PanelKit.TEAL)
		bar.custom_minimum_size = Vector2(0, 10)
		page.add_child(bar)
		_parts[part["id"]] = {"count": count, "bar": bar}

	page.add_child(PanelKit.label("This run", PanelKit.GOLD))
	_run = PanelKit.label("", PanelKit.TEXT)
	page.add_child(_run)

	page.add_child(PanelKit.label("All time", PanelKit.GOLD))
	_all = PanelKit.label("", PanelKit.TEXT)
	page.add_child(_all)

	page.add_child(PanelKit.label("Fastest cycle per reset layer", PanelKit.GOLD))
	_fastest = PanelKit.label("", PanelKit.TEXT)
	page.add_child(_fastest)

	page.add_child(PanelKit.label("Lifetime resets", PanelKit.GOLD))
	_lifetime = PanelKit.label("", PanelKit.TEXT)
	page.add_child(_lifetime)


func _refresh() -> void:
	var s: GameState = Game.state
	var p := s.persist
	var c := Records.completion(s)
	_percent.text = "%d%% complete" % roundi(float(c["percent"]))
	for part in c["parts"]:
		var row: Dictionary = _parts[part["id"]]
		(row["count"] as Label).text = "%d/%d" % [part["done"], part["total"]]
		var bar := row["bar"] as ProgressBar
		bar.max_value = float(part["total"])
		bar.value = float(part["done"])

	var run_resets := 0
	var run_lines := PackedStringArray()
	for k in range(1, Records.LAYERS + 1):
		run_resets += s.resets(k)
		run_lines.append("%s ×%d" % [Records.layer_title(s, k), s.resets(k)])
	_run.text = "Time played %s · Resets %d\n%s" % [Records.format_duration(Records.run_seconds(p)), run_resets,
		", ".join(run_lines)]

	var stats: Dictionary = p["stats"]
	_all.text = "Runs %d · Resets %d · Trainings %d · Events %d\nTime played %s" % [int(stats["runs"]),
		int(stats["resets"]), int(stats["trainings"]), int(stats["events"]),
		Records.format_duration(float(stats["time"]))]

	var fastest: Dictionary = p["records"]["fastest"]
	var fast_lines := PackedStringArray()
	for k in range(1, Records.LAYERS + 1):
		var t := "not yet" if not fastest.has(str(k)) else Records.format_duration(float(fastest[str(k)]))
		fast_lines.append("%s  %s" % [Records.layer_title(s, k), t])
	_fastest.text = "\n".join(fast_lines)

	var life: Array = p["lifetime_resets"]
	var life_lines := PackedStringArray()
	for k in range(1, Records.LAYERS + 1):
		life_lines.append("%s ×%d" % [Records.layer_title(s, k), int(life[k - 1])])
	_lifetime.text = "\n".join(life_lines)
