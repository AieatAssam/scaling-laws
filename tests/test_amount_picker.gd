extends GutTest
## AmountPicker: the x1 / x10 / MAX row shared by the producers and hiring panels. Selection, the change signal and
## cycling (the B hotkey), without a scene tree.


func _picker(choices: Array) -> AmountPicker:
	return AmountPicker.new().setup("Buy", choices, "Buy")


func test_starts_on_the_first_choice() -> void:
	var p := _picker([1, 10, -1])
	assert_eq(p.amount, 1)
	p.free()


func test_cycle_steps_through_the_choices_and_wraps() -> void:
	var p := _picker([1, 10, -1])
	var seen := []
	p.changed.connect(func(a: int) -> void: seen.append(a))
	p.cycle()
	p.cycle()
	p.cycle()
	assert_eq(seen, [10, -1, 1], "x10, MAX, then back to x1")
	assert_eq(p.amount, 1)
	p.free()


func test_select_emits_unless_silent() -> void:
	var p := _picker([1, 5, -1])
	var seen := []
	p.changed.connect(func(a: int) -> void: seen.append(a))
	p.select(-1)
	assert_eq(p.amount, -1, "MAX is a valid choice")
	p.select(5, false)
	assert_eq(p.amount, 5)
	assert_eq(seen, [-1], "the silent select does not emit")
	p.free()
