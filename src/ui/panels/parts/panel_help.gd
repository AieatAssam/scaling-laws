class_name PanelHelp
## "?" button that opens the Help tab on one topic. The shell is in the "shell" group and runs open_help(topic).


static func button(topic: String) -> Button:
	var b := Button.new()
	b.text = "?"
	b.custom_minimum_size = Vector2(PanelKit.TOUCH_H, PanelKit.TOUCH_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void: b.get_tree().call_group("shell", "open_help", topic))
	Tip.attach(b, "Help\nOpen the Help tab on this topic.")
	return b
