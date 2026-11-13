class_name PanelText
## Plain-text descriptions of content conditions, effects and multipliers, for the panels.


static func title_of(type: String, id: String) -> String:
	var root := (Engine.get_main_loop() as SceneTree).root
	var d = root.get_node("Content").get_def(type, id)
	return d.title if d != null else id


static func cur_name(id: String) -> String:
	return id.capitalize()


static func layer_title(k: int) -> String:
	var root := (Engine.get_main_loop() as SceneTree).root
	var d = Sim.layer_def(root.get_node("Game").state, k)
	return d.title if d != null else "Layer %d" % k


static func num(v: Variant) -> String:
	var f := float(v)
	if absf(f) >= 1000.0:
		return BigNum.from_float(f).format()
	return ("%.2f" % f).rstrip("0").rstrip(".")


static func signed(v: Variant) -> String:
	return ("+" if float(v) >= 0.0 else "") + num(v)


## Condition text, e.g. "Compute >= 1000".
static func condition(c: Dictionary) -> String:
	match c["type"]:
		"owned_gte":
			return "%d× %s" % [int(c["value"]), title_of("producers", c["id"])]
		"currency_gte":
			return "%s >= %s" % [cur_name(c["id"]), num(c["value"])]
		"resets_gte":
			return "%s done" % layer_title(int(c["layer"]))
		"training_best_gte":
			return "Best training score >= %s" % num(c["value"])
		"staff_gte":
			return "%d %s hired" % [int(c["value"]), title_of("staff", c["id"])]
		"research_has":
			return "Research: %s" % title_of("research", c["id"])
		"slider_gte":
			return "Alignment >= %s" % PanelKit.pct(float(c["value"]))
		"time_played_gte":
			return "Played >= %s" % PanelKit.hms(float(c["value"]))
		"benchmark_unlocked":
			return "Benchmark: %s" % title_of("benchmarks", c["id"])
		"flag_set":
			return "Flag: %s" % String(c["id"]).capitalize()
		"debt_gte":
			return "Debt >= %s" % num(c["value"])
		"compute_rate_gte":
			return "Compute >= %s/s" % BigNum.from_float(float(c["value"])).format()
	return str(c)


## Condition text plus the live value, and whether it holds now: {text, met}.
static func condition_now(s: GameState, c: Dictionary) -> Dictionary:
	var text := condition(c)
	match c["type"]:
		"currency_gte":
			text += " (now %s)" % s.cur(c["id"]).format()
		"owned_gte":
			text += " (now %d)" % s.owned(c["id"])
		"training_best_gte":
			text += " (now %.2f)" % float(s.run["layers"][2]["best"])
		"slider_gte":
			text += " (now %s)" % PanelKit.pct(float(s.run["slider"]))
		"debt_gte":
			text += " (now %.1f)" % float(s.run["layers"][0]["debt"])
	return {"text": text, "met": Rules.check(s, c)}


## Effect text, e.g. "×1.05 Compute forever".
static func effect(e: Dictionary) -> String:
	match e["type"]:
		"add_currency":
			return "%s %s" % [signed(e["value"]), cur_name(e["id"])]
		"add_debt":
			return "%s debt" % signed(e["value"])
		"add_slider":
			return "%+d%% alignment" % roundi(float(e["value"]) * 100.0)
		"add_flag":
			return "Sets flag: %s" % String(e["id"]).capitalize()
		"timed_mod":
			return "×%s %s for %s" % [num(e["value"]), e["key"], PanelKit.hms(float(e["seconds"]))]
		"run_mult":
			return "×%s %s this run" % [num(e["value"]), e["key"]]
		"perm_mult":
			return "×%s %s forever" % [num(e["value"]), e["key"]]
		"rival_progress":
			return "%s progress %+d%%" % [title_of("rivals", e["id"]), roundi(float(e["value"]) * 100.0)]
	return str(e)


static func effects(list: Array) -> String:
	var parts: Array[String] = []
	for e in list:
		parts.append(effect(e))
	return ", ".join(parts) if not parts.is_empty() else "nothing"


static func conditions(list: Array) -> String:
	var parts: Array[String] = []
	for c in list:
		parts.append(condition(c))
	return "; ".join(parts) if not parts.is_empty() else "none"
