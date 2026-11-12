class_name PanelBase
extends Control
## Base for the progression panels. Subclasses build widgets once in _build() and update them in _refresh().
## _refresh() runs on every Game signal and on a light timer, so automation and offline ticks show up without per-frame work.

var page: VBoxContainer
var result_line: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = PanelKit.col(PanelKit.BG)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	page = PanelKit.scroll_page(self)
	result_line = PanelKit.label("", PanelKit.TEXT)
	page.add_child(result_line)
	_build()
	var refresh := Callable(self, "_refresh")
	for sig in Game.get_signal_list():
		var n: int = sig["args"].size()
		Game.connect(sig["name"], refresh if n == 0 else refresh.unbind(n))
	PanelKit.timer(self, refresh)
	_refresh()


## Override: create widgets (called once).
func _build() -> void:
	pass


## Override: push current state into widgets (called often).
func _refresh() -> void:
	pass


## Override: false hides the panel from the shell's tab bar until its layer is reachable.
func is_unlocked() -> bool:
	return true


## Override: true when the shell should flag this panel (e.g. a reset is worth doing or a buy is affordable).
func wants_attention() -> bool:
	return false


## Shows an action result at the top of the panel: failure reason in red, ok_text in green.
func report(r: Dictionary, ok_text: String) -> void:
	var ok: bool = r.get("ok", false)
	result_line.text = ok_text if ok else str(r.get("reason", "Failed."))
	result_line.add_theme_color_override("font_color", PanelKit.col(PanelKit.GREEN if ok else PanelKit.RED))
	PanelKit.flash(result_line)


## A button that runs `action` (a Callable returning a Sim result dict) and reports it.
func action_button(text: String, enabled: bool, action: Callable, ok_text: String) -> Button:
	var b := PanelKit.button(text, Callable(), enabled)
	b.pressed.connect(func() -> void:
		var r: Dictionary = action.call()
		report(r, ok_text)
		if r.get("ok", false):
			PanelKit.pop(b))
	return b
