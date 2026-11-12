class_name StaffDef
extends ContentDef
## Hireable staff, paid in equity. Each hire adds bonus_per_hire to multiplier `bonus_key`.

@export var base_cost: float = 5.0
@export var cost_growth: float = 1.5
@export var bonus_key: String = ""
@export var bonus_per_hire: float = 0.1
## Each hire cuts training fail chance by this share (multiplicative, floored; see Sim.training_fail_factor).
@export var fail_per_hire: float = 0.0
