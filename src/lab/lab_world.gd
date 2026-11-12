class_name LabWorld
extends Control
## Art-space drawing of the lab: ground, floors and roofs, exterior set pieces, legacy props, workers.
## Walking and blinking stop under reduce_motion; the lab itself is drawn the same either way.

const WALK_SPEED := 14.0
const WALK_MIN := 8.0          # workers stay inside the ground-floor room (art x 4..100)
const WALK_MAX := 80.0

var view: LabView
var _workers: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if view == null:
		return
	_t += delta
	_sync_staff()
	if not view.reduce:
		_walk(delta)
	queue_redraw()


## One worker per hired head, capped per role. Only changes allocate.
func _sync_staff() -> void:
	for role in LabData.ROLES:
		var want := mini(int(view.staff.get(role, 0)), LabData.MAX_WORKERS)
		var n := 0
		for w in _workers:
			if w["role"] == role:
				n += 1
		while n < want:
			_workers.append({"role": role, "x": randf_range(WALK_MIN, WALK_MAX), "dir": 1.0 if randf() < 0.5 else -1.0, "pause": 0.0})
			n += 1
		for j in range(_workers.size() - 1, -1, -1):
			if n > want and _workers[j]["role"] == role:
				_workers.remove_at(j)
				n -= 1


func _walk(delta: float) -> void:
	for w in _workers:
		if w["pause"] > 0.0:
			w["pause"] = w["pause"] - delta
			continue
		var x: float = w["x"] + float(w["dir"]) * WALK_SPEED * delta
		if x < WALK_MIN or x > WALK_MAX:
			x = clampf(x, WALK_MIN, WALK_MAX)
			w["dir"] = -float(w["dir"])
			w["pause"] = 0.8 + randf() * 1.5
		w["x"] = x


func _draw() -> void:
	if view == null:
		return
	draw_set_transform(view.art_origin(), 0.0, Vector2.ONE * view.unit())
	var c := view.counts()
	var stage := view.shown_stage
	if stage <= 1:
		# Solid earth under the ground strip, so the backdrop's lower third never shows through below it.
		draw_rect(Rect2(-1040, LabData.GY + LabData.GROUND_H - 1, 2600, 600), Color("6B3A1E"))
		for gx in range(-1040, 1456, 104):
			LabData.draw_art(self, LabData.GROUND_PNG, Vector2(float(gx), LabData.GY), Vector2(LabData.FLOOR.x, LabData.GROUND_H))
	for f in 6:
		if c[f] <= 0:
			continue
		var bt: float = view.build_t[f]
		var fall := view.fall_p(f)
		var a := bt * (1.0 - fall)
		if a <= 0.0:
			continue
		var o := LabData.floor_origin(f) + Vector2(0, -20.0 * (1.0 - bt) + 140.0 * fall)
		LabData.draw_art(self, LabData.FLOOR_PNG, o, LabData.FLOOR, Color(1, 1, 1, a))
		var room := o + LabData.ROOM_OFF
		LabData.draw_art(self, LabData.room_path(f), room, LabData.ROOM, Color(1, 1, 1, a))
		_draw_leds(f, c[f], room, a)
		if view.training:
			draw_rect(Rect2(room, LabData.ROOM), LabData.fade(LabData.C_CYAN, 0.12 * a))
		if not view.reduce:
			var flick := 0.5 + 0.5 * sin(_t * 9.0 + float(f) * 2.1)
			draw_rect(Rect2(room + Vector2(56, 20), Vector2(10, 6)), LabData.fade(LabData.C_CYAN, 0.2 * flick * a))
		var column_top := f % 3 == 2 or c[f + 1] <= 0
		if column_top:
			LabData.draw_art(self, LabData.ROOF_PNG, o + Vector2(0, -LabData.ROOF.y), LabData.ROOF, Color(1, 1, 1, a))
	for i in range(6, 12):
		if c[i] <= 0:
			continue
		var st: int = LabData.TIER_STAGE[i]
		var pos: Vector2 = LabData.TIER_POS[i]
		var fall := view.fall_p(i)
		if st < stage:
			_draw_dot(pos + LabData.ROOM * 0.5, LabData.DOT_COLOR[i], 1.0 - fall)
		elif st == stage:
			var bt: float = view.build_t[i]
			var a := bt * (1.0 - fall)
			if a <= 0.0:
				continue
			var p := pos + Vector2(0, -20.0 * (1.0 - bt) + 140.0 * fall)
			LabData.draw_art(self, LabData.room_path(i), p, LabData.ROOM, Color(1, 1, 1, a))
			_draw_leds(i, c[i], p, a)
			_draw_extra(i, p, a)
	if stage >= 2 and c[0] > 0:
		_draw_dot(LabData.LAB_DOT, LabData.C_CYAN, 1.0 - view.fall_p(0))
	for j in view.legacy.size():
		var p := LabData.legacy_pos(j)
		LabData.draw_art(self, "res://assets/legacy/%s.png" % LabData.LEGACY_LAYERS[view.legacy[j]], p, Vector2(LabData.LEGACY, LabData.LEGACY))
		if j % 2 == 0:  # one shelf per column, under the lower prop
			draw_rect(Rect2(p.x - 2.0, LabData.GY - 2.0, LabData.LEGACY + 4.0, 2.0), LabData.C_WOOD)
	if stage <= 1 and c[0] > 0 and view.fall_p(0) <= 0.0:
		for w in _workers:
			var stepping: bool = w["pause"] <= 0.0 and not view.reduce
			var bob := -1.0 if stepping and fmod(_t * 4.0, 1.0) < 0.5 else 0.0
			var p := Vector2(float(w["x"]), LabData.WORKER_FEET - LabData.WORKER.y + bob)
			LabData.draw_art(self, "res://assets/workers/%s.png" % w["role"], p, LabData.WORKER, Color.WHITE, float(w["dir"]) < 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_leds(i: int, cnt: int, origin: Vector2, a: float) -> void:
	var n := 0
	for m in LabData.MILESTONES:
		if cnt >= m:
			n += 1
	for j in n:
		var on := view.reduce or sin(_t * 4.0 + float(j) * 1.9 + float(i)) > -0.3
		draw_rect(Rect2(origin + LabData.LED_POS[j], Vector2(2, 2)), LabData.fade(LabData.C_GREEN, a * (1.0 if on else 0.3)))


func _draw_dot(centre: Vector2, col: Color, a: float) -> void:
	if a <= 0.0:
		return
	var pulse := 0.5 if view.reduce else 0.5 + 0.5 * sin(_t * 3.0 + centre.x)
	draw_rect(Rect2(centre - Vector2(3, 3), Vector2(6, 6)), LabData.fade(col, 0.25 * a))
	draw_rect(Rect2(centre - Vector2(2, 2), Vector2(4, 4)), LabData.fade(col, a * (0.7 + 0.3 * pulse)))


## Ambient detail on exterior set pieces. Skipped under reduce_motion.
func _draw_extra(i: int, p: Vector2, a: float) -> void:
	if view.reduce:
		return
	var centre := p + LabData.ROOM * 0.5
	if i == 7:
		for s in 2:
			var ang := _t * 0.8 + float(s) * PI
			draw_rect(Rect2(centre + Vector2(cos(ang) * 60.0, sin(ang) * 18.0), Vector2(2, 2)), LabData.fade(LabData.C_WHITE, a))
	elif i == 9:
		for s in 8:
			var ang := float(s) / 8.0 * TAU + _t * 0.5
			var tw := 0.5 + 0.5 * sin(_t * 4.0 + float(s))
			draw_rect(Rect2(centre + Vector2(cos(ang) * 46.0, sin(ang) * 30.0), Vector2(2, 2)), LabData.fade(LabData.C_AMBER, a * (0.3 + 0.7 * tw)))
