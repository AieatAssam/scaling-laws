class_name ChallengeDef
extends ContentDef
## Regulation challenge. At the end of `duration`, `goal` is checked: reward applies on success, penalty on failure.

@export var duration: float = 3600.0
@export var goal: Array[Dictionary] = []
@export var reward: Array[Dictionary] = []
@export var penalty: Array[Dictionary] = []
