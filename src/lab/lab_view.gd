class_name LabView
extends Control
## Animated lab cutaway. Mirrors the run state and frames the camera. Everything is drawn in art pixels:
## unit() is the view size of one art pixel, a whole number of physical pixels, so the art stays crisp.
## Art is 2x its logical size, so pixel_k is always even: each art texel is a whole physical pixel, see _k_for.
## Drawing lives in LabBack (backdrops), LabWorld (lab, props, workers) and LabFront (effects, fades).

const COLLAPSE_SECONDS := 2.7  # the reset overlay is opaque for its first 1.2 s, so the fall starts after it
const COLLAPSE_DELAY := 1.2
const CAM_SECONDS := 0.7       # centre glide between framings with the same scale
const COVER_IN := 0.18         # fade to the cover colour before a zoom change
const COVER_OUT := 0.22        # fade back out after the snap
const MARGIN := 8.0            # art pixels around the building in stage 0
const DRAG_SLOP := 8.0         # view pixels a press may move before it counts as a drag, not a tap

@onready var back: LabBack = $Back
@onready var world: LabWorld = $World
@onready var front: LabFront = $Front

var stage := 0                 # zoom stage wanted (set by the build, or by a tap)
var shown_stage := 0           # zoom stage on screen (changes at the snap)
var shown_c := Vector2(104, 116)   # camera centre in art pixels, glides within a stage
var shown_r := Rect2(44, 56, 120, 120)  # art area that must fit (framing rect); sets pixel_k, changes only at snaps
var pan := Vector2.ZERO        # art-pixel offset from the drag; kept inside shown_r, reset on every zoom change
var pixel_k := 2               # physical pixels per art pixel (always even, see _k_for)
var px := 1.0                  # physical pixels per view pixel
var cover := 0.0               # 0..1 opacity of the cover drawn over the view during a zoom change
var bld := Vector2(52, 196)    # centre of the building in art pixels (effects aim here)
var shown: Array[int] = []     # producer counts currently drawn
var build_t: Array[float] = []
var snap: Array[int] = []      # counts frozen while a reset collapses
var collapsing := false
var collapse_t := 0.0
var legacy: Array[int] = []    # reset layer indices (0..3) with a legacy prop
var staff: Dictionary = {}
var training := false
var reduce := false
var top := -1                  # highest owned tier index, -1 when none
var _cover_dir := 0.0          # +1 fading to the cover, -1 fading back out, 0 idle
var _tween: Tween
var _tween_to := Vector2.INF
var _primed := false
var _press := Vector2.INF      # where the current press started (view px), INF when no press is held
var _press_dragged := false    # the press has moved past DRAG_SLOP, so release is not a tap


func _ready() -> void:
	clip_contents = true
	texture_filter = TEXTURE_FILTER_NEAREST
	shown.resize(12)
	shown.fill(0)
	build_t.resize(12)
	build_t.fill(1.0)
	snap.resize(12)
	snap.fill(0)
	back.view = self
	world.view = self
	front.view = self
	Game.started.connect(_resync)
	Game.new_run_started.connect(_resync)
	Game.layer_reset.connect(_on_layer_reset)
	Game.training_finished.connect(_on_training_finished)
	Game.event_offered.connect(_on_event_offered)
	Game.challenge_finished.connect(_on_challenge_finished)
	Game.rival_launched.connect(_on_rival_launched)
	Game.benchmark_unlocked.connect(_on_benchmark_unlocked)
	Game.settings_changed.connect(_on_setting_changed)
	if get_tree().current_scene == self and not Game.running:
		Game.start()
	_resync()
	_primed = true


func _process(delta: float) -> void:
	if Game.state == null:
		return
	px = maxf(1.0, get_viewport().get_final_transform().get_scale().x)
	if collapsing:
		collapse_t += delta
		if collapse_t >= COLLAPSE_SECONDS:
			collapsing = false
			legacy = _load_legacy()
	else:
		_reconcile()
	for i in 12:
		if build_t[i] < 1.0:
			build_t[i] = minf(1.0, build_t[i] + delta * 3.0)
	_update_cover(delta)
	_frame()
	pixel_k = _k_for(shown_r.size)


## Copies the run state into the mirror (on start, new run, and first frame). Snaps the camera.
func _resync() -> void:
	if Game.state == null:
		return
	var st: GameState = Game.state
	collapsing = false
	for i in LabData.IDS.size():
		shown[i] = st.owned(LabData.IDS[i])
		build_t[i] = 1.0
	staff = st.run["layers"][1]["staff"]
	training = not (st.run["layers"][0]["training"] as Dictionary).is_empty()
	reduce = bool(st.persist["settings"].get("reduce_motion", false))
	legacy = _load_legacy()
	top = -1
	for i in 12:
		if shown[i] > 0:
			top = i
	stage = LabData.TIER_STAGE[top] if top >= 0 else 0
	_cover_dir = 0.0
	cover = 0.0
	pan = Vector2.ZERO
	_apply(_target())


## Diffs owned counts against the mirror. Covers purchases and automation, which emit no signal.
func _reconcile() -> void:
	var st: GameState = Game.state
	var new_top := -1
	for i in 12:
		var want := st.owned(LabData.IDS[i])
		if want != shown[i]:
			if want > shown[i] and _primed:
				front.burst_art(tier_art_pos(i), [LabData.C_CYAN, LabData.C_MINT], 4, 30.0, 10.0, 0.5, 2.0)
			if want > 0 and shown[i] == 0:
				build_t[i] = 0.0
			shown[i] = want
		if want > 0:
			new_top = i
	if reduce:
		build_t.fill(1.0)
	if new_top != top:
		top = new_top
		pan = Vector2.ZERO
		stage = LabData.TIER_STAGE[top] if top >= 0 else 0
	staff = st.run["layers"][1]["staff"]
	training = not (st.run["layers"][0]["training"] as Dictionary).is_empty()


## One legacy prop per reset layer with a non-zero lifetime count (persist.lifetime_resets).
func _load_legacy() -> Array[int]:
	var out: Array[int] = []
	var lifetime: Array = Game.state.persist["lifetime_resets"]
	for k in 4:
		if int(lifetime[k]) > 0:
			out.append(k)
	return out


## Largest even number of physical pixels per art pixel whose physical size fits the art area s, never below 2.
## The art is 2x, so an even count makes each texel a whole number of physical pixels (crisp). An odd count would
## land texels on half pixels. Phones get 2 and window the framed area instead (see _clamp_c).
func _k_for(s: Vector2) -> int:
	var phys := size * px
	if phys.x < 1.0 or phys.y < 1.0 or s.x <= 0.0 or s.y <= 0.0:
		return 2
	var k := floori(minf(phys.x / s.x, phys.y / s.y))
	return maxi(2, k - k % 2)


## Art pixels visible in the view at the current scale.
func _art_view() -> Vector2:
	return size * px / float(pixel_k)


## Camera centre c kept so the visible window (V art px) stays inside framing rect r. A window wider or taller than r
## is centred on r, so framings that fit keep their centre exactly.
func _clamp_c(c: Vector2, r: Rect2, v: Vector2) -> Vector2:
	if v.x >= r.size.x:
		c.x = r.get_center().x
	else:
		c.x = clampf(c.x, r.position.x + v.x * 0.5, r.end.x - v.x * 0.5)
	if v.y >= r.size.y:
		c.y = r.get_center().y
	else:
		c.y = clampf(c.y, r.position.y + v.y * 0.5, r.end.y - v.y * 0.5)
	return c


## The camera centre actually drawn: the glided centre plus the player's drag, kept inside the framing.
func view_c() -> Vector2:
	return _clamp_c(shown_c + pan, shown_r, _art_view())


## Drag by rel view px: moves the picture with the finger, never past the framing.
func _pan_by(rel: Vector2) -> void:
	var c := _clamp_c(view_c() - rel / unit(), shown_r, _art_view())
	pan = c - shown_c


## View pixels per art pixel (the transform the lab layers draw with).
func unit() -> float:
	return float(pixel_k) / px


## View-space position of art pixel (0, 0). Snapped to physical pixels so the art grid stays aligned.
func art_origin() -> Vector2:
	var phys := size * 0.5 * px - view_c() * float(pixel_k)
	return phys.round() / px


func art_to_view(p: Vector2) -> Vector2:
	return art_origin() + p * unit()


func tier_art_pos(i: int) -> Vector2:
	return LabData.floor_origin(i) + Vector2(52, 40) if i < 6 else LabData.TIER_POS[i] + Vector2(48, 32)


## Counts drawn this frame: the frozen snapshot while collapsing, otherwise the live mirror.
func counts() -> Array[int]:
	return snap if collapsing else shown


## 0..1 progress of tier i's fall during a reset collapse. Top tiers fall first.
func fall_p(i: int) -> float:
	if not collapsing:
		return 0.0
	var delay := COLLAPSE_DELAY + float(11 - i) * 0.08
	return clampf((collapse_t - delay) / 0.5, 0.0, 1.0)


func backdrop_name() -> String:
	if shown_stage == 0:
		return "city" if top >= 3 else "garage_sky"
	return LabData.BACKDROPS[shown_stage]


## Where the shown backdrop's art pixel (0, 0) sits. Space backdrops follow their stage's camera.
func backdrop_origin() -> Vector2:
	if shown_stage == 0 or shown_stage == 1:
		return LabData.SKY_ORIGIN
	return LabData.FOCUS[shown_stage].c - Vector2(160, 90)


## The framing the camera should have now: stage 0 fits the build, later stages use FOCUS.
## r is the framing rect (what must be visible); c the wanted centre. Stage 0 centres on the newest floor when the build
## is larger than the view, so a phone opens on the part that just grew.
func _target() -> Dictionary:
	if stage > 0:
		var f: Dictionary = LabData.FOCUS[stage]
		var r := Rect2(f.c - f.s * 0.5, f.s)
		var c: Vector2 = f.c
		if _too_small(r.size):
			c = _newest_in(stage, c)
		return {"c": c, "r": r, "stage": stage}
	var c := counts()
	var levels := [0, 0]   # highest owned level per column (1..3)
	for f in 6:
		if c[f] > 0:
			var col := floori(f / 3.0)
			levels[col] = maxi(levels[col], f % 3 + 1)
	var cols := 2 if levels[1] > 0 else 1
	var tall := maxi(1, maxi(levels[0], levels[1]))
	var x0 := -8.0 - LabData.LEGACY_STEP * float(LabData.legacy_cols(legacy.size())) if legacy.size() > 0 else 0.0
	var x1 := float(cols) * LabData.FLOOR.x
	var top_y := LabData.GY - float(tall) * LabData.FLOOR.y - LabData.ROOF.y
	var bot_y := LabData.GY + LabData.GROUND_H
	bld = Vector2(x1 * 0.5, LabData.GY - float(tall) * LabData.FLOOR.y * 0.5)
	var r := Rect2(x0 - MARGIN, top_y - MARGIN, x1 - x0 + 2.0 * MARGIN, bot_y - top_y + 2.0 * MARGIN)
	var centre := r.get_center()
	if _too_small(r.size):
		centre = _newest_in(0, centre)
	return {"c": centre, "r": r, "stage": 0}


## True when the view cannot show the whole framing s at the current scale (phones, small windows).
func _too_small(s: Vector2) -> bool:
	return _art_view().x < s.x or _art_view().y < s.y


## Centre of the newest owned tier in zoom stage st (its art centre), or `otherwise` when none is owned. A view too
## small for the framing centres here, so the part that just grew stays on screen.
func _newest_in(st: int, otherwise: Vector2) -> Vector2:
	for i in range(11, -1, -1):
		if shown[i] > 0 and LabData.TIER_STAGE[i] == st:
			return tier_art_pos(i)
	return otherwise


## Applies a framing with no animation.
func _apply(tgt: Dictionary) -> void:
	shown_stage = tgt.stage
	shown_c = tgt.c
	shown_r = tgt.r
	_tween_to = tgt.c
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


## Same scale: glide the centre. Different scale or stage: fade to the cover, snap at the midpoint, fade out.
func _frame() -> void:
	var tgt := _target()
	if reduce:
		_apply(tgt)
		return
	if _cover_dir == 0.0 and (tgt.stage != shown_stage or _k_for(tgt.r.size) != _k_for(shown_r.size)):
		_cover_dir = 1.0
	if _cover_dir != 0.0:
		return
	shown_r = tgt.r
	if tgt.c.distance_to(_tween_to) > 0.01:
		_tween_to = tgt.c
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "shown_c", tgt.c, CAM_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _update_cover(delta: float) -> void:
	if _cover_dir > 0.0:
		cover = minf(1.0, cover + delta / COVER_IN)
		if cover >= 1.0:
			_apply(_target())
			_cover_dir = -1.0
			pan = Vector2.ZERO
	elif _cover_dir < 0.0:
		cover = maxf(0.0, cover - delta / COVER_OUT)
		if cover <= 0.0:
			_cover_dir = 0.0


## A tap (press and release without dragging) moves to the next zoom stage, never past the highest stage owned.
## A drag pans the picture inside the framing, for touch and for a real mouse. Emulated mouse events from touch are ignored.
func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	var mouse := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if touch != null or (mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.device != -1):
		var down := touch.pressed if touch != null else mouse.pressed
		var at := touch.position if touch != null else mouse.position
		if down:
			_press = at
			_press_dragged = false
		elif _press != Vector2.INF:
			if not _press_dragged:
				var hi: int = LabData.TIER_STAGE[top] if top >= 0 else 0
				stage = stage + 1 if stage < hi else 0
				pan = Vector2.ZERO
			_press = Vector2.INF
		accept_event()
	elif (drag != null or (motion != null and motion.device != -1 and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)) and _press != Vector2.INF:
		var at := drag.position if drag != null else motion.position
		if not _press_dragged and at.distance_to(_press) < DRAG_SLOP:
			return
		_press_dragged = true
		_pan_by(drag.relative if drag != null else motion.relative)
		accept_event()


func _on_layer_reset(_layer: int, _gain: int) -> void:
	if reduce:
		legacy = _load_legacy()
		return
	for i in 12:
		snap[i] = shown[i]
	collapsing = true
	collapse_t = 0.0


func _on_training_finished(r: Dictionary) -> void:
	front.on_result(bool(r.get("ok", false)))


func _on_event_offered(id: String) -> void:
	var d = Content.get_def("events", id)
	front.on_event(d.category if d else "")


func _on_challenge_finished(_id: String, success: bool) -> void:
	front.on_result(success)


func _on_rival_launched(_id: String) -> void:
	front.comet()


func _on_benchmark_unlocked(_id: String, _badge: String) -> void:
	front.confetti()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key != "reduce_motion":
		return
	reduce = bool(value)
	if reduce:
		collapsing = false
		cover = 0.0
		_cover_dir = 0.0
		build_t.fill(1.0)
		legacy = _load_legacy()
		_apply(_target())
