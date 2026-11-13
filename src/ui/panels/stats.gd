class_name StatsPanel
extends PanelBase
## Statistics overlay: completion, this run, the reset layers, all time and training. Opened from the HUD button or
## Settings > Statistics (the shell's open_stats); Close or Back hides it. Reads only: Records, the persist counters and
## the live state. Every section is aligned rows (label left, value right) under an accent header and a thin rule.

const TABLE_HEAD := ["", "Resets", "Fastest", "Last", "Best", "Holding"]
const LAYER_ART := ["", "funding", "generation", "paradigm", "singularity"]

var _percent: Label
var _overall: ProgressBar
var _headline_scale: Label
var _headline_stage: Label
var _headline_icon: TextureRect
var _headline_line: Label
var _parts := {}   # part id -> {count: Label, bar: ProgressBar}
var _v := {}       # row key -> value Label
var _cells := {}   # layer k -> {resets, fastest, last, gain: Label, icon: TextureRect, holding: Label}


func _build() -> void:
	result_line.hide()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	page.add_child(top)
	var head := PanelKit.label("Statistics", -1, false)
	head.theme_type_variation = &"Heading"
	top.add_child(head)
	top.add_child(PanelKit.button("Close", hide, true))
	var headline := VBoxContainer.new()
	headline.add_theme_constant_override("separation", 0)
	page.add_child(headline)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 4)
	headline.add_child(scale_row)
	var scale_icon := PanelKit.icon("compute", 0.5)
	scale_row.add_child(scale_icon)
	Tip.attach(scale_icon, "Lab scale\nCurrent compute rate (FLOP/s), after all multipliers.")
	var scale_title := PanelKit.label("Lab scale", PanelKit.TEXT, false)
	scale_title.theme_type_variation = &"MicroLabel"
	scale_row.add_child(scale_title)
	_headline_scale = PanelKit.label("", PanelKit.BRIGHT, false)
	_headline_scale.theme_type_variation = &"Value"
	_headline_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(_headline_scale)
	Tip.attach(scale_title, "Lab scale\nThe largest score: current compute output per second.")
	_headline_stage = PanelKit.label("", PanelKit.BRIGHT, false)
	_headline_stage.theme_type_variation = &"MicroLabel"
	_headline_stage.add_theme_color_override("font_color", Fx.col(Fx.ACCENT))
	scale_row.add_child(_headline_stage)
	var stage_row := HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 4)
	headline.add_child(stage_row)
	_headline_icon = PanelKit.icon("equity", 0.5)
	stage_row.add_child(_headline_icon)
	_headline_line = PanelKit.label("", PanelKit.TEXT, false)
	_headline_line.theme_type_variation = &"MicroLabel"
	stage_row.add_child(_headline_line)
	Tip.attach(_headline_stage, "Lab stage\nThe lab's current location, based on its highest producer tier.")
	Tip.attach(_headline_icon, Callable(self, "_headline_tip"))
	Tip.attach(_headline_line, Callable(self, "_headline_tip"))

	var comp := _section("Completion")
	_percent = PanelKit.label("", PanelKit.BRIGHT, false)
	comp.add_child(_percent)
	_overall = PanelKit.bar(PanelKit.GOLD)
	comp.add_child(_overall)
	for part in Records.completion(Game.state)["parts"]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		comp.add_child(box)
		var line := _line(str(part["label"]))
		box.add_child(line["box"])
		var bar := PanelKit.bar(PanelKit.TEAL)
		bar.custom_minimum_size = Vector2(0, 10)
		box.add_child(bar)
		_parts[part["id"]] = {"count": line["value"], "bar": bar}

	var run := _section("This run")
	_row(run, "run_time", "Time played")
	_row(run, "run_resets", "Resets")
	_row(run, "cash_rate", "Cash income")
	_row(run, "compute_rate", "Compute income")
	_row(run, "cash_mult", "Cash multiplier")
	_row(run, "compute_mult", "Compute multiplier")

	_build_layers(_section("Reset layers"))

	var all := _section("All time")
	_row(all, "runs", "Runs started")
	_row(all, "resets", "Resets")
	_row(all, "time", "Time played")
	_row(all, "offline", "Offline time credited")
	_row(all, "bursts", "Deployment burst cash")
	_row(all, "events", "Events resolved")
	_row(all, "papers", "Papers read")
	_row(all, "moonshots", "Moonshots completed")
	_row(all, "upgrades", "Lab upgrades bought")
	_row(all, "launches", "Launches fired")
	_row(all, "news", "News caught")
	_row(all, "evals_passed", "Evals passed")
	_row(all, "evals_failed", "Evals failed")
	_row(all, "landmarks", "Landmarks")
	_row(all, "top_tier", "Highest producer")

	var train := _section("Training")
	_row(train, "trainings", "Training runs")
	_row(train, "failed", "Failed")
	_row(train, "success", "Success rate")
	_row(train, "best_gen", "Best this generation")
	_row(train, "best_all", "Best ever")


## One section: accent header over a thin rule, then its rows. Returns the box the rows go into.
func _section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	page.add_child(box)
	var h := PanelKit.label(title, -1, false)
	h.theme_type_variation = &"Heading"
	box.add_child(h)
	var rule := ColorRect.new()
	rule.color = PanelKit.col(PanelKit.EDGE)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


## Label left (wraps before it widens the page), value right. Returns {box, value}.
func _line(text: String) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var name_l := PanelKit.label(text, PanelKit.TEXT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_stretch_ratio = 2.0
	h.add_child(name_l)
	var v := PanelKit.label("", PanelKit.BRIGHT, false)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_SHRINK_END  # values keep their natural width; the label gives way
	h.add_child(v)
	return {"box": h, "value": v}


func _row(box: Control, key: String, text: String) -> void:
	var line := _line(text)
	box.add_child(line["box"])
	_v[key] = line["value"]


## Per-layer table: layer icon, lifetime resets, fastest cycle, time since last reset, best gain, what it holds.
func _build_layers(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = TABLE_HEAD.size()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in TABLE_HEAD.size():
		grid.add_child(_cell(TABLE_HEAD[i], true))
	for k in range(1, Records.LAYERS + 1):
		var art := TextureRect.new()
		art.texture = Fx.tex_fit("res://assets/legacy/%s.png" % LAYER_ART[k], Vector2i(16, 16))
		art.custom_minimum_size = Vector2(16, 16)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Tip.attach(art, Records.layer_title(Game.state, k))
		var cell := {
			"resets": _cell("", false), "fastest": _cell("", false), "last": _cell("", false),
			"gain": _cell("", false), "icon": PanelKit.icon("cash", 1.0), "holding": _cell("", false),
		}
		_cells[k] = cell
		grid.add_child(art)
		grid.add_child(cell["resets"])
		grid.add_child(cell["fastest"])
		grid.add_child(cell["last"])
		grid.add_child(cell["gain"])
		var hold := HBoxContainer.new()
		hold.alignment = BoxContainer.ALIGNMENT_END
		hold.add_theme_constant_override("separation", 3)
		hold.add_child(cell["icon"])
		hold.add_child(cell["holding"])
		grid.add_child(hold)


## A right-aligned table cell in the micro font. Headers take the accent colour.
func _cell(text: String, accent: bool) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MicroLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", Fx.col(Fx.ACCENT) if accent else PanelKit.col(PanelKit.TEXT))
	return l


func _refresh() -> void:
	var s: GameState = Game.state
	var headline := Rules.headline(s)
	_headline_scale.text = "%s/s" % (headline["scale"] as BigNum).format()
	_headline_stage.text = str(headline["stage_name"])
	_headline_icon.texture = Fx.tex_fit("res://assets/icons/%s.png" % headline["currency"], Vector2i(16, 16))
	_headline_line.text = str(headline["line"])
	_headline_line.add_theme_color_override("font_color", Fx.col(Fx.ACCENT if headline["highlight"] else Fx.MUTED))
	var p := s.persist
	var stats: Dictionary = p["stats"]
	var c := Records.completion(s)
	_percent.text = "%d%% complete" % roundi(float(c["percent"]))
	_overall.max_value = 100.0
	_overall.value = float(c["percent"])
	for part in c["parts"]:
		var row: Dictionary = _parts[part["id"]]
		(row["count"] as Label).text = "%d/%d" % [part["done"], part["total"]]
		var bar := row["bar"] as ProgressBar
		bar.max_value = float(part["total"])
		bar.value = float(part["done"])

	var run_resets := 0
	for k in range(1, Records.LAYERS + 1):
		run_resets += s.resets(k)
	_v["run_time"].text = Records.format_duration(Records.run_seconds(p))
	_v["run_resets"].text = str(run_resets)
	_v["cash_rate"].text = "%s/s" % Game.cash_per_second().format()
	_v["compute_rate"].text = "%s/s" % Game.compute_per_second().format()
	_v["cash_mult"].text = "x%.2f" % Rules.mult(s, "cash")
	_v["compute_mult"].text = "x%.2f" % Rules.mult(s, "compute")

	_refresh_layers(s)

	_v["runs"].text = str(int(stats["runs"]))
	_v["resets"].text = str(int(stats["resets"]))
	_v["time"].text = Records.format_duration(float(stats["time"]))
	_v["offline"].text = Records.format_duration(float(p["records"].get("offline_seconds", 0.0)))
	_v["bursts"].text = BigNum.from_json(p["records"].get("deployment_burst_cash", {})).format()
	_v["events"].text = str(int(stats.get("events", 0)))
	_v["papers"].text = str(int(stats.get("papers", 0)))
	for key in ["moonshots", "upgrades", "launches", "news", "evals_passed", "evals_failed"]:
		_v[key].text = str(int(stats.get(key, 0)))
	_v["landmarks"].text = str(int(stats.get("landmarks", 0)))
	_v["top_tier"].text = _top_tier(s)

	var trains := int(stats.get("trainings", 0))
	var failed := int(stats.get("failed", 0))
	_v["trainings"].text = str(trains)
	_v["failed"].text = str(failed)
	_v["success"].text = PanelKit.pct(float(trains - failed) / trains) if trains > 0 else "-"
	_v["best_gen"].text = "%.2f" % float(s.run["layers"][2]["best"])
	_v["best_all"].text = "%.2f" % float(p["best_all"])


func _headline_tip() -> String:
	return "AGI road\nStage requirements progress and the current ending trajectory." if Game.state.resets(4) > 0 else "Frontier reset\nCurrent layer currency and the gain available on reset. Highlighted when the gain is at least twice your holding."


func _refresh_layers(s: GameState) -> void:
	var p := s.persist
	var now := float(p["stats"]["time"])
	var life: Array = p["lifetime_resets"]
	var fastest: Dictionary = p["records"]["fastest"]
	var gains: Dictionary = p["records"].get("best_gain", {})
	for k in range(1, Records.LAYERS + 1):
		var cell: Dictionary = _cells[k]
		var prev := Sim.reset_preview(s, k)
		var n := int(life[k - 1])
		(cell["resets"] as Label).text = str(n)
		(cell["fastest"] as Label).text = Records.format_duration(float(fastest[str(k)])) if fastest.has(str(k)) else "-"
		(cell["last"] as Label).text = "-" if n == 0 else _ago(now - float(p["records"]["cycle_start"][k]))
		(cell["gain"] as Label).text = (BigNum.from_float(float(gains[str(k)])).format()) if gains.has(str(k)) else "-"
		var cur := str(prev["currency"])
		if cell.get("cur", "") != cur:  # the layer's currency only changes when a save is loaded
			cell["cur"] = cur
			(cell["icon"] as TextureRect).texture = Fx.tex_fit("res://assets/icons/%s.png" % cur, Vector2i(16, 16))
		(cell["holding"] as Label).text = (prev["holding"] as BigNum).format()


## The producer tier with the highest order that has ever been reached.
func _top_tier(s: GameState) -> String:
	var best := ""
	var best_order := -1
	for d in s.db.get_all("producers"):
		if s.persist["records"]["producers"].has(d.id) and int(d.order) > best_order:
			best = str(d.title)
			best_order = int(d.order)
	return best if best != "" else "none yet"


## Coarse age: "45s", "12m", "3h 05m", "5d".
static func _ago(secs: float) -> String:
	var t := int(maxf(secs, 0.0))
	if t < 60:
		return "%ds" % t
	if t < 3600:
		return "%dm" % (t / 60)
	if t < 86400:
		return "%dh %02dm" % [t / 3600, (t % 3600) / 60]
	return "%dd" % (t / 86400)
