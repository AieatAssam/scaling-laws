class_name HelpPanel
extends PanelBase
## Help: an accordion of topics from content/help. Locked topics show "???" and a hint. Unlocked ones show the
## article, re-rendered while open so the training options stay live. open_topic(id) is used by the "?" buttons.

var _order: Array = []   # topic ids in display order
var _rows := {}          # id -> {def, head, card, body, text, ok}
var _open := ""


func _build() -> void:
	page.add_child(PanelKit.caption("Tap a topic to read it. Locked topics show a hint."))
	for d in Game.state.db.get_all("help"):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		page.add_child(box)
		var head := PanelKit.button("", Callable())
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.clip_text = false   # titles wrap at 340 px instead of being cut off
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.pressed.connect(_toggle.bind(d.id))
		box.add_child(head)
		var card := PanelKit.card()
		card.visible = false
		var body := RichTextLabel.new()
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.selection_enabled = true
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_color_override("default_color", PanelKit.col(PanelKit.TEXT))
		card.add_child(body)
		box.add_child(card)
		_rows[d.id] = {"def": d, "head": head, "card": card, "body": body, "text": "", "ok": null}
		_order.append(d.id)


func _refresh() -> void:
	var s: GameState = Game.state
	for id in _order:
		var row: Dictionary = _rows[id]
		var d: HelpTopicDef = row["def"]
		var ok := Rules.check_all(s, d.conditions)
		var head: Button = row["head"]
		var is_open: bool = _open == id
		head.text = ("- " if is_open else "+ ") + (d.title if ok else "???")
		if row["ok"] != ok:
			row["ok"] = ok
			head.icon = Fx.tex_fit("res://assets/icons/%s.png" % d.icon, Vector2i(16, 16)) if ok else null
		(row["card"] as Control).visible = is_open
		if not is_open:
			continue
		var text := HelpText.to_bbcode(d.body, s.db, s) if ok else "[color=#%s]%s[/color]" % [
			Fx.col(Fx.MUTED).to_html(false), d.hint]
		if text != row["text"]:
			row["text"] = text
			(row["body"] as RichTextLabel).text = text


func _toggle(id: String) -> void:
	_open = "" if _open == id else id
	_refresh()


## Opens one topic and scrolls it into view. Called by the shell's open_help and by "?" buttons.
func open_topic(id: String) -> void:
	if not _rows.has(id):
		return
	_open = id
	_refresh()
	await get_tree().process_frame
	var sc := _scroll()
	if sc != null:
		sc.ensure_control_visible(_rows[id]["head"])


func _scroll() -> ScrollContainer:
	var n: Node = page
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	return n as ScrollContainer
