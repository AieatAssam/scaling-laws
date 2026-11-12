extends SceneTree
const BigNum = preload("res://src/core/big_num.gd")
func _initialize() -> void:
	var a = BigNum.new(1234)
	assert(a.format() == "1.23K")
	assert(a.add(BigNum.new(766)).compare(BigNum.new(2, 3)) == 0)
	assert(BigNum.new(-2, 3).compare(BigNum.new(-1, 3)) == -1)
	assert(abs(BigNum.new(9, 8).square_root().mantissa - 3.0) < 0.000001)
	assert(BigNum.new(-0.2).floor_value().compare(BigNum.new(-1)) == 0)
	assert(BigNum.from_json(a.to_json()).compare(a) == 0)
	print("BigNum self-check passed")
	quit()
