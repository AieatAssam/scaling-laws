class_name RevealCard
extends Control
## One-time "New: <System>" card (see Reveals). Opens through `gate` (the shell's modal queue), never during the intro,
## and at most one per REVEAL_GAP_MS. OK, Space/Enter or Back closes it; "Learn more" closes it and opens the system's
## Help topic. A shown reveal is saved as seen, so it never comes back.

signal closed

const REVEAL_GAP_MS := 30000

var gate: Callable   # shell: runs an open Callable now or after the dialog in front closes

var _shade: ColorRect
var _card: PanelContainer
var _head: Label
var _body: Label
var _topic := ""
var _pending := false              # asked the shell's queue for a card that has not opened yet
var _last_ms := -REVEAL_GAP_MS     # Time.get_ticks_msec() when the last card opened


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = ColorRect.new()
	_shade.color = Color(Fx.col(Fx.BG), 0.8)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	add_child(_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size.x = 300
	_card.visible = false
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	_head = Label.new()
	_head.theme_type_variation = &"Heading"
	box.add_child(_head)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var more := Button.new()
	more.text = "Learn more"
	more.custom_minimum_size = Vector2(0, 28)
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more.pressed.connect(_learn_more)
	row.add_child(more)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0, 28)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_close)
	row.add_child(ok)

	var tm := Timer.new()
	tm.wait_time = 1.0
	tm.timeout.connect(_tick)
	add_child(tm)
	tm.start()


## Once a second: asks the queue for the next due reveal, unless one is up or already asked for.
func _tick() -> void:
	if _pending or _card.visible or Game.state == null or not Game.running:
		return
	if not bool(Game.state.persist.get("intro_seen", true)):
		return
	var id := Reveals.next_due(Game.state)
	if id == "":
		return
	_pending = true
	if gate.is_valid():
		gate.call(_open.bind(id))
	else:
		_open(id)


## Shows reveal `id`. Returns false (skipped) when it is too soon after the last card or already seen; the next tick asks again.
func _open(id: String) -> bool:
	_pending = false
	var r := Reveals.find(id)
	if r.is_empty() or Reveals.is_seen(Game.state, id) or Time.get_ticks_msec() - _last_ms < REVEAL_GAP_MS:
		return false
	Reveals.mark_seen(Game.state, id)
	Game.save_now()
	_last_ms = Time.get_ticks_msec()
	Audio.play("unlock_reveal")
	_topic = String(r["topic"])
	_head.text = "New: %s" % r["title"]
	_body.text = String(r["body"])
	_shade.visible = true
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = true
	return true


func _learn_more() -> void:
	var topic := _topic
	_close()
	get_tree().call_group("shell", "open_help", topic)


func _close() -> void:
	_card.visible = false
	_shade.visible = false
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


## Space, Enter, Back: closes the card if it is open. Returns true when it was.
func dismiss() -> bool:
	if not _card.visible:
		return false
	_close()
	return true
