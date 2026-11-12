class_name Fx
extends RefCounted
## Shared UI helpers: palette roles, texture fallback, reduce_motion, effect text, pop tween.

## Mirror of art/palette.hex (index = 0-based line number). Keep in sync.
const PAL := [
	"0B0E1A", "141A2E", "1E2644", "2B3360", "3D3F7A", "5B3C88", "7D4FA8", "A77BC9",
	"1B3A4B", "0F5E63", "137E7A", "1FA7A1", "3FD6CF", "A6F3EC", "F2FBF9", "B9C6D6",
	"7F8BA3", "4A5468", "2E3646", "FFB347", "F59E2B", "B8651B", "FFE08A", "6B3A1E",
	"9C5A2E", "2F8F4E", "5FD17A", "17472E", "C8362F", "FF6B6B", "E8E2D0", "7A1E2B",
]

# Roles (palette indices).
const BG := 0
const PANEL := 1
const RAISED := 2
const BTN := 3
const BTN_HOVER := 4
const BTN_PRESSED := 5
const ACCENT := 12
const INK := 14
const TEXT := 15
const MUTED := 16
const BORDER := 17
const DISABLED := 18
const GOLD := 19
const GREEN := 26
const RED := 29
## Reset colour per layer, index = reset layer (1 funding .. 4 singularity).
const LAYER_COLORS := [BG, 11, 6, 20, 28]


static func col(i: int) -> Color:
	return Color.html("#" + PAL[i])


## Autoload node by name. Looked up at runtime so this script also compiles under `-s` tools.
static func svc(name: String):
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null(name)


static func reduce_motion() -> bool:
	var g = svc("Game")
	return g != null and bool(g.state.persist["settings"].get("reduce_motion", false))


## Texture at `path`, or a flat palette rect when the file is missing.
static func tex(path: String, size := Vector2i(16, 16)) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(col(PANEL))
	return ImageTexture.create_from_image(img)


## Nearest-neighbour upscale of a texture by an integer factor (keeps pixel art crisp).
static func tex_x(path: String, factor: int) -> Texture2D:
	var img := tex(path).get_image()
	img.resize(img.get_width() * factor, img.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## Attention dot: steady when reduce_motion is on, a slow alpha pulse otherwise.
static func set_attention(dot: CanvasItem, on: bool) -> void:
	var want := on and not reduce_motion()
	var t: Tween = dot.get_meta("pulse") if dot.has_meta("pulse") else null
	if t != null and not want:
		t.kill()
		dot.remove_meta("pulse")
		t = null
	dot.modulate.a = 1.0
	dot.visible = on
	if want and t == null and dot.is_inside_tree():
		t = dot.create_tween().set_loops()
		t.tween_property(dot, "modulate:a", 0.3, 0.6)
		t.tween_property(dot, "modulate:a", 1.0, 0.6)
		dot.set_meta("pulse", t)


## One-shot scale pulse on `ctrl`. Skipped under reduce_motion.
static func pop(ctrl: Control, amount := 1.12) -> void:
	if reduce_motion() or not ctrl.is_inside_tree():
		return
	if ctrl.has_meta("pop_tween"):
		(ctrl.get_meta("pop_tween") as Tween).kill()
	ctrl.pivot_offset = ctrl.size * 0.5
	var t := ctrl.create_tween()
	t.tween_property(ctrl, "scale", Vector2.ONE * amount, 0.06)
	t.tween_property(ctrl, "scale", Vector2.ONE, 0.12)
	ctrl.set_meta("pop_tween", t)


## Compact magnitude text for a plain float (suffix notation via BigNum).
static func num(v: float) -> String:
	return BigNum.from_float(absf(v)).format()


## Short human text for one effect dict (see docs/API.md effect schema).
static func effect_text(e: Dictionary) -> String:
	var v := float(e.get("value", 0.0))
	match e.get("type", ""):
		"add_currency":
			return "%s%s %s" % ["+" if v >= 0.0 else "-", num(v), e["id"]]
		"add_debt":
			return "+%s debt" % num(v)
		"add_slider":
			return "alignment %+d%%" % roundi(v * 100.0)
		"add_flag":
			return "flag %s" % e["id"]
		"timed_mod":
			return "x%s %s for %ds" % [v, e["key"], int(e.get("seconds", 0.0))]
		"run_mult":
			return "x%s %s this run" % [v, e["key"]]
		"perm_mult":
			return "x%s %s forever" % [v, e["key"]]
		"rival_progress":
			return "%s %+d" % [e["id"], roundi(v)]
	return str(e.get("type", "?"))


static func effects_text(list: Array) -> String:
	var parts := PackedStringArray()
	for e in list:
		parts.append(effect_text(e))
	return ", ".join(parts)


static func layer_def(k: int):
	var c = svc("Content")
	if c == null:
		return null
	for d in c.get_all("layers"):
		if d.index == k:
			return d
	return null
