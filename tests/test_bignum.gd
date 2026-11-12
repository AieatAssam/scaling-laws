extends GutTest
## BigNum: normalisation, arithmetic, comparison, powers, roots, floor, formatting, JSON, edge values.

const Support := preload("res://tests/support.gd")


func _near(got: BigNum, expected: float, rel: float = 1e-9) -> void:
	assert_almost_eq(got.to_float(), expected, absf(expected) * rel + 1e-300)


func test_normalises_mantissa_into_one_to_ten() -> void:
	var cases := [[1234.0, 1.234, 3], [0.005, 5.0, -3], [-42.0, -4.2, 1], [1000.0, 1.0, 3], [10.0, 1.0, 1], [1.0, 1.0, 0]]
	for c in cases:
		var b := BigNum.new(c[0])
		assert_almost_eq(b.mantissa, c[1], 1e-9, "mantissa of %s" % c[0])
		assert_eq(b.exponent, c[2], "exponent of %s" % c[0])


func test_zero_is_canonical() -> void:
	for z in [BigNum.new(), BigNum.new(0.0, 99), BigNum.new(-0.0), BigNum.new(3.0).mul_f(0.0)]:
		assert_true(z.is_zero())
		assert_eq(z.exponent, 0)
		assert_eq(z.format(), "0")
		assert_eq(z.log10(), -INF)


func test_tiny_and_huge_values() -> void:
	var tiny := BigNum.new(1e-300)
	assert_eq(tiny.exponent, -300)
	var huge := BigNum.new(1e300)
	assert_eq(huge.exponent, 300)
	var sum := huge.add(huge)
	assert_eq(sum.exponent, 300)
	_near(sum, 2e300)
	# A value 1e40 times larger swallows 1 entirely.
	assert_eq(BigNum.new(1, 40).add(BigNum.new(1.0)).compare(BigNum.new(1, 40)), 0)


func test_add_and_subtract() -> void:
	_near(BigNum.new(1e6).add(BigNum.new(5e6)), 6e6)
	_near(BigNum.new(5e3).subtract(BigNum.new(2e3)), 3e3)
	assert_true(BigNum.new(1e3).subtract(BigNum.new(1e3)).is_zero())
	assert_eq(BigNum.new(2e3).subtract(BigNum.new(5e3)).compare(BigNum.new(-3e3)), 0)


func test_multiply_divide_and_mul_f() -> void:
	_near(BigNum.new(2e3).multiply(BigNum.new(3e4)), 6e7)
	_near(BigNum.new(6e7).divide(BigNum.new(3e4)), 2e3)
	_near(BigNum.new(1.5e3).mul_f(2.0), 3e3)
	assert_true(BigNum.new(7e3).multiply(BigNum.new()).is_zero())


func test_divide_by_zero_is_reported() -> void:
	var r := BigNum.new(1.0).divide(BigNum.new())
	assert_push_error("division by zero")
	assert_true(r.is_zero())


func test_compare_orders_signs_and_magnitudes() -> void:
	var cases := [
		[1e3, 999.0, 1], [999.0, 1e3, -1], [1e3, 1e3, 0], [-1e3, -999.0, -1], [-1.0, 1.0, -1],
		[0.0, -1.0, 1], [0.0, 0.0, 0], [2e5, 3e4, 1], [3e4, 2e5, -1], [-0.5, 0.0, -1],
	]
	for c in cases:
		assert_eq(BigNum.new(c[0]).compare(BigNum.new(c[1])), c[2], "compare %s %s" % [c[0], c[1]])
	assert_true(BigNum.new(5.0).gte(BigNum.new(5.0)))
	assert_true(BigNum.new(4.0).lt(BigNum.new(5.0)))
	assert_false(BigNum.new(5.0).lt(BigNum.new(5.0)))


func test_non_finite_input_is_rejected() -> void:
	var b := BigNum.new(INF)
	assert_push_error("non-finite")
	assert_true(b.is_zero())


func test_power() -> void:
	_near(BigNum.new(2.0).power(10.0), 1024.0)
	_near(BigNum.new(1.0, 3).power(2.0), 1e6)
	_near(BigNum.new(4.0).power(0.5), 2.0)
	_near(BigNum.new(-2.0).power(3.0), -8.0)
	assert_true(BigNum.new().power(3.0).is_zero())


func test_power_keeps_huge_exponents() -> void:
	var p := BigNum.new(1.0, 100).power(3.0)
	assert_eq(p.exponent, 300)


func test_fractional_power_of_negative_is_rejected() -> void:
	var r := BigNum.new(-4.0).power(0.5)
	assert_push_error("fractional power")
	assert_true(r.is_zero())


func test_square_root() -> void:
	_near(BigNum.new(4.0).square_root(), 2.0)
	_near(BigNum.new(1.0, 2).square_root(), 10.0)
	_near(BigNum.new(9.0, 1).square_root(), sqrt(90.0))
	_near(BigNum.new(1.0, 300).square_root(), 1e150)
	assert_true(BigNum.new().square_root().is_zero())


func test_square_root_of_negative_is_rejected() -> void:
	var r := BigNum.new(-9.0).square_root()
	assert_push_error("square root of negative")
	assert_true(r.is_zero())


func test_floor_value() -> void:
	var cases := [[3.7, 3.0], [-3.2, -4.0], [0.5, 0.0], [-0.5, -1.0], [12345.9, 12345.0], [7.0, 7.0]]
	for c in cases:
		assert_eq(BigNum.new(c[0]).floor_value().to_float(), c[1], "floor %s" % c[0])
	assert_true(BigNum.new().floor_value().is_zero())
	var big := BigNum.new(1.0, 20)
	assert_eq(big.floor_value().compare(big), 0, "values with exponent >= 15 are already integers")


func test_format_suffix_then_scientific() -> void:
	var cases := {
		"0": BigNum.new(), "1.00": BigNum.new(1.0), "999.00": BigNum.new(999.0),
		"1.23K": BigNum.new(1234.0), "1.00M": BigNum.new(1.0, 6), "2.50B": BigNum.new(2.5, 9),
		"-1.23K": BigNum.new(-1234.0), "1.00Dc": BigNum.new(1.0, 33),
		"1.00e36": BigNum.new(1.0, 36), "1.50e-3": BigNum.new(1.5, -3), "0.50": BigNum.new(0.5),
	}
	for expected in cases:
		assert_eq(cases[expected].format(), expected)


func test_format_never_shows_a_rounded_up_group_one_short() -> void:
	# 999.999K rounds to 1000.00K; the suffix must roll over to M.
	assert_eq(BigNum.new(999999.0).format(), "1.00M")


func test_json_round_trip_is_exact() -> void:
	var values := [BigNum.new(), BigNum.new(1.0), BigNum.new(-3.5, 7), BigNum.new(2.2, -9), BigNum.new(1.7976931348623157, 300)]
	for b in values:
		var text := JSON.stringify(b.to_json(), "", true, true)
		var back := BigNum.from_json(JSON.parse_string(text))
		assert_eq(back.mantissa, b.mantissa, "mantissa survives %s" % text)
		assert_eq(back.exponent, b.exponent, "exponent survives %s" % text)


func test_from_json_defaults_to_zero() -> void:
	assert_true(BigNum.from_json({}).is_zero())
	assert_eq(BigNum.from_json({"mantissa": 2.0, "exponent": 3}).to_float(), 2000.0)


func test_copy_is_independent() -> void:
	var a := BigNum.new(5.0)
	var b := a.copy()
	b.mantissa = 9.0
	assert_eq(a.mantissa, 5.0)
	assert_true(Support.bn_near(a.add(BigNum.new(0.0)), a))
