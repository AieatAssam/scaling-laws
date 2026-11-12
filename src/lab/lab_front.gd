class_name LabFront
extends Control
## Screen-space effects over the lab: particles, flashes, alarm tint, comet, and the zoom cover.
## Particles aim at the building. Every effect is skipped under reduce_motion; the cover is not (it snaps).

var view: LabView
var _parts: Array[Dictionary] = []
var _flash := 0.0
var _flash_col := LabData.C_WHITE
var _alarm := 0.0
var _amber := 0.0
var _comet := -1.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if view == null:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 1.8)
	_alarm = maxf(0.0, _alarm - delta)
	_amber = maxf(0.0, _amber - delta)
	if _comet >= 0.0:
		_comet += delta * 0.9
		if _comet > 1.0:
			_comet = -1.0
	var i := _parts.size() - 1
	while i >= 0:
		var q := _parts[i]
		q["t"] = float(q["t"]) + delta
		if q["t"] >= q["life"]:
			_parts.remove_at(i)
		else:
			var v: Vector2 = q["v"] + Vector2(0, float(q["g"]) * delta)
			q["v"] = v
			q["p"] = q["p"] + v * delta
		i -= 1
	queue_redraw()


func _draw() -> void:
	if view == null:
		return
	var full := Rect2(Vector2.ZERO, size)
	if _alarm > 0.0:
		draw_rect(full, LabData.fade(LabData.C_RED, 0.2 * (0.5 + 0.5 * sin(_t * 10.0)) * minf(1.0, _alarm)))
	if _amber > 0.0:
		draw_rect(full, LabData.fade(LabData.C_AMBER, 0.12 * minf(1.0, _amber)))
	if _flash > 0.0:
		draw_rect(full, LabData.fade(_flash_col, _flash * 0.5))
	if _comet >= 0.0:
		var head := Vector2(size.x + 40.0, size.y * 0.2).lerp(Vector2(-40.0, size.y * 0.35), _comet)
		for j in 6:
			draw_rect(Rect2(head + Vector2(j * 8.0, -j * 3.0), Vector2(4, 4)), LabData.fade(LabData.C_MINT, 1.0 - float(j) / 6.0))
	var m := view.unit()
	for q in _parts:
		var a := 1.0 - float(q["t"]) / float(q["life"])
		var sz: float = float(q["s"]) * m
		draw_rect(Rect2(q["p"], Vector2(sz, sz)), LabData.fade(q["col"], a))
	if view.cover > 0.0:
		draw_rect(full, LabData.fade(LabData.C_NIGHT, view.cover))


func _add(p: Vector2, v: Vector2, col: Color, s: float, life: float, g: float) -> void:
	_parts.append({"p": p, "v": v, "col": col, "s": s, "life": life, "g": g, "t": 0.0})


## Building-relative art point (dx, dy from the building centre).
func _at(dx: float, dy: float) -> Vector2:
	return view.bld + Vector2(dx, dy)


## Particles burst from an art-space point. Speeds are in view pixels per second.
func burst_art(art: Vector2, cols: Array, n: int, speed: float, g: float, life: float, s := 2.0) -> void:
	if view.reduce:
		return
	var base := view.art_to_view(art)
	for j in n:
		var a := randf() * TAU
		_add(base, Vector2(cos(a), sin(a)) * speed * randf_range(0.4, 1.0), cols[randi() % cols.size()], s, life * randf_range(0.7, 1.3), g)


func _smoke(art: Vector2, n: int) -> void:
	if view.reduce:
		return
	var base := view.art_to_view(art)
	for j in n:
		_add(base + Vector2(randf_range(-6.0, 6.0), 0.0), Vector2(randf_range(-8.0, 8.0), randf_range(-22.0, -12.0)), LabData.C_STEEL, 6.0, 2.4, -4.0)


## Training pass/fail and challenge outcomes: gold flash and sparks on success, smoke on failure.
func on_result(ok: bool) -> void:
	if view.reduce:
		return
	if ok:
		_flash = 0.6
		_flash_col = LabData.C_GOLD
		burst_art(_at(0, -40), [LabData.C_GOLD, LabData.C_MINT], 12, 50.0, 30.0, 1.0)
	else:
		_smoke(_at(-24, -40), 10)


func on_event(category: String) -> void:
	if view.reduce:
		return
	match category:
		"incident", "outage":
			_alarm = 2.5
			burst_art(_at(0, 0), [LabData.C_RED, LabData.C_LRED], 14, 60.0, 30.0, 1.0)
		"media":
			for j in 3:
				burst_art(_at(randf_range(-60.0, 60.0), randf_range(-70.0, 0.0)), [LabData.C_WHITE], 1, 0.0, 0.0, 0.35, 6.0)
			_flash = 0.35
			_flash_col = LabData.C_WHITE
		"breakthrough":
			burst_art(_at(0, -50), [LabData.C_GOLD, LabData.C_WHITE], 18, 50.0, 40.0, 1.2)
		"rival_launch":
			comet()
		"regulation":
			_amber = 1.2
		"poaching":
			burst_art(_at(-60, -20), [LabData.C_LILAC, LabData.C_VIOLET], 10, 40.0, 20.0, 0.9)
		"funding":
			burst_art(_at(0, -20), [LabData.C_GOLD, LabData.C_AMBER], 12, 45.0, 30.0, 1.0)
		_:
			burst_art(_at(0, -10), [LabData.C_MINT], 8, 40.0, 20.0, 0.8)


func confetti() -> void:
	if view.reduce:
		return
	var base := view.art_to_view(_at(0, -40))
	for j in 36:
		_add(base, Vector2(randf_range(-110.0, 110.0), randf_range(-160.0, -60.0)), LabData.CONFETTI[j % LabData.CONFETTI.size()], 3.0, 2.6, 260.0)


func comet() -> void:
	if view.reduce:
		return
	_comet = 0.0
