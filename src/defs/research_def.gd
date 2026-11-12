class_name ResearchDef
extends ContentDef
## Research node, bought with insights. branch "" is shared; named branches are mutually exclusive.

@export var cost: float = 1.0
@export var prereqs: PackedStringArray = PackedStringArray()
@export var branch: String = ""
@export var effects: Array[Dictionary] = []
