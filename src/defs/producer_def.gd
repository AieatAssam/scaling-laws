class_name ProducerDef
extends ContentDef
## One of 12 compute producers. Cost of the next unit = base_cost * 1.15^owned.

@export var order: int = 0
@export var base_cost: float = 10.0
## Compute per second per owned unit, before multipliers.
@export var base_output: float = 1.0
