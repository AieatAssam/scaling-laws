class_name AgiStageDef
extends ContentDef
## One step of the AGI sequence. Stages advance in `order` once all `conditions` hold.

@export var order: int = 0
@export var conditions: Array[Dictionary] = []
