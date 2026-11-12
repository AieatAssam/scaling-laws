class_name TickLabel
extends Label
## Label that eases its number toward a BigNum target in log10 space (works past float range).
## Snaps instantly under reduce_motion.

var prefix := ""
var suffix := ""
var _target := BigNum.new()
var _goal := -INF   # log10 of the target (-INF for zero)
var _shown := -INF  # log10 of the displayed value


func set_target(v: BigNum) -> void:
	_target = v
	_goal = v.log10()
	if _shown == _goal:
		_redraw()


func _process(delta: float) -> void:
	if _shown == _goal:
		return
	if Fx.reduce_motion() or not is_finite(_goal) or not is_finite(_shown):
		_shown = _goal
	else:
		_shown = lerpf(_shown, _goal, 1.0 - exp(-delta * 10.0))
		if absf(_shown - _goal) < 0.0005 * maxf(1.0, absf(_goal)):
			_shown = _goal
	_redraw()


func _redraw() -> void:
	var body: String
	if _shown == _goal:
		body = _target.format()
	elif not is_finite(_shown):
		body = "0"
	else:
		var e := floorf(_shown)
		body = BigNum.new(pow(10.0, _shown - e), int(e)).format()
	text = prefix + body + suffix
