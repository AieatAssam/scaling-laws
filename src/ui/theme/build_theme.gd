extends SceneTree
## Dev tool: regenerates src/ui/theme/pixel_theme.tres. Every colour is a palette role.
## Run after `--import`: $GODOT --headless --path . -s src/ui/theme/build_theme.gd

const OUT := "res://src/ui/theme/pixel_theme.tres"
const FONT := "res://assets/fonts/PressStart2P-Regular.ttf"


func _init() -> void:
	if not _palette_matches():
		push_error("build_theme: Fx.PAL differs from art/palette.hex; fix the mirror first")
		quit(1)
		return
	var err := ResourceSaver.save(_build(), OUT)
	print("build_theme: saved %s (err %d)" % [OUT, err])
	quit(0 if err == OK else 1)


func _palette_matches() -> bool:
	var hex := PackedStringArray()
	for line in FileAccess.get_file_as_string("res://art/palette.hex").split("\n", false):
		var t := line.strip_edges().to_upper()
		if t != "":
			hex.append(t)
	return hex == PackedStringArray(Fx.PAL)


func _box(bg: int, border := -1, margin := Vector2(6, 4)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = false
	sb.bg_color = Fx.col(bg)
	if border >= 0:
		sb.border_color = Fx.col(border)
		sb.set_border_width_all(2)
	else:
		sb.set_border_width_all(0)
	sb.content_margin_left = margin.x
	sb.content_margin_right = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_bottom = margin.y
	return sb


func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _img_tex(w: int, h: int, fill: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Fx.col(fill))
	return ImageTexture.create_from_image(img)


func _checkbox_tex(on: bool) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Fx.col(Fx.BORDER))
	img.fill_rect(Rect2i(2, 2, 8, 8), Fx.col(Fx.BTN))
	if on:
		img.fill_rect(Rect2i(4, 4, 4, 4), Fx.col(Fx.ACCENT))
	return ImageTexture.create_from_image(img)


func _build() -> Theme:
	var t := Theme.new()

	# Font: pixel face. Antialiasing and hinting are off in its .import file, so glyph edges stay hard.
	t.default_font = load(FONT)
	t.default_font_size = 16

	# Labels and type variations.
	t.set_color("font_color", "Label", Fx.col(Fx.TEXT))
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", Fx.col(Fx.MUTED))
	t.set_type_variation("Heading", "Label")
	t.set_color("font_color", "Heading", Fx.col(Fx.ACCENT))
	t.set_type_variation("Value", "Label")
	t.set_color("font_color", "Value", Fx.col(Fx.GOLD))
	# 8px text (the font's native grid) for HUD rates and effect hints.
	t.set_type_variation("MicroLabel", "Label")
	t.set_font_size("font_size", "MicroLabel", 8)
	t.set_type_variation("MicroDim", "Label")
	t.set_font_size("font_size", "MicroDim", 8)
	t.set_color("font_color", "MicroDim", Fx.col(Fx.MUTED))

	# Buttons.
	t.set_stylebox("normal", "Button", _box(Fx.BTN, Fx.BORDER))
	t.set_stylebox("hover", "Button", _box(Fx.BTN_HOVER, Fx.BORDER))
	t.set_stylebox("pressed", "Button", _box(Fx.BTN_PRESSED, Fx.BORDER))
	t.set_stylebox("hover_pressed", "Button", _box(Fx.BTN_PRESSED, Fx.BORDER))
	t.set_stylebox("disabled", "Button", _box(Fx.DISABLED, Fx.BORDER))
	t.set_stylebox("focus", "Button", _empty())
	t.set_color("font_color", "Button", Fx.col(Fx.TEXT))
	t.set_color("font_hover_color", "Button", Fx.col(Fx.INK))
	t.set_color("font_pressed_color", "Button", Fx.col(Fx.INK))
	t.set_color("font_hover_pressed_color", "Button", Fx.col(Fx.INK))
	t.set_color("font_focus_color", "Button", Fx.col(Fx.TEXT))
	t.set_color("font_disabled_color", "Button", Fx.col(Fx.MUTED))

	# Tab buttons: a pressed toggle is the selected tab.
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", _box(Fx.PANEL, Fx.BORDER))
	t.set_stylebox("hover", "TabButton", _box(Fx.BTN_HOVER, Fx.BORDER))
	t.set_stylebox("pressed", "TabButton", _box(Fx.ACCENT, Fx.BORDER))
	t.set_stylebox("hover_pressed", "TabButton", _box(Fx.ACCENT, Fx.BORDER))
	t.set_color("font_pressed_color", "TabButton", Fx.col(Fx.BG))
	t.set_color("font_hover_pressed_color", "TabButton", Fx.col(Fx.BG))

	# Micro buttons: 8px text, for dense choice lists.
	t.set_type_variation("MicroButton", "Button")
	t.set_font_size("font_size", "MicroButton", 8)

	# Panels.
	for type in ["Panel", "PanelContainer", "PopupPanel"]:
		t.set_stylebox("panel", type, _box(Fx.PANEL, Fx.BORDER, Vector2(8, 6)))

	# Progress bars.
	t.set_stylebox("background", "ProgressBar", _box(Fx.RAISED, Fx.BORDER, Vector2(0, 0)))
	t.set_stylebox("fill", "ProgressBar", _box(Fx.ACCENT, -1, Vector2(0, 0)))
	t.set_color("font_color", "ProgressBar", Fx.col(Fx.TEXT))

	# Sliders.
	t.set_stylebox("slider", "HSlider", _box(Fx.RAISED, Fx.BORDER, Vector2(0, 0)))
	t.set_stylebox("grabber_area", "HSlider", _box(Fx.ACCENT, -1, Vector2(0, 0)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Fx.INK, -1, Vector2(0, 0)))
	t.set_stylebox("focus", "HSlider", _empty())
	t.set_icon("grabber", "HSlider", _img_tex(8, 12, Fx.BORDER))
	t.set_icon("grabber_highlight", "HSlider", _img_tex(8, 12, Fx.INK))
	t.set_icon("grabber_disabled", "HSlider", _img_tex(8, 12, Fx.DISABLED))

	# Check boxes: no frame styles, the palette icons carry the state.
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(s, "CheckBox", _empty())
	t.set_icon("checked", "CheckBox", _checkbox_tex(true))
	t.set_icon("unchecked", "CheckBox", _checkbox_tex(false))
	t.set_icon("checked_disabled", "CheckBox", _checkbox_tex(true))
	t.set_icon("unchecked_disabled", "CheckBox", _checkbox_tex(false))
	t.set_color("font_color", "CheckBox", Fx.col(Fx.TEXT))
	t.set_color("font_hover_color", "CheckBox", Fx.col(Fx.INK))
	t.set_color("font_pressed_color", "CheckBox", Fx.col(Fx.INK))
	t.set_color("font_disabled_color", "CheckBox", Fx.col(Fx.MUTED))
	t.set_constant("h_separation", "CheckBox", 8)

	# Scroll containers: flat track, bar-coloured grabber, no focus ring.
	t.set_stylebox("panel", "ScrollContainer", _empty())
	t.set_stylebox("focus", "ScrollContainer", _empty())
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(Fx.BG, -1, Vector2(4, 0)))
		t.set_stylebox("scroll_focus", bar, _box(Fx.BG, -1, Vector2(4, 0)))
		t.set_stylebox("grabber", bar, _box(Fx.BTN, -1, Vector2(4, 0)))
		t.set_stylebox("grabber_highlight", bar, _box(Fx.BTN_HOVER, -1, Vector2(4, 0)))
		t.set_stylebox("grabber_pressed", bar, _box(Fx.BTN_PRESSED, -1, Vector2(4, 0)))

	return t
