class_name RivalDef
extends ContentDef
## Rival lab. Progresses in real game-time; launches after launch_hours (jittered by RNG).

@export var launch_hours: float = 6.0
@export var outpace_stage: int = 1  # AGI stage (1-based) this rival races toward; clearing it first outpaces the rival
