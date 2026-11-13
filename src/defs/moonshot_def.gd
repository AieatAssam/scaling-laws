class_name MoonshotDef
extends ContentDef
## Long real-time project on the Paradigm tab. Starts for `breakthroughs` and `cash`, runs for `hours` of game time
## (offline too, at full speed), then its `effects` apply once. Passive rewards are read by id in Moonshots.

@export var hours: float = 4.0
@export var breakthroughs: float = 0.0
@export var cash: float = 0.0
## Moonshot ids that must be done first.
@export var prereqs: Array[String] = []
## Unlock conditions (benchmark_unlocked gates). All must hold.
@export var conditions: Array[Dictionary] = []
## Effects applied once on completion (Rules.apply). Most rewards are passive and need none.
@export var effects: Array[Dictionary] = []
