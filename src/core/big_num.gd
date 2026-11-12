class_name BigNum
extends RefCounted
## Value = mantissa * 10^exponent. Mantissa in [1, 10) in magnitude (sign on mantissa), or 0.
## Immutable: every operation returns a new BigNum.

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

## How format() writes a value. Set from the player's setting by Game.apply_settings (a display choice only).
enum Notation { SUFFIX, SCIENTIFIC, ENGINEERING }
static var notation: Notation = Notation.SUFFIX

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


## Map a saved setting key ("suffix", "scientific", "engineering") to a Notation; anything else is suffix.
static func notation_from_key(key: String) -> Notation:
	match key:
		"scientific":
			return Notation.SCIENTIFIC
		"engineering":
			return Notation.ENGINEERING
	return Notation.SUFFIX


## Suffix notation up to Dc, then scientific ("1.23e36"). Scientific is always "d.dde<n>";
## engineering uses exponents that are multiples of three ("123.40e12").
func format() -> String:
	if mantissa == 0.0:
		return "0"
	if notation == Notation.SCIENTIFIC:
		return _sci()
	if notation == Notation.ENGINEERING:
		return _eng()
	if exponent < -2:
		return _sci()
	var group := maxi(exponent, 0) / 3
	var m := mantissa * pow(10.0, exponent - group * 3)
	# Two-decimal rounding can reach 1000 (999.999K): roll over to the next suffix instead.
	if roundf(absf(m) * 100.0) >= 100000.0 and group + 1 < SUFFIXES.size():
		group += 1
		m /= 1000.0
	if group < SUFFIXES.size():
		return "%.2f%s" % [m, SUFFIXES[group]]
	return _sci()


## "d.dde<exp>", rolling over when rounding reaches 10.00.
func _sci() -> String:
	var sm := mantissa
	var se := exponent
	if roundf(absf(sm) * 100.0) >= 1000.0:
		sm /= 10.0
		se += 1
	return "%.2fe%d" % [sm, se]


## "ddd.dde<exp>" with exp a multiple of three, rolling over when rounding reaches 1000.
func _eng() -> String:
	var group := int(floor(float(exponent) / 3.0))
	var m := mantissa * pow(10.0, exponent - group * 3)
	if roundf(absf(m) * 100.0) >= 100000.0:
		group += 1
		m /= 1000.0
	return "%.2fe%d" % [m, group * 3]


func to_json() -> Dictionary:
	return {"mantissa": mantissa, "exponent": exponent}


static func from_json(data: Dictionary) -> BigNum:
	return BigNum.new(float(data.get("mantissa", 0.0)), int(data.get("exponent", 0)))
