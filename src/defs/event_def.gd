class_name EventDef
extends ContentDef
## Random event. Eligible when all `conditions` hold; picked by weight. `choices` each hold {label, effects}.

## One of: rival_launch, regulation, poaching, incident, breakthrough, media, funding, outage.
@export var category: String = "incident"
@export var weight: float = 1.0
## Seconds before the same event can fire again after it is resolved.
@export var cooldown: float = 1800.0
@export var conditions: Array[Dictionary] = []
@export var choices: Array[Dictionary] = []
