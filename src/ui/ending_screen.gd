extends Control
## Full-screen overlay for a finished run. Shown on Game.ending_reached (and at startup if the saved run is already over).
## "Start a new legacy" calls Game.new_run; "Back to the lab" dismisses it and play carries on.

var _art: TextureRect
var _title: Label
var _desc: Label
var _result: Label
var _again: Button

## Emitted once when the overlay is dismissed (back to the lab, or a new legacy started). The shell's modal queue waits on it.
signal closed


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = PanelKit.col(PanelKit.BG)
	shade.modulate.a = 1.0  # opaque: the lab HUD behind must not show through the headline
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var page := PanelKit.scroll_page(self)

	var head := PanelKit.label("Run over", PanelKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(head)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(_art)
	_title = PanelKit.label("", PanelKit.BRIGHT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_title)
	_desc = PanelKit.label("", PanelKit.TEXT)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_desc)
	_result = PanelKit.label("", PanelKit.MUTED)
	page.add_child(_result)
	_again = PanelKit.button("Start a new legacy", func() -> void: _new_run(), true)
	page.add_child(_again)
	var back := PanelKit.button("Back to the lab", _close, true)
	page.add_child(back)
	resized.connect(_fit_art)


## Shows the overlay for ending `id`. Called by the shell after add_child.
func show_ending(id: String) -> void:
	var d = Content.get_def("endings", id)
	_title.text = d.title if d != null else id
	_desc.text = d.description if d != null else ""
	_art.texture = load(PanelKit.ENDING % id) if ResourceLoader.exists(PanelKit.ENDING % id) else null
	_result.text = ""
	_fit_art()
	visible = true
	move_to_front()


## The art (320x180, 16:9) fills the page width, capped at 45% of the screen height so the buttons stay on screen.
func _fit_art() -> void:
	var w := minf(size.x - 2.0 * PanelKit.GUTTER, size.y * 0.45 * 16.0 / 9.0)
	var h := floorf(w * 9.0 / 16.0)
	_art.custom_minimum_size = Vector2(floorf(w), h)


## Starts a new legacy; the overlay frees itself only once the run actually restarts.
func _new_run() -> void:
	var r: Dictionary = Game.new_run()
	if r.get("ok", false):
		_close()
	else:
		_result.text = str(r.get("reason", "Failed."))
		_result.add_theme_color_override("font_color", PanelKit.col(PanelKit.RED))


func _close() -> void:
	closed.emit()
	queue_free()
