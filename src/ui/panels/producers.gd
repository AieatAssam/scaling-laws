class_name ProducersPanel
extends Control
## Compute producers. Shows owned tiers, the buyable tier and one locked teaser (silhouette, "???").
## Each row: room thumbnail, owned count, output/s, progress to the next milestone, and a buy button.
## The x1 / x10 / MAX selector sets how many each buy button buys.
## Above the producers: launch cards (timed boosts with cooldowns). Below them: lab upgrades (bought once with cash).

const AMOUNTS := [1, 10, -1]   # -1 = max affordable
const THUMB_SMALL := Vector2(96, 64)     # phone: half density of the 2x room art
const THUMB_WIDE := Vector2(192, 128)    # desktop: room art (192x128) drawn 1:1, every texel visible
const WIDE_PANEL := 440.0                # panel width from which the wide thumbnails are used

var _order: Array = []         # producer ids in tier order
var _rows := {}                # id -> {row, thumb, name, sub, bar, next, cost, buy}
var _result: Label
var _picker: AmountPicker
var _buyable := false
var _launch_flow: HFlowContainer
var _launch_hint: Label
var _launches := {}            # id -> {card, btn, bar, status, def}
var _upgrade_flow: HFlowContainer
var _upgrade_hint: Label
var _upgrade_owned: Label
var _upgrades := {}            # id -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)

	_result = Label.new()
	_result.theme_type_variation = &"MicroDim"
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_result)

	_picker = AmountPicker.new().setup("Buy", AMOUNTS, "Buy")
	_picker.changed.connect(func(_a: int) -> void: _refresh())
	page.add_child(_picker)

	var scroll := DragScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_build_launches(list)
	for d in Content.get_all("producers"):
		_order.append(d.id)
		var row := _row(d)
		list.add_child(row)
	_build_upgrades(list)

	var tm := Timer.new()
	tm.wait_time = 0.25
	tm.timeout.connect(_refresh)
	add_child(tm)
	tm.start()
	resized.connect(_fit_thumbs)
	_fit_thumbs()
	_refresh()


## Room thumbnails: full 2x size on desktop-width panels, half on phones.
func _fit_thumbs() -> void:
	var thumb_size := THUMB_WIDE if size.x >= WIDE_PANEL else THUMB_SMALL
	for id in _rows:
		(_rows[id]["thumb"] as TextureRect).custom_minimum_size = thumb_size


func _row(d) -> PanelContainer:
	var id: String = d.id
	var card := PanelKit.card()
	Tip.attach(card, Callable(self, "_tip").bind(id))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var thumb := TextureRect.new()
	thumb.texture = Fx.tex("res://assets/rooms/%s.png" % id, Vector2i(THUMB_WIDE))
	thumb.custom_minimum_size = THUMB_SMALL
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.add_child(thumb)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	top.add_child(mid)
	var name_lbl := Label.new()
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long names wrap on phones instead of clipping
	name_lbl.theme_type_variation = &"DimLabel"
	mid.add_child(name_lbl)
	var sub := Label.new()
	sub.theme_type_variation = &"MicroDim"
	sub.clip_text = true
	mid.add_child(sub)

	var prog := HBoxContainer.new()
	prog.add_theme_constant_override("separation", 6)
	v.add_child(prog)
	var bar := PanelKit.bar(PanelKit.TEAL)
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog.add_child(bar)
	var next := Label.new()
	next.theme_type_variation = &"MicroDim"
	next.clip_text = true
	next.custom_minimum_size.x = 120
	prog.add_child(next)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	v.add_child(bottom)
	var cost := Label.new()
	cost.theme_type_variation = &"MicroDim"
	cost.clip_text = true
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(cost)
	var buy := PanelKit.button("", Callable(), false)
	buy.custom_minimum_size = Vector2(120, PanelKit.TOUCH_H)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_END
	buy.pressed.connect(_buy.bind(id, buy))
	bottom.add_child(buy)

	_rows[id] = {"row": card, "thumb": thumb, "name": name_lbl, "sub": sub, "bar": bar, "next": next,
		"cost": cost, "buy": buy, "def": d}
	return card


## Tooltip for a producer row: output, share of production, next milestone, cost of the next 1 / 10 / max.
func _tip(id: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("producers", id)
	var title := PanelText.title_of("producers", id)
	if not Sim.producer_available(s, id):
		return "%s\nLocked. Needs %s first." % [title, PanelText.title_of("producers", _order[maxi(_order.find(id) - 1, 0)])]
	var owned := s.owned(id)
	var mult := Rules.mult(s, "compute")
	var own_raw := Sim.producer_raw_rate(s, id)
	var total_raw := Sim.raw_rate(s)
	var share := 0.0 if own_raw.is_zero() or total_raw.is_zero() else pow(10.0, own_raw.log10() - total_raw.log10())
	var lines: Array[String] = []
	lines.append(title)
	lines.append("Base %s/s per unit, ×%d owned." % [BigNum.from_float(float(d.base_output)).format(), owned])
	lines.append("Output now %s/s (%.0f%% of raw production, total ×%.2f compute)." % [
		own_raw.mul_f(mult).format(), share * 100.0, mult])
	var next_ms := -1
	var doublings := 0
	for ms in Sim.MILESTONES:
		if owned >= ms:
			doublings += 1
		elif next_ms < 0:
			next_ms = ms
	if next_ms > 0:
		lines.append("Next ×2 output at %d owned (%d more). Doubles output per milestone." % [next_ms, next_ms - owned])
	else:
		lines.append("All milestones reached: ×%d output from them." % (1 << doublings))
	var k := Game.max_affordable(id)
	lines.append("Buy 1: %s · Buy 10: %s · Buy max (%d): %s" % [
		Game.producer_cost(id, 1).format(), Game.producer_cost(id, 10).format(), k,
		Game.producer_cost(id, maxi(k, 1)).format()])
	return "\n".join(lines)


## B hotkey: the next amount in the x1 / x10 / MAX row.
func cycle_amount() -> void:
	_picker.cycle()


## Amount this row's button buys right now (max → affordable count, may be 0).
func _count_for(id: String) -> int:
	return Game.max_affordable(id) if _picker.amount < 0 else _picker.amount


func _refresh() -> void:
	var s: GameState = Game.state
	var mult := Rules.mult(s, "compute")
	# Tiers unlock in a chain, so the open tiers are a prefix of _order.
	var last_open := -1
	for i in _order.size():
		if Sim.producer_available(s, _order[i]):
			last_open = i
	_buyable = false
	for i in _order.size():
		var id: String = _order[i]
		var r: Dictionary = _rows[id]
		var d = r["def"]
		var shown := i <= last_open + 1
		(r["row"] as Control).visible = shown
		if not shown:
			continue
		var open := i <= last_open
		var owned := s.owned(id)
		(r["thumb"] as TextureRect).modulate = Color.WHITE if open else Fx.col(Fx.DISABLED)
		if not open:
			(r["name"] as Label).text = "???"
			(r["sub"] as Label).text = "Locked"
			(r["bar"] as ProgressBar).visible = false
			(r["next"] as Label).text = ""
			(r["cost"] as Label).text = "Needs %s" % PanelText.title_of("producers", _order[i - 1])
			(r["buy"] as Button).text = "Locked"
			(r["buy"] as Button).disabled = true
			continue

		# Milestones: each one reached doubles this tier's output.
		var m := 1
		var next_ms := -1
		for ms in Sim.MILESTONES:
			if owned >= ms:
				m *= 2
			elif next_ms < 0:
				next_ms = ms
		var rate := Sim.producer_raw_rate(s, id).mul_f(mult)
		(r["name"] as Label).text = str(d.title)
		(r["sub"] as Label).text = "×%d owned · %s/s" % [owned, rate.format()]
		var bar := r["bar"] as ProgressBar
		bar.visible = next_ms > 0
		if next_ms > 0:
			bar.max_value = next_ms
			bar.value = owned
			(r["next"] as Label).text = "Next ×2 at %d" % next_ms
		else:
			(r["next"] as Label).text = "Max milestones ×%d" % m

		var n := _count_for(id)
		var k := Game.max_affordable(id)
		var buy := r["buy"] as Button
		buy.disabled = n < 1 or k < n
		buy.text = "Buy %s" % ("max" if _picker.amount < 0 else str(_picker.amount))
		var shown_n := maxi(n, 1)
		(r["cost"] as Label).text = "Cost %s for %d" % [Game.producer_cost(id, shown_n).format(), shown_n]
		if _picker.amount < 0:
			buy.text = "Buy max (%d)" % n
		if not buy.disabled:
			_buyable = true
	_refresh_launches(s)
	_refresh_upgrades(s)


## Launch cards sit at the top of the list. Each shows once its conditions pass, with a cooldown bar and status.
func _build_launches(list: VBoxContainer) -> void:
	var box := PanelKit.section(list, "Launches", "breakthroughs")
	_launch_flow = HFlowContainer.new()
	_launch_flow.add_theme_constant_override("h_separation", 6)
	_launch_flow.add_theme_constant_override("v_separation", 6)
	box.add_child(_launch_flow)
	_launch_hint = PanelKit.label("Launches unlock as you grow.", PanelKit.DIM)
	box.add_child(_launch_hint)
	for d in Content.get_all("launches"):
		var card := PanelKit.card()
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.custom_minimum_size.x = 160
		Tip.attach(card, Callable(self, "_launch_tip").bind(d.id))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		card.add_child(v)
		var btn := PanelKit.button(str(d.title), _fire.bind(d.id))
		v.add_child(btn)
		var bar := PanelKit.bar(PanelKit.AMBER)
		bar.custom_minimum_size = Vector2(0, 6)
		bar.max_value = 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bar)
		var status := Label.new()
		status.theme_type_variation = &"MicroDim"
		status.clip_text = true
		v.add_child(status)
		_launch_flow.add_child(card)
		_launches[d.id] = {"card": card, "btn": btn, "bar": bar, "status": status, "def": d}


func _refresh_launches(s: GameState) -> void:
	var any := false
	for id in _launches:
		var r: Dictionary = _launches[id]
		var d = r["def"]
		var shown := Rules.check_all(s, d.conditions)
		(r["card"] as Control).visible = shown
		if not shown:
			continue
		any = true
		var left := Launches.cooldown_left(s, id)
		var reason := Launches.blocker(s, id)
		(r["bar"] as ProgressBar).value = 1.0 - clampf(left / float(d.cooldown), 0.0, 1.0)  # fills as the cooldown runs out
		(r["status"] as Label).text = ("%s left" % PanelKit.hms(left)) if left > 0.0 else ("Ready" if reason == "" else reason)
		(r["btn"] as Button).disabled = reason != ""
	_launch_hint.visible = not any


func _fire(id: String) -> void:
	var r := Game.fire_launch(id)
	_report(r, "Launched %s." % str(Content.get_def("launches", id).title))
	_refresh()


## Exact numbers for a launch: effects, cost, cooldown, and time left.
func _launch_tip(id: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("launches", id)
	var lines: Array[String] = [str(d.title)]
	for e in d.effects:
		if e.get("type", "") == "timed_mod":
			lines.append("Effect: %s x%.2f for %s." % [_key_label(str(e["key"])), float(e["value"]), PanelKit.hms(float(e["seconds"]))])
	lines.append("Cost: %s %s (%.0f%% of %s)." % [Launches.cost(s, id).format(), d.cost_currency,
		float(d.cost_share) * 100.0, d.cost_currency])
	lines.append("Cooldown: %s." % PanelKit.hms(float(d.cooldown)))
	var left := Launches.cooldown_left(s, id)
	if left > 0.0:
		lines.append("Ready in %s." % PanelKit.hms(left))
	return "\n".join(lines)


func _key_label(key: String) -> String:
	match key:
		"cash":
			return "cash income"
		"compute":
			return "compute"
		"train_speed":
			return "training speed"
	return key


## Upgrades section at the bottom of the list: buttons for unlocked, unbought upgrades; bought ones are a count.
func _build_upgrades(list: VBoxContainer) -> void:
	var box := PanelKit.section(list, "Upgrades", "research")
	_upgrade_owned = Label.new()
	_upgrade_owned.theme_type_variation = &"MicroDim"
	box.add_child(_upgrade_owned)
	_upgrade_flow = HFlowContainer.new()
	_upgrade_flow.add_theme_constant_override("h_separation", 6)
	_upgrade_flow.add_theme_constant_override("v_separation", 6)
	box.add_child(_upgrade_flow)
	_upgrade_hint = PanelKit.label("", PanelKit.DIM)
	box.add_child(_upgrade_hint)
	for d in Content.get_all("upgrades"):
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, PanelKit.TOUCH_H)
		b.clip_text = true
		b.text = "%s  %s" % [str(d.title), BigNum.from_float(float(d.cost)).format()]
		b.pressed.connect(_buy_upgrade.bind(d.id, b))
		Tip.attach(b, Callable(self, "_upgrade_tip").bind(d.id))
		_upgrade_flow.add_child(b)
		_upgrades[d.id] = b


func _refresh_upgrades(s: GameState) -> void:
	var owned := Upgrades.owned_ids(s).size()
	_upgrade_owned.text = "%d owned of %d" % [owned, _upgrades.size()]
	var shown := 0
	for id in _upgrades:
		var b := _upgrades[id] as Button
		var reason := Upgrades.blocker(s, id)
		b.visible = not Upgrades.is_owned(s, id) and not reason.begins_with("locked")
		if not b.visible:
			continue
		shown += 1
		b.disabled = reason != ""
		if reason == "":
			_buyable = true
	_upgrade_hint.text = "All upgrades bought." if owned >= _upgrades.size() else "Next upgrades unlock as you grow."
	_upgrade_hint.visible = shown == 0


func _buy_upgrade(id: String, btn: Button) -> void:
	var r := Game.buy_upgrade(id)
	_report(r, "Bought %s." % str(Content.get_def("upgrades", id).title))
	if r.get("ok", false):
		Fx.pop(btn)
	_refresh()


## Exact effect of an upgrade (its own factor, or the synergy at the current owned count), cost and status.
func _upgrade_tip(id: String) -> String:
	var s: GameState = Game.state
	var d = Content.get_def("upgrades", id)
	var lines: Array[String] = [str(d.title), str(d.description)]
	var v := float(d.value)
	match str(d.kind):
		"double":
			lines.append("Effect: %s output x%.2f." % [PanelText.title_of("producers", d.target), 1.0 + v])
		"synergy":
			var now := minf(Upgrades.SYNERGY_CAP, v * s.owned(str(d.source)))
			lines.append("Effect: +%.0f%% %s output per %s owned, up to +%.0f%%. Now +%.0f%%." % [v * 100.0,
				PanelText.title_of("producers", d.target), PanelText.title_of("producers", d.source),
				Upgrades.SYNERGY_CAP * 100.0, now * 100.0])
		"cost":
			lines.append("Effect: %s costs -%.0f%%." % [PanelText.title_of("producers", d.target), v * 100.0])
		"revenue":
			lines.append("Effect: +%.0f%% cash from inference (compute to cash)." % (v * 100.0))
		"train_speed":
			lines.append("Effect: training runs take -%.0f%% seconds." % (v * 100.0))
	lines.append("Cost: %s cash." % BigNum.from_float(float(d.cost)).format())
	var reason := Upgrades.blocker(s, id)
	lines.append(reason if reason != "" else "Ready to buy.")
	return "\n".join(lines)


func _buy(id: String, btn: Button) -> void:
	var r := Game.buy_producer(id, _picker.amount)
	var ok: bool = r.get("ok", false)
	var n: int = r.get("count", _picker.amount)
	_report(r, "Bought %d %s." % [n, PanelText.title_of("producers", id)])
	if ok:
		Fx.pop(btn)
	_refresh()


func _report(r: Dictionary, ok_text: String) -> void:
	var ok: bool = r.get("ok", false)
	_result.text = ok_text if ok else str(r.get("reason", "Failed."))
	_result.add_theme_color_override("font_color", Fx.col(Fx.GREEN if ok else Fx.RED))


func is_unlocked() -> bool:
	return true


func wants_attention() -> bool:
	return _buyable
