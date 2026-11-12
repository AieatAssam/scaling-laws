class_name BigNum
extends RefCounted
## Value = mantissa * 10^exponent. Mantissa in [1, 10) in magnitude (sign on mantissa), or 0.
## Immutable: every operation returns a new BigNum.

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

var mantissa: float
var exponent: int


func _init(m: float = 0.0, e: int = 0) -> void:
	if not is_finite(m):
		push_error("BigNum: non-finite mantissa")
		m = 0.0
	mantissa = m
	exponent = e
	_normalize()


func _normalize() -> void:
	if mantissa == 0.0:
		exponent = 0
		return
	var shift := int(floor(log(absf(mantissa)) / log(10.0)))
	mantissa /= pow(10.0, shift)
	exponent += shift
	if absf(mantissa) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	elif absf(mantissa) < 1.0:
		mantissa *= 10.0
		exponent -= 1


static func from_float(x: float) -> BigNum:
	return BigNum.new(x)


func copy() -> BigNum:
	return BigNum.new(mantissa, exponent)


func is_zero() -> bool:
	return mantissa == 0.0


func to_float() -> float:
	return mantissa * pow(10.0, exponent)


## log10 of the absolute value (-INF for zero).
func log10() -> float:
	if mantissa == 0.0:
		return -INF
	return log(absf(mantissa)) / log(10.0) + exponent


func add(o: BigNum) -> BigNum:
	if o.is_zero():
		return copy()
	if is_zero():
		return o.copy()
	if absi(exponent - o.exponent) > 30:
		return copy() if exponent > o.exponent else o.copy()
	var e := maxi(exponent, o.exponent)
	return BigNum.new(mantissa * pow(10.0, exponent - e) + o.mantissa * pow(10.0, o.exponent - e), e)


func subtract(o: BigNum) -> BigNum:
	return add(BigNum.new(-o.mantissa, o.exponent))


func multiply(o: BigNum) -> BigNum:
	return BigNum.new(mantissa * o.mantissa, exponent + o.exponent)


func divide(o: BigNum) -> BigNum:
	if o.is_zero():
		push_error("BigNum: division by zero")
		return BigNum.new()
	return BigNum.new(mantissa / o.mantissa, exponent - o.exponent)


## Multiply by a plain float factor.
func mul_f(f: float) -> BigNum:
	return BigNum.new(mantissa * f, exponent)


## -1, 0 or 1.
func compare(o: BigNum) -> int:
	var sa := signf(mantissa)
	var sb := signf(o.mantissa)
	if sa != sb:
		return 1 if sa > sb else -1
	if sa == 0.0:
		return 0
	var mag := 0
	if exponent != o.exponent:
		mag = 1 if exponent > o.exponent else -1
	elif absf(mantissa) != absf(o.mantissa):
		mag = 1 if absf(mantissa) > absf(o.mantissa) else -1
	return int(mag * sa)


func gte(o: BigNum) -> bool:
	return compare(o) >= 0


func lt(o: BigNum) -> bool:
	return compare(o) < 0


func power(p: float) -> BigNum:
	if is_zero():
		return BigNum.new()
	var neg := mantissa < 0.0
	if neg and fmod(absf(p), 1.0) != 0.0:
		push_error("BigNum: fractional power of negative number")
		return BigNum.new()
	var mag := (log(absf(mantissa)) / log(10.0) + exponent) * p
	var e := int(floor(mag))
	var sign_value := -1.0 if neg and fmod(absf(p), 2.0) == 1.0 else 1.0
	return BigNum.new(sign_value * pow(10.0, mag - e), e)


func square_root() -> BigNum:
	if mantissa < 0.0:
		push_error("BigNum: square root of negative number")
		return BigNum.new()
	if is_zero():
		return BigNum.new()
	# Exact split by exponent parity; going through log10 would turn sqrt(4) into 1.9999... and floor it wrongly.
	var m := mantissa
	var e := exponent
	if posmod(e, 2) != 0:
		m *= 10.0
		e -= 1
	return BigNum.new(sqrt(m), e / 2)


func floor_value() -> BigNum:
	if exponent >= 15:
		return copy()
	if exponent < 0:
		return BigNum.new(-1.0 if mantissa < 0.0 else 0.0)
	return BigNum.new(floor(mantissa * pow(10.0, exponent)))


## Suffix notation up to Dc, then scientific ("1.23e36").
func format() -> String:
	if mantissa == 0.0:
		return "0"
	if exponent < -2:
		return "%.2fe%d" % [mantissa, exponent]
	if exponent < 3:
		return "%.2f" % to_float()
	var group := exponent / 3
	if group < SUFFIXES.size():
		return "%.2f%s" % [mantissa * pow(10.0, exponent - group * 3), SUFFIXES[group]]
	return "%.2fe%d" % [mantissa, exponent]


func to_json() -> Dictionary:
	return {"mantissa": mantissa, "exponent": exponent}


static func from_json(data: Dictionary) -> BigNum:
	return BigNum.new(float(data.get("mantissa", 0.0)), int(data.get("exponent", 0)))
