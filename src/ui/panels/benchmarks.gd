class_name BenchmarksPanel
extends Control
## Benchmarks: achievements with a badge. Locked ones show a "?" slot; their reward stays hidden until earned.

var _rows := {}  # id -> {badge, query, title, desc, reward}
var _count: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)
	_count = Label.new()
	_count.theme_type_variation = &"Heading"
	page.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for d in Content.get_all("benchmarks"):
		list.add_child(_row(d))
	var tm := Timer.new()
	tm.wait_time = 0.5
	tm.timeout.connect(_refresh)
	add_child(tm)
	tm.start()
	_refresh()


func _row(d) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(32, 32)
	row.add_child(slot)
	var badge := TextureRect.new()
	badge.texture = Fx.tex("res://assets/badges/%s.png" % d.badge, Vector2i(24, 24))  # fallback at logical size
	badge.custom_minimum_size = Vector2(24, 24)   # logical size; the badge art may be 2x
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(badge)
	var query := Label.new()
	query.text = "?"
	query.theme_type_variation = &"Heading"
	query.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	query.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(query)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long titles wrap at 390px instead of clipping
	text.add_child(title)
	var desc := Label.new()
	desc.theme_type_variation = &"MicroDim"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	var reward := Label.new()
	reward.theme_type_variation = &"MicroDim"
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(reward)
	_rows[d.id] = {"def": d, "badge": badge, "query": query, "title": title, "desc": desc, "reward": reward}
	Tip.attach(row, Callable(self, "_tip").bind(d.id))
	return row


## Earned: title, what it is and its reward. Locked: the requirements only; the reward stays hidden.
func _tip(id: String) -> String:
	var d = Content.get_def("benchmarks", id)
	var got: bool = id in Game.state.persist["benchmarks"]
	if got:
		return "%s\n%s\nEarned. Reward: %s" % [d.title, d.description, Fx.effects_text(d.effects)]
	return "Locked benchmark\nRequires: %s" % PanelText.conditions(d.conditions)


func _refresh() -> void:
	var earned: Array = Game.state.persist["benchmarks"]
	for id in _rows:
		var r: Dictionary = _rows[id]
		var d = r["def"]
		var got: bool = id in earned
		(r["badge"] as TextureRect).visible = got
		(r["query"] as Label).visible = not got
		(r["title"] as Label).text = str(d.title) if got else "???"
		(r["desc"] as Label).text = str(d.description)
		(r["reward"] as Label).text = ("Reward: " + Fx.effects_text(d.effects)) if got else "Reward: ?"
	_count.text = "Earned %d / %d" % [earned.size(), _rows.size()]


func is_unlocked() -> bool:
	return true


func wants_attention() -> bool:
	return false
