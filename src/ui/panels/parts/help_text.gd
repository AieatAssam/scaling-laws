class_name HelpText
## Turns help article markup into RichTextLabel BBCode. Static, driven by content and a state; never reads the Game autoload.
##
## Markup, one item per line:
##   ## Heading        bold accent line
##   - item            bullet
##   [training]        live table of the three training options for this save
##   [layers]          the four reset layers and their gain-1 thresholds
##   anything else     paragraph
## Inline: {NAME} is a number from Sim or GameState; {NAME:pct}, {NAME:h} and {NAME:min} format it.
## {layer:k} is a layer's title and {threshold:k} its gain-1 threshold. [icon:name] is assets/icons/name.png and
## [badge:name] is assets/badges/name.png. An unknown token renders as <UNKNOWN:token>, which the content test catches.

const CONSTANT_SOURCES := ["res://src/core/sim.gd", "res://src/core/game_state.gd"]
const TRAIN_FRACS := [0.25, 0.5, 1.0]
const RE_TOKEN := "\\{([^{}]+)\\}"
const RE_IMAGE := "\\[(icon|badge):([a-z_]+)\\]"

static var _consts: Dictionary = {}


## Plain numeric constants from Sim and GameState, read by name so a rename shows as <UNKNOWN> instead of a parse error.
static func constants() -> Dictionary:
	if _consts.is_empty():
		for path in CONSTANT_SOURCES:
			_consts.merge(load(path).get_script_constant_map())
	return _consts


static func to_bbcode(body: String, content, state: GameState) -> String:
	var lines: Array[String] = []
	for raw in body.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			lines.append("")
		elif line == "[training]":
			lines.append_array(_training(state))
		elif line == "[layers]":
			lines.append_array(_layers(content))
		elif line.begins_with("## "):
			var accent := "#" + Fx.col(Fx.ACCENT).to_html(false)
			lines.append("[color=%s][b]%s[/b][/color]" % [accent, inline(line.substr(3), content, state)])
		elif line.begins_with("- "):
			lines.append("•  " + inline(line.substr(2), content, state))
		else:
			lines.append(inline(line, content, state))
	return "\n".join(lines)


static func inline(text: String, content, state: GameState) -> String:
	var out := _replace(text, RegEx.create_from_string(RE_IMAGE), func(m: RegExMatch) -> String:
		var folder := "icons" if m.get_string(1) == "icon" else "badges"
		return "[img=16x16]res://assets/%s/%s.png[/img]" % [folder, m.get_string(2)])
	return _replace(out, RegEx.create_from_string(RE_TOKEN), func(m: RegExMatch) -> String:
		return _token(m.get_string(1), content))


static func _replace(text: String, re: RegEx, fn: Callable) -> String:
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last) + String(fn.call(m))
		last = m.get_end()
	return out + text.substr(last)


static func _token(tok: String, content) -> String:
	var parts := tok.split(":")
	if parts.size() == 2 and parts[0] in ["layer", "threshold"]:
		var ld = _layer(content, int(parts[1]))
		if ld != null:
			return ld.title if parts[0] == "layer" else BigNum.from_float(ld.threshold).format()
	elif constants().get(parts[0]) is float or constants().get(parts[0]) is int:
		return _fmt(float(constants()[parts[0]]), parts[1] if parts.size() == 2 else "")
	return "<UNKNOWN:%s>" % tok


static func _fmt(v: float, how: String) -> String:
	match how:
		"pct":
			return _num(v * 100.0) + "%"
		"h":
			return _num(v / 3600.0) + " h"
		"min":
			return _num(v / 60.0) + " min"
	return _num(v)


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.01))


static func _layer(content, k: int):
	for ld in content.get_all("layers"):
		if ld.index == k:
			return ld
	return null


## Live options: what each share of compute would spend, its fail chance and the compute needed to start it.
static func _training(state: GameState) -> Array[String]:
	var out: Array[String] = ["You hold %s compute. Each option spends a share of it:" % state.cur("compute").format()]
	for f in TRAIN_FRACS:
		var p := Sim.training_preview(state, f)
		out.append("- %s of compute: spends %s, %s chance to fail, needs %s compute in stock" % [
			_num(f * 100.0) + "%", (p["spend"] as BigNum).format(),
			_num(float(p["fail_chance"]) * 100.0) + "%", (p["min_compute"] as BigNum).format()])
	return out


static func _layers(content) -> Array[String]:
	var out: Array[String] = []
	for ld in content.get_all("layers"):
		out.append("- %s: gain 1 at %s cash earned, about %s h per cycle, grants %s" % [
			ld.title, BigNum.from_float(ld.threshold).format(), _num(ld.target_hours), ld.currency])
	return out
