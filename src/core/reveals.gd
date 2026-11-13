class_name Reveals
extends RefCounted
## One-time "New: <System>" cards (pure, no UI). A reveal is due once its conditions hold and it has not been shown
## (persist.seen_reveals). Each reveal's conditions mirror its Help topic, so the card and the topic appear together.
## "Constraints" is the regulation challenges, the only constraint system in the game.

const LIST := [
	{"id": "hiring", "title": "Hiring", "topic": "funding",
		"body": "Equity hires staff. Each hire adds to its own bonus, to training, or to cash or compute. Hire 1, 5 or the most you can afford.",
		"conditions": [{"type": "time_played_gte", "value": 1200.0}]},
	{"id": "research", "title": "Research tree", "topic": "generation",
		"body": "Architecture branches exclude each other. Picking one locks the others in its branch.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_funding_1"}]},
	{"id": "alignment", "title": "Alignment slider", "topic": "generation",
		"body": "Lower alignment buys raw capability: the less you hold back, the more compute your producers make. Below the safe line, debt builds each second, and any reset clears it.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_funding_1"}]},
	{"id": "automation", "title": "Automation", "topic": "paradigm",
		"body": "Automation buys producers, funds rounds, ships generations and trains models for you. Each one unlocks on the Paradigm tab.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_generation_1"}]},
	{"id": "moonshots", "title": "Moonshots", "topic": "moonshots",
		"body": "Moonshots are long projects on the Paradigm tab. Pay breakthroughs to start one; it runs in real time, even offline, and pays a permanent reward.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_paradigm_1"}]},
	{"id": "constraints", "title": "Constraints", "topic": "singularity",
		"body": "Regulation challenges set limits on a run. Start one from its card on the AGI tab.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_paradigm_1"}]},
	{"id": "rivals", "title": "Rivals", "topic": "singularity",
		"body": "Rival labs launch on a schedule and push back on your lead. Watch the AGI tab.",
		"conditions": [{"type": "benchmark_unlocked", "id": "reset_paradigm_1"}]},
	{"id": "agi", "title": "AGI sequence", "topic": "singularity",
		"body": "The AGI road has stages. Finish it and the run ends in one of three endings: aligned, rushed or open-sourced.",
		"conditions": [{"type": "resets_gte", "layer": 4, "value": 1}]},
	{"id": "training", "title": "Training", "topic": "training",
		"body": "Pick a run type on the Train tab. A run spends compute for a score and, on success, a cash burst.",
		"conditions": [{"type": "time_played_gte", "value": 600.0}]},
]


static func find(id: String) -> Dictionary:
	for r in LIST:
		if r["id"] == id:
			return r
	return {}


## Id of the first reveal that is due (its conditions hold and it has not been shown), or "".
static func next_due(s: GameState) -> String:
	var seen: Dictionary = s.persist["seen_reveals"]
	for r in LIST:
		if not seen.has(r["id"]) and Rules.check_all(s, r["conditions"]):
			return r["id"]
	return ""


static func is_seen(s: GameState, id: String) -> bool:
	return bool(s.persist["seen_reveals"].get(id, false))


static func mark_seen(s: GameState, id: String) -> void:
	s.persist["seen_reveals"][id] = true


## Run once per load (Game.start). Reveals already met count as seen, so a save from before this feature gets no burst
## of cards; only systems the player reaches from now on are announced.
static func seed(s: GameState) -> void:
	if bool(s.persist.get("reveals_seeded", false)):
		return
	for r in LIST:
		if Rules.check_all(s, r["conditions"]):
			mark_seen(s, r["id"])
	s.persist["reveals_seeded"] = true
