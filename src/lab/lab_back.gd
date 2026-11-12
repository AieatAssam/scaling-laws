class_name LabBack
extends Control
## Backdrop in art space, behind the lab. The 320x180 art is extended past its edges (edge rows and columns
## stretched for the garage and city, palette night for space), so the view never shows a bare band.
## Cross-fades when the backdrop changes. Clouds and stars drift; all of it is still under reduce_motion.

const FADE_SECONDS := 0.9
const STARS := 12
const BIG := 2000.0

var view: LabView
var _from := ""
var _to := ""
var _from_o := Vector2.ZERO
var _to_o := Vector2.ZERO
var _fade_t := 1.0
var _t := 0.0


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
	if bd == "garage_sky" or bd == "city":
		_extend(t, o, a)
		return
	draw_rect(Rect2(-BIG, -BIG, BIG * 2.0, BIG * 2.0), LabData.fade(LabData.C_NIGHT, a))
	draw_texture(t, o, Color(1, 1, 1, a))


## Draws the art at o and fills the 3x3 surround with its edge pixels stretched outwards.
func _extend(t: Texture2D, o: Vector2, a: float) -> void:
	var w := float(t.get_width())
	var h := float(t.get_height())
	var xs := [[-BIG, o.x + BIG, 0.0, 1.0], [o.x, w, 0.0, w], [o.x + w, BIG, w - 1.0, 1.0]]
	var ys := [[-BIG, o.y + BIG, 0.0, 1.0], [o.y, h, 0.0, h], [o.y + h, BIG, h - 1.0, 1.0]]
	for xi in 3:
		for yi in 3:
			var dst := Rect2(xs[xi][0], ys[yi][0], xs[xi][1], ys[yi][1])
			var src := Rect2(xs[xi][2], ys[yi][2], xs[xi][3], ys[yi][3])
			draw_texture_rect_region(t, dst, src, Color(1, 1, 1, a))


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
