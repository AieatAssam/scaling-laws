class_name PanelResetCard
extends PanelContainer
## One layer reset: what it yields, what it keeps and wipes, and a confirm step before it runs.

const WIPES := {
	1: "Wipes cash, compute, producers and any training run. Keeps equity and everything in later layers.",
	2: "Also wipes equity and staff. Keeps insights, research and the best training score.",
	3: "Also wipes insights, research and the best training score. Keeps breakthroughs, data, energy and automation.",
	4: "Also wipes breakthroughs, data and energy. Keeps legacy and its perks, the AGI stage, rival progress and challenges.",
}
const LAYER_ART := ["", "funding", "generation", "paradigm", "singularity"]

var layer: int = 0
var _on_result: Callable
var _gain: Label
var _holding: Label
var _eta: Label
var _why: Label
var _button: Button
var _dialog: ConfirmationDialog


## A layer k is shown as reachable once the layer below has been reset, or once this layer's gain is non-zero.
static func is_layer_unlocked(k: int) -> bool:
	var s: GameState = Game.state
	return s.resets(k - 1) > 0 or s.resets(k) > 0 or int(Sim.reset_preview(s, k)["gain"]) >= 1


## Builds the card for layer k. `on_result` receives (sim_result, ok_text) after the reset runs.
func setup(k: int, on_result: Callable) -> PanelResetCard:
	layer = k
	_on_result = on_result
	PanelKit.style_card(self)
	Tip.attach(self, Callable(self, "_tip"))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(PanelKit.icon(LAYER_ART[k], 1.5, PanelKit.LEGACY))
	head.add_child(PanelKit.label(PanelText.layer_title(k), PanelKit.BRIGHT))
	head.add_child(PanelHelp.button(LAYER_ART[k]))
	v.add_child(head)
	_gain = PanelKit.label("", PanelKit.GOLD)
	_holding = PanelKit.label("", PanelKit.TEXT)
	_eta = PanelKit.label("", PanelKit.MUTED)
	v.add_child(_gain)
	v.add_child(_holding)
	v.add_child(_eta)
	v.add_child(PanelKit.label(WIPES[k], PanelKit.MUTED))
	_why = PanelKit.label("", PanelKit.MUTED)
	v.add_child(_why)
	_button = PanelKit.button("", Callable(), false)
	_button.pressed.connect(func() -> void: _dialog.popup_centered())
	v.add_child(_button)
	_dialog = ConfirmationDialog.new()
	_dialog.exclusive = false   # several panels live in one window in the dev harness; only one dialog opens at a time anyway
	_dialog.confirmed.connect(_do_reset)
	add_child(_dialog)
	refresh()
	return self


func refresh() -> void:
	var p: Dictionary = Sim.reset_preview(Game.state, layer)
	var cur: String = PanelText.cur_name(str(p["currency"]))
	var gain := int(p["gain"])
	_gain.text = "Gain on reset: +%d %s" % [gain, cur]
	_holding.text = "You hold: %s %s" % [(p["holding"] as BigNum).format(), cur]
	_eta.text = _eta_text(Rules.reset_eta(Game.state, layer))
	var allowed: bool = p["allowed"]
	if not allowed:
		_why.text = str(p["reason"])
	elif p["highlight"]:
		_why.text = "Worth it: the gain is at least double what you hold."
	else:
		_why.text = ""
	_button.text = "Run +%d %s" % [gain, cur]   # the full name is in the dialog and the header
	_button.disabled = not allowed
	_dialog.title = "Run %s?" % PanelText.layer_title(layer)
	_dialog.dialog_text = "You gain +%d %s. %s" % [gain, cur, WIPES[layer]]


## Full explanation of this reset: gain, holding, what it wipes, and why it is or isn't allowed now.
func _tip() -> String:
	var p: Dictionary = Sim.reset_preview(Game.state, layer)
	var cur: String = PanelText.cur_name(str(p["currency"]))
	var lines: Array[String] = [
		"Run %s" % PanelText.layer_title(layer),
		"Gain on reset: +%d %s. You hold %s." % [int(p["gain"]), cur, (p["holding"] as BigNum).format()],
		WIPES[layer],
	]
	if not p["allowed"]:
		lines.append(str(p["reason"]))
	elif p["highlight"]:
		lines.append("Worth it: the gain is at least double what you hold.")
	lines.append("Est.: times assume cash income stays at today's rate.")
	return "\n".join(lines)


## "Est.: worth it in ~12m, next +1 in ~3m" (at the current cash rate). "now" once worth it; "-" when there is no income.
func _eta_text(e: Dictionary) -> String:
	var worth := "worth it now" if e["worth_now"] else "worth it in " + _dur(float(e["worth_in"]))
	return "Est.: %s, next +1 in %s" % [worth, _dur(float(e["next_in"]))]


## "~12m" style, "<1m" under a minute, "-" when the rate is zero (INF).
static func _dur(sec: float) -> String:
	if is_inf(sec):
		return "-"
	return "<1m" if sec < 60.0 else "~" + _span(sec)


## Coarse time: "<1m", "12m", "3h", "5d", "over 100y".
static func _span(sec: float) -> String:
	if sec >= 3.15e9:
		return "over 100y"
	if sec < 60.0:
		return "<1m"
	if sec < 3600.0:
		return "%dm" % roundi(sec / 60.0)
	if sec < 86400.0:
		return "%dh" % roundi(sec / 3600.0)
	return "%dd" % roundi(sec / 86400.0)


func _do_reset() -> void:
	var r: Dictionary = Game.reset_layer(layer)
	_on_result.call(r, "%s done." % PanelText.layer_title(layer))
