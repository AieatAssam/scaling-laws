class_name PanelResearchTree
extends VBoxContainer
## Research list grouped by branch. Each row shows cost, effects, status and a Buy button.

const BRANCH_NAMES := {
	"": "General", "dense": "Dense branch", "moe": "Mixture-of-experts branch", "ssm": "State-space branch",
}

var _rows: Dictionary = {}   # id -> {buy: Button, status: Label, cost: float}
var _on_result: Callable


func build(on_result: Callable) -> void:
	_on_result = on_result
	add_theme_constant_override("separation", 8)
	var order: Array = []
	var groups: Dictionary = {}
	for d in Content.get_all("research"):
		var b: String = d.branch
		if not groups.has(b):
			groups[b] = []
			order.append(b)
		groups[b].append(d)
	for b in order:
		var box := PanelKit.section(self, BRANCH_NAMES.get(b, b), "research")
		for d in groups[b]:
			var id: String = d.id
			var c := PanelKit.card()
			box.add_child(c)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 4)
			c.add_child(v)
			v.add_child(PanelKit.label(d.title, PanelKit.BRIGHT))
			var fx: Array[String] = []
			for e in d.effects:
				fx.append("×%s %s" % [PanelText.num(e["value"]), e["key"]])
			var pre: Array[String] = []
			for p in d.prereqs:
				pre.append(PanelText.title_of("research", p))
			var info := "Cost %s insights" % PanelText.num(d.cost)
			info += " · Effects: " + (", ".join(fx) if not fx.is_empty() else "none")
			if not pre.is_empty():
				info += " · Needs: " + ", ".join(pre)
			v.add_child(PanelKit.label(info, PanelKit.MUTED))
			var status := PanelKit.label("", PanelKit.MUTED)
			v.add_child(status)
			var buy := PanelKit.button("", Callable(), false)
			buy.pressed.connect(func() -> void: _buy(id))
			v.add_child(buy)
			_rows[id] = {"buy": buy, "status": status, "cost": float(d.cost)}
	refresh()


func refresh() -> void:
	var s: GameState = Game.state
	for id in _rows:
		var row: Dictionary = _rows[id]
		var owned: bool = id in s.run["layers"][2]["research"]
		var reason: String = Sim.research_blocker(s, id)
		if reason.begins_with("requires "):
			reason = "Needs " + PanelText.title_of("research", reason.substr(9))
		row.status.text = "Owned." if owned else reason
		row.buy.text = "Owned" if owned else "Buy for %s insights" % PanelText.num(row.cost)
		row.buy.disabled = owned or reason != ""


func _buy(id: String) -> void:
	var r: Dictionary = Game.research(id)
	_on_result.call(r, "Researched %s." % PanelText.title_of("research", id))
	if r.get("ok", false):
		PanelKit.pop(_rows[id].buy)
