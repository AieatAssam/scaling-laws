class_name LabBack
extends Control
## Backdrop in art space, behind the lab. The art is extended past its edges so the view never shows a bare band:
## garage and city stretch their edge rows and columns outwards; space backdrops fill each side with that edge's most
## common colour (stretched texels streak on starfields). Colours are sampled from the art at runtime.
## Cross-fades when the backdrop changes. Clouds and stars drift; all of it is still under reduce_motion.

const FADE_SECONDS := 0.9
const STARS := 12
const BIG := 2000.0
const EDGE_SAMPLES := 48  # samples per edge when picking its most common colour

var view: LabView
var _from := ""
var _to := ""
var _from_o := Vector2.ZERO
var _to_o := Vector2.ZERO
var _fade_t := 1.0
var _t := 0.0
var _edges := {}  # texture instance id -> [top, bottom, left, right] edge colours


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if view == null:
		return
	_t += delta
	var target := view.backdrop_name()
	if target != _to:
		_from = _to
		_from_o = _to_o
		_to = target
		_to_o = view.backdrop_origin()
		_fade_t = 0.0 if _from != "" and not view.reduce else 1.0
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + delta / FADE_SECONDS)
	queue_redraw()


func _draw() -> void:
	if view == null or _to == "":
		return
	draw_set_transform(view.art_origin(), 0.0, Vector2.ONE * view.unit())
	if _fade_t < 1.0 and _from != "":
		_backdrop(_from, _from_o, 1.0)
	_backdrop(_to, _to_o, _fade_t)
	_ambient()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _backdrop(bd: String, o: Vector2, a: float) -> void:
	var t := LabData.tex("res://assets/backdrops/%s.png" % bd)
	if t == null:
		draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, BIG * 2.0), LabData.fade(LabData.C_DARK, a))
		return
	_extend(t, o, a, bd != "garage_sky" and bd != "city")


## Draws the art at o (logical size LabData.BACKDROP, whatever its texel density) and fills the surround. Destination
## rects are logical; source rects are in texels. Stretched (garage, city): the 3x3 cells use the edge texels.
## Flat (space): the art is drawn alone and the four sides are bands of that edge's most common colour.
func _extend(t: Texture2D, o: Vector2, a: float, flat := false) -> void:
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var w := LabData.BACKDROP.x
	var h := LabData.BACKDROP.y
	if flat:
		var e := _edge_colours(t)
		draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, BIG + o.y), LabData.fade(e[0], a))
		draw_rect(Rect2(-BIG, o.y + h, BIG * 2.0, BIG), LabData.fade(e[1], a))
		draw_rect(Rect2(-BIG, o.y, BIG + o.x, h), LabData.fade(e[2], a))
		draw_rect(Rect2(o.x + w, o.y, BIG, h), LabData.fade(e[3], a))
		draw_texture_rect_region(t, Rect2(o, Vector2(w, h)), Rect2(0, 0, tw, th), Color(1, 1, 1, a))
		return
	var xs := [[-BIG, o.x + BIG, 0.0, 1.0], [o.x, w, 0.0, tw], [o.x + w, BIG, tw - 1.0, 1.0]]
	var ys := [[-BIG, o.y + BIG, 0.0, 1.0], [o.y, h, 0.0, th], [o.y + h, BIG, th - 1.0, 1.0]]
	for xi in 3:
		for yi in 3:
			var dst := Rect2(xs[xi][0], ys[yi][0], xs[xi][1], ys[yi][1])
			var src := Rect2(xs[xi][2], ys[yi][2], xs[xi][3], ys[yi][3])
			draw_texture_rect_region(t, dst, src, Color(1, 1, 1, a))


## [top, bottom, left, right] most common colour along each edge, quantised to 1/32 per channel. Cached per texture.
func _edge_colours(t: Texture2D) -> Array:
	var key := t.get_instance_id()
	if _edges.has(key):
		return _edges[key]
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var out := []
	for side in 4:
		var seen := {}
		for i in EDGE_SAMPLES:
			var f := (float(i) + 0.5) / float(EDGE_SAMPLES)
			var p: Vector2i
			match side:
				0: p = Vector2i(int(f * w), 0)
				1: p = Vector2i(int(f * w), h - 1)
				2: p = Vector2i(0, int(f * h))
				_: p = Vector2i(w - 1, int(f * h))
			var c := img.get_pixelv(p)
			var q := Color(roundf(c.r * 32.0) / 32.0, roundf(c.g * 32.0) / 32.0, roundf(c.b * 32.0) / 32.0)
			seen[q] = seen.get(q, 0) + 1
		var best := Color.BLACK
		var best_n := -1
		for q in seen:
			if seen[q] > best_n:
				best = q
				best_n = seen[q]
		out.append(best)
	_edges[key] = out
	return out


func _ambient() -> void:
	if _to == "orbit" or _to == "swarm" or _to == "universe":
		for j in STARS:
			var p := _to_o + Vector2(fmod(float(j) * 97.0, 320.0), fmod(float(j) * 53.0 + 20.0, 170.0))
			var tw := 0.8 if view.reduce else 0.45 + 0.55 * sin(_t * 2.0 + float(j) * 1.7)
			draw_rect(Rect2(p, Vector2(1, 1)), LabData.fade(LabData.C_WHITE, tw))
	elif not view.reduce:
		for c in 3:
			var x := fmod(_t * 5.0 + float(c) * 130.0, 400.0) - 60.0
			var y := 22.0 + float(c) * 20.0
			draw_rect(Rect2(x, y, 28, 6), LabData.fade(LabData.C_SLATE, 0.35))
			draw_rect(Rect2(x + 6.0, y - 3.0, 14, 4), LabData.fade(LabData.C_SLATE, 0.35))
