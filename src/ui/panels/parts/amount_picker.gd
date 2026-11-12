class_name AmountPicker
extends HBoxContainer
## The "x1 / x10 / MAX" row shared by the producers and hiring panels. Each button is a toggle in one ButtonGroup.
## -1 in `choices` means MAX (as many as the player can afford). Owners read `amount` and listen to `changed`.

signal changed(amount: int)

var amount := 1
var _choices: Array = []
var _btns := {}  # amount -> Button


## Builds the row: a `label` (e.g. "Buy"), then one toggle per choice. `verb` names the action in the tooltips.
func setup(label: String, choices: Array, verb: String) -> AmountPicker:
	_choices = choices
	add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = label
	lbl.theme_type_variation = &"MicroDim"
	add_child(lbl)
	var group := ButtonGroup.new()
	for a in choices:
		var b := Button.new()
		b.text = "x%d" % a if a > 0 else "MAX"
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, PanelKit.TOUCH_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(select.bind(a))
		if a < 0:
			Tip.attach(b, "%s as many as you can afford per tap.\nApplies to every %s button in this panel." % [verb, verb.to_lower()])
		else:
			Tip.attach(b, "%s %d per tap.\nApplies to every %s button in this panel." % [verb, a, verb.to_lower()])
		add_child(b)
		_btns[a] = b
	amount = int(choices[0])
	(_btns[amount] as Button).button_pressed = true
	return self


## Chooses `a` (one of the choices). Emits `changed` unless `emit` is false.
func select(a: int, emit := true) -> void:
	amount = a
	(_btns[a] as Button).button_pressed = true
	if emit:
		changed.emit(a)


## Moves to the next choice, wrapping after the last. The B hotkey uses this.
func cycle() -> void:
	var i := _choices.find(amount)
	select(int(_choices[(i + 1) % _choices.size()]))
