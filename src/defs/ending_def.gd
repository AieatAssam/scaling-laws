class_name EndingDef
extends ContentDef
## Final outcome. Checked in `order` after the last AGI stage; the first whose conditions all hold wins.

@export var order: int = 0
@export var conditions: Array[Dictionary] = []
@export var method: String = ""  # the AGI method that wins this ending: full, redteam or ship
@export var legacy_payout: float = 1.0  # legacy added when the run ends this way
@export var epilogue: String = ""  # shown under the description on the ending screen
