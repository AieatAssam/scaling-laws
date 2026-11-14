extends SceneTree
## Dev: Play Store graphics. Icon (512x512) and feature graphic (1024x500), both RGB with no alpha.
## Nearest-neighbour only: every scale is an integer or an exact Image.resize with INTERPOLATE_NEAREST.
## Reads only res:// art; writes only the out dir. Never touches the player save.
## $GODOT --path . -s tools/dev_store_graphics.gd -- <out_dir>   (default store/graphics)

const NAVY := Color("0B0E1A")
const AMBER := Color("FFB347")
const TAGLINE := Color("DDE4F0")
const FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const ICON_SIZE := 512
const FEATURE := Vector2i(1024, 500)
const TITLE := "SCALING LAWS"
const TAGLINE_TEXT := "Grow an AI lab, one grant at a time."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "store/graphics"
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(120.0).timeout.connect(quit.bind(1))  # failsafe: a stuck frame must not hang the run
	await process_frame
	_icon(out)
	await _feature(out)
	quit()


## The app icon, scaled down to 512 and composited on the game's navy (the icon has transparent corners).
func _icon(out: String) -> void:
	var src: Image = (load("res://icon/app_icon.png") as Texture2D).get_image()
	src.convert(Image.FORMAT_RGBA8)
	var art := src.duplicate() as Image
	art.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(NAVY)
	img.blend_rect(art, Rect2i(Vector2i.ZERO, Vector2i(ICON_SIZE, ICON_SIZE)), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/icon-512.png" % out)
	print("saved icon-512 %s" % img.get_size())


## Feature graphic: garage sky backdrop (2x, cropped), dimmed; title, tagline; two early lab rooms (2x) on the bottom row.
func _feature(out: String) -> void:
	var vp := SubViewport.new()
	vp.size = FEATURE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = NAVY
	bg.size = Vector2(FEATURE)
	vp.add_child(bg)

	# 640x360 backdrop at 2x is 1280x720; centre-crop to 1024x500 (offset -128, -110).
	var sky := _rect(load("res://assets/backdrops/garage_sky.png"), Vector2(-128, -110), Vector2(1280, 720))
	vp.add_child(sky)

	var dim := ColorRect.new()
	dim.color = Color(NAVY.r, NAVY.g, NAVY.b, 0.6)
	dim.size = Vector2(FEATURE)
	vp.add_child(dim)

	var rooms := ["intern_laptop", "cloud_gpus"]
	var gap := 24.0
	var room_size := Vector2(384, 256)  # 192x128 at 2x
	var x0 := (FEATURE.x - (room_size.x * rooms.size() + gap * (rooms.size() - 1))) / 2.0
	for i in rooms.size():
		var tex = load("res://assets/rooms/%s.png" % rooms[i])
		vp.add_child(_rect(tex, Vector2(x0 + i * (room_size.x + gap), FEATURE.y - room_size.y - 24.0), room_size))

	vp.add_child(_label(TITLE, 56, AMBER, Vector2(0, 64)))
	vp.add_child(_label(TAGLINE_TEXT, 24, TAGLINE, Vector2(0, 150)))

	await _settle()
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != FEATURE:
		push_error("feature captured at %s, expected %s" % [img.get_size(), FEATURE])
	img.save_png("%s/feature-graphic-1024x500.png" % out)
	print("saved feature-graphic-1024x500 %s" % img.get_size())
	vp.queue_free()


func _rect(tex: Texture2D, pos: Vector2, size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.position = pos
	tr.size = size
	return tr


func _label(text: String, size: int, color: Color, pos: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", NAVY)
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.text = text
	label.position = pos
	label.size = Vector2(FEATURE.x, size + 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _settle() -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
