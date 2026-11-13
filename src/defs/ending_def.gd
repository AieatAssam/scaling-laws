class_name EndingDef
extends ContentDef
## Final outcome. Checked in `order` after the last AGI stage; the first whose conditions all hold wins.

@export var order: int = 0
@export var conditions: Array[Dictionary] = []
@export var method: String = ""  # the AGI method that wins this ending: full, redteam or ship
