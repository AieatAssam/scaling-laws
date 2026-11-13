class_name PanelKit
## Shared widget builders, palette access and feedback tweens for the progression panels.

const ICON := "res://assets/icons/%s.png"
const WORKER := "res://assets/workers/%s.png"
const LEGACY := "res://assets/legacy/%s.png"
const ENDING := "res://assets/endings/%s.png"
const GUTTER := 12
const TOUCH_H := 36.0

# Indices into art/palette.hex (0-based line order).
const BG := 0
const PANEL := 1
const EDGE := 3
const DIM := 17
const MUTED := 16
const TEXT := 15
const BRIGHT := 14
const TEAL := 11
const CYAN := 12
const AMBER := 19
const GOLD := 22
const GREEN := 26
const RED := 29
const LILAC := 7

static var _pal: Array[Color] = []


static func col(i: int) -> Color:
	if _pal.is_empty():
		for line in FileAccess.get_file_as_string("res://art/palette.hex").split("\n"):
			var hex := line.strip_edges()
			if hex.length() == 6:
				_pal.append(Color.html("#" + hex))
	return _pal[i]


static func reduce_motion() -> bool:
	return bool(Game.state.persist["settings"].get("reduce_motion", false))


## Scrollable page with a 12px gutter. Returns the VBox to add content to.
static func scroll_page(parent: Control) -> VBoxContainer:
	var sc := DragScroll.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, GUTTER)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v


## Section header (icon + title) followed by a VBox the caller fills.
static func section(parent: Container, title: String, icon_name: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	if icon_name != "":
		head.add_child(icon(icon_name))
	head.add_child(label(title, BRIGHT))
	box.add_child(head)
	return box


## Bordered background for a group of rows.
static func style_card(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col(PANEL)
	sb.border_color = col(EDGE)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)


static func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_card(p)
	return p


static func label(text: String, color: int = -1, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color >= 0:
		l.add_theme_color_override("font_color", col(color))
	return l


## 8 px muted caption: descriptions, status and effect lines. Titles and values stay 16 px.
static func caption(text: String = "") -> Label:
	var l := label(text)
	l.theme_type_variation = &"MicroDim"
	return l


static func button(text: String, on_press: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, TOUCH_H)
	b.clip_text = true   # long labels shrink to the panel instead of widening it
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func icon(name: String, scale: float = 2.0, folder: String = ICON) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(folder % name)
	r.custom_minimum_size = Vector2(16, 16) * scale
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


static func bar(color: int = TEAL) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = col(color)
	p.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = col(PANEL)
	back.border_color = col(EDGE)
	back.set_border_width_all(1)
	p.add_theme_stylebox_override("background", back)
	return p


static func hms(seconds: float) -> String:
	var t := int(maxf(seconds, 0.0))
	if t >= 3600:
		return "%dh %02dm" % [t / 3600, (t % 3600) / 60]
	return "%d:%02d" % [t / 60, t % 60]


static func pct(f: float) -> String:
	return "%d%%" % roundi(f * 100.0)


## Small scale pop on purchases. Skipped when reduce_motion is on.
static func pop(c: Control) -> void:
	if reduce_motion() or not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(1.08, 1.08), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.12)


## Brief brightness flash, e.g. for a result line. Skipped when reduce_motion is on.
static func flash(c: CanvasItem) -> void:
	if reduce_motion() or not c.is_inside_tree():
		return
	c.modulate = Color(1.6, 1.6, 1.6)
	var t := c.create_tween()
	t.tween_property(c, "modulate", Color.WHITE, 0.3)


## Adds a 0.25 s refresh timer that calls `on_tick`. The only per-frame-ish work the panels do.
static func timer(parent: Node, on_tick: Callable) -> void:
	var t := Timer.new()
	t.wait_time = 0.25
	t.timeout.connect(on_tick)
	parent.add_child(t)
	t.start()
