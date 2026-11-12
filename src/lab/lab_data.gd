class_name LabData
extends RefCounted
## Layout, palette and art helpers for the lab cutaway. Layout units are art pixels.

const IDS := [
	"intern_laptop", "cloud_gpus", "server_rack", "data_centre", "custom_silicon", "hyperscale_campus",
	"fusion_plant", "orbital_cluster", "lunar_foundry", "dyson_swarm", "matrioshka_brain", "universe_simulator",
]
const ROLES := ["researcher", "engineer", "ops"]
const LEGACY_LAYERS := ["funding", "generation", "paradigm", "singularity"]
const MILESTONES := [25, 50, 100, 200]
const MAX_WORKERS := 3

const FLOOR_PNG := "res://assets/shell/floor.png"
const ROOF_PNG := "res://assets/shell/roof.png"
const GROUND_PNG := "res://assets/shell/ground.png"
const FLOOR := Vector2(104, 72)
const ROOM := Vector2(96, 64)
const ROOM_OFF := Vector2(4, 4)
const ROOF := Vector2(104, 16)
const GROUND_H := 16.0
const GY := 232.0                      # top of the ground strip; floors stand on it
const WORKER := Vector2(16, 24)
const WORKER_FEET := 228.0             # floor line inside the ground-floor room (GY - 4)
const LEGACY := 24.0
const LEGACY_STEP := 24.0              # legacy props stand in columns left of the building, two high, nearest first
const LED_POS := [Vector2(6, 8), Vector2(86, 8), Vector2(6, 52), Vector2(86, 52)]
const SKY_ORIGIN := Vector2(-56, 100)  # garage and city backdrops: their horizon sits on GY
const LAB_DOT := Vector2(408, 120)     # the building, shrunk to a dot from stage 2 on

## Zoom stage of each producer tier (index 0..11). Tiers 1-6 are the building (stage 0).
const TIER_STAGE := [0, 0, 0, 0, 0, 0, 1, 2, 2, 3, 3, 4]
## Top-left of each exterior set piece in the shared world (index 6..11).
const TIER_POS := [
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2(224, 168), Vector2(456, 40), Vector2(568, 96), Vector2(712, 40), Vector2(856, 40), Vector2(1000, 48),
]

## Backdrop per stage (index = stage). Stage 0 is chosen by the view (garage or city).
const BACKDROPS := ["garage_sky", "city", "orbit", "swarm", "universe"]
## Camera per zoom stage: centre c and the art-pixel area s that must fit on screen. Stage 0 is framed from the build.
const FOCUS := [
	{"c": Vector2(104, 116), "s": Vector2(120, 120)},
	{"c": Vector2(160, 124), "s": Vector2(340, 170)},
	{"c": Vector2(560, 100), "s": Vector2(300, 150)},
	{"c": Vector2(832, 72), "s": Vector2(300, 130)},
	{"c": Vector2(1048, 80), "s": Vector2(200, 130)},
]

static var C_CYAN := Color("3FD6CF")
static var C_MINT := Color("A6F3EC")
static var C_WHITE := Color("F2FBF9")
static var C_GREY := Color("B9C6D6")
static var C_SLATE := Color("7F8BA3")
static var C_STEEL := Color("4A5468")
static var C_DARK := Color("2E3646")
static var C_NIGHT := Color("0B0E1A")
static var C_AMBER := Color("FFB347")
static var C_GOLD := Color("FFE08A")
static var C_WOOD := Color("9C5A2E")
static var C_GREEN := Color("5FD17A")
static var C_RED := Color("C8362F")
static var C_LRED := Color("FF6B6B")
static var C_LILAC := Color("A77BC9")
static var C_VIOLET := Color("7D4FA8")
static var CONFETTI := [Color("FFB347"), Color("5FD17A"), Color("FF6B6B"), Color("3FD6CF"), Color("A77BC9"), Color("FFE08A"), Color("F2FBF9")]
## Dot colour per exterior tier (index 0..11; entries 0..5 unused).
static var DOT_COLOR := [
	Color("3FD6CF"), Color("3FD6CF"), Color("3FD6CF"), Color("3FD6CF"), Color("3FD6CF"), Color("3FD6CF"),
	Color("FFB347"), Color("A6F3EC"), Color("B9C6D6"), Color("FFE08A"), Color("A77BC9"), Color("F2FBF9"),
]

static var _cache := {}


static func fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func room_path(i: int) -> String:
	return "res://assets/rooms/%s.png" % IDS[i]


## Draws an art texture at an art-space rect. Missing art falls back to a palette rect (dev only).
static func draw_art(ci: CanvasItem, path: String, pos: Vector2, size: Vector2, tint := Color(1, 1, 1, 1), flip := false) -> void:
	var t := tex(path)
	if t == null:
		ci.draw_rect(Rect2(pos, size), fade(C_SLATE, tint.a * 0.6))
		return
	var r := Rect2(pos, size)
	if flip:
		r = Rect2(pos + Vector2(size.x, 0), Vector2(-size.x, size.y))
	ci.draw_texture_rect(t, r, false, tint)


## Top-left of building floor f (0..5). Column 0 is floors 0-2, column 1 is floors 3-5; each column stacks upward from GY.
static func floor_origin(f: int) -> Vector2:
	return Vector2(float(floori(f / 3.0)) * FLOOR.x, GY - float(f % 3 + 1) * FLOOR.y)


## Columns of legacy props needed for n props (two props per column). Keeps the framing narrow after many resets.
static func legacy_cols(n: int) -> int:
	return ceili(float(n) / 2.0)


## Legacy prop j stands on the ground, nearest the building first; the second prop of a column sits on the first.
static func legacy_pos(j: int) -> Vector2:
	var col := j / 2
	var row := j % 2
	return Vector2(-8.0 - LEGACY_STEP * float(col + 1), GY - LEGACY - 2.0 - LEGACY * float(row))
