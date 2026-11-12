class_name SettingsPanel
extends Control
## Settings: reduce motion, UI scale, manual save, read-only run stats.

const SCALES := [1.0, 1.25, 1.5]

var _motion: CheckBox
var _scale_buttons := {}  # float -> Button
var _stats: Label
var _saved: Label
var _result: Label
var _paste: LineEdit
var _reset_dialog: ConfirmationDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	var head := Label.new()
	head.text = "Settings"
	head.theme_type_variation = &"Heading"
	page.add_child(head)

	_motion = CheckBox.new()
	_motion.text = "Reduce motion"
	_motion.custom_minimum_size.y = 28
	Tip.attach(_motion, "Reduce motion\nNo fades or pops; tooltips appear instantly. Saved with your game.")
	_motion.toggled.connect(func(on: bool) -> void: Game.set_setting("reduce_motion", on))
	page.add_child(_motion)

	var scale_lbl := Label.new()
	scale_lbl.text = "UI scale"
	page.add_child(scale_lbl)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	page.add_child(scale_row)
	var group := ButtonGroup.new()
	for s in SCALES:
		var b := Button.new()
		b.text = "%sx" % s
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, PanelKit.TOUCH_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(Game.set_setting.bind("ui_scale", s))
		Tip.attach(b, "UI scale %sx\nScales the whole interface. Use a larger scale on small phones." % s)
		scale_row.add_child(b)
		_scale_buttons[s] = b

	var save_btn := Button.new()
	save_btn.text = "Save now"
	save_btn.custom_minimum_size = Vector2(0, 28)
	save_btn.pressed.connect(_save_now)
	Tip.attach(save_btn, "Save now\nWrites progress to disk immediately. The game also autosaves every 30 s.")
	page.add_child(save_btn)
	_result = Label.new()
	_result.theme_type_variation = &"MicroDim"
	page.add_child(_result)
	_saved = Label.new()
	_saved.theme_type_variation = &"MicroDim"
	page.add_child(_saved)
	_stats = Label.new()
	_stats.theme_type_variation = &"MicroDim"
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_stats)
	var intro_btn := PanelKit.button("Replay intro", _replay_intro, true)
	Tip.attach(intro_btn, "Replay intro\nPlays the opening story again. The game pauses until it ends.")
	page.add_child(intro_btn)

	page.add_child(PanelKit.label("Save data", PanelKit.GOLD))
	var io_row := VBoxContainer.new()
	io_row.add_theme_constant_override("separation", 6)
	page.add_child(io_row)
	var copy_btn := PanelKit.button("Copy save", _export, true)
	Tip.attach(copy_btn, "Copy save\nCopies your save as text to the clipboard, for backup or another device.")
	io_row.add_child(copy_btn)
	var reset_btn := PanelKit.button("Hard reset", _confirm_reset, true)
	Tip.attach(reset_btn, "Hard reset\nErases all progress, legacy included. Cannot be undone.")
	io_row.add_child(reset_btn)
	_paste = LineEdit.new()
	_paste.placeholder_text = "Paste save here"
	_paste.custom_minimum_size.y = PanelKit.TOUCH_H
	_paste.clear_button_enabled = true
	Tip.attach(_paste, "Paste a save copied earlier, then import it.")
	page.add_child(_paste)
	var import_btn := PanelKit.button("Import pasted save", _import, true)
	Tip.attach(import_btn, "Import pasted save\nReplaces current progress with the pasted save, then reloads the game.")
	page.add_child(import_btn)

	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.dialog_text = "Erase all progress, legacy included? This cannot be undone."
	_reset_dialog.confirmed.connect(_hard_reset)
	add_child(_reset_dialog)

	var tm := Timer.new()
	tm.wait_time = 0.5
	tm.timeout.connect(_refresh)
	add_child(tm)
	tm.start()
	_refresh()


func _refresh() -> void:
	var st: Dictionary = Game.state.persist["settings"]
	_motion.set_pressed_no_signal(bool(st.get("reduce_motion", false)))
	var cur := float(st.get("ui_scale", 1.0))
	for s in _scale_buttons:
		(_scale_buttons[s] as Button).set_pressed_no_signal(absf(cur - s) < 0.01)
	var stats: Dictionary = Game.state.persist["stats"]
	var secs := int(stats.get("time", 0.0))
	_stats.text = "Runs %d  Resets %d  Trainings %d  Events %d  Play time %dh %02dm" % [
		int(stats.get("runs", 0)), int(stats.get("resets", 0)), int(stats.get("trainings", 0)),
		int(stats.get("events", 0)), secs / 3600, (secs % 3600) / 60,
	]
	var at := float(Game.state.persist.get("saved_at", 0.0))
	_saved.text = "Last saved %s" % Time.get_datetime_string_from_unix_time(int(at)) if at > 0.0 else "Not saved yet"


func _save_now() -> void:
	var ok := Game.save_now()
	_result.text = "Saved" if ok else "Save failed"
	_result.add_theme_color_override("font_color", Fx.col(Fx.GREEN if ok else Fx.RED))
	_refresh()


func _report(ok: bool, text: String) -> void:
	_result.text = text
	_result.add_theme_color_override("font_color", Fx.col(Fx.GREEN if ok else Fx.RED))


## Copies the same wrapper SaveSystem writes to disk, so it can be pasted back in.
func _export() -> void:
	var wrapper := {"version": SaveSystem.VERSION, "state": Game.state.to_dict()}
	DisplayServer.clipboard_set(JSON.stringify(wrapper))
	_report(true, "Save copied to clipboard.")


## Validates the pasted wrapper before replacing progress; the scene reloads so no panel keeps stale numbers.
func _import() -> void:
	var json := JSON.new()
	if json.parse(_paste.text.strip_edges()) != OK or not (json.data is Dictionary) or not json.data.has("state"):
		_report(false, "Not a valid save.")
		return
	var data: Dictionary = SaveSystem.migrate(json.data)
	if data.is_empty() or not (data.get("persist") is Dictionary) or not (data.get("run") is Dictionary):
		_report(false, "Not a valid save.")
		return
	Game.state = GameState.from_dict(Content, data)
	Game.save_now()
	_paste.text = ""
	get_tree().call_deferred("reload_current_scene")


## Asks the shell to play the intro again (main.gd play_intro). Replaying does not change the flag.
func _replay_intro() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("play_intro"):
		main.call("play_intro")


func _confirm_reset() -> void:
	_reset_dialog.popup_centered()


func _hard_reset() -> void:
	SaveSystem.delete(Game.save_path)
	Game.state = GameState.new(Content, randi())
	Game.save_now()
	get_tree().call_deferred("reload_current_scene")


func is_unlocked() -> bool:
	return true


func wants_attention() -> bool:
	return false
