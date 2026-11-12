extends GutTest
## Number notation: BigNum.format in suffix, scientific and engineering modes, the setting key mapping, and the
## saved default (a save without the key gets "suffix" from the key-by-key fill).

const Support := preload("res://tests/support.gd")
const N := BigNum.Notation

var _content: Node


func before_each() -> void:
	_content = Support.make_content()


func after_each() -> void:
	BigNum.notation = N.SUFFIX
	_content.free()


func test_suffix_is_the_default() -> void:
	assert_eq(BigNum.notation, N.SUFFIX)
	assert_eq(BigNum.new(1.234e14).format(), "123.40T")
	assert_eq(BigNum.new(1234.0).format(), "1.23K")


func test_scientific_writes_mantissa_and_exponent() -> void:
	BigNum.notation = N.SCIENTIFIC
	assert_eq(BigNum.new(1.234e14).format(), "1.23e14")
	assert_eq(BigNum.new(1234.0).format(), "1.23e3")
	assert_eq(BigNum.new(1.0).format(), "1.00e0")
	assert_eq(BigNum.new(-2.5e-7).format(), "-2.50e-7")
	assert_eq(BigNum.new(9.999e5).format(), "1.00e6", "rounding to 10.00 rolls the exponent over")


func test_engineering_uses_exponents_that_are_multiples_of_three() -> void:
	BigNum.notation = N.ENGINEERING
	assert_eq(BigNum.new(1.234e14).format(), "123.40e12")
	assert_eq(BigNum.new(1234.0).format(), "1.23e3")
	assert_eq(BigNum.new(1.0e5).format(), "100.00e3")
	assert_eq(BigNum.new(1.0).format(), "1.00e0")
	assert_eq(BigNum.new(1.0e-5).format(), "10.00e-6")
	assert_eq(BigNum.new(9.99999e5).format(), "1.00e6", "rounding to 1000 rolls the exponent over")


func test_zero_is_zero_in_every_notation() -> void:
	for n in [N.SUFFIX, N.SCIENTIFIC, N.ENGINEERING]:
		BigNum.notation = n
		assert_eq(BigNum.new().format(), "0")


func test_the_numeric_value_does_not_change_with_notation() -> void:
	var v := BigNum.new(3.5e20)
	BigNum.notation = N.SCIENTIFIC
	var sci := v.format()
	BigNum.notation = N.ENGINEERING
	var eng := v.format()
	assert_eq(sci, "3.50e20")
	assert_eq(eng, "350.00e18")
	assert_eq(v.to_float(), 3.5e20, "format() leaves the value alone")


func test_setting_keys_map_to_modes() -> void:
	assert_eq(BigNum.notation_from_key("suffix"), N.SUFFIX)
	assert_eq(BigNum.notation_from_key("scientific"), N.SCIENTIFIC)
	assert_eq(BigNum.notation_from_key("engineering"), N.ENGINEERING)
	assert_eq(BigNum.notation_from_key("bogus"), N.SUFFIX, "unknown keys fall back to suffix")


func test_new_states_default_to_suffix() -> void:
	var s := Support.new_state(_content)
	assert_eq(String(s.persist["settings"]["notation"]), "suffix")


func test_old_save_without_the_key_gets_suffix() -> void:
	var d := Support.new_state(_content).to_dict()
	d["persist"]["settings"].erase("notation")
	var back := GameState.from_dict(_content, d)
	assert_eq(String(back.persist["settings"]["notation"]), "suffix")
	assert_true(back.persist["settings"].has("reduce_motion"), "the other settings keys are kept")
