class_name TrainingRunDef
extends ContentDef
## One training run type (content/training_runs/*.tres). Score = log10(spend) x training x score_mult x roll.

## Position in the Train tab and in the help table (ties sort by id).
@export var order: int = 0
## Share of current compute spent up front, 0..1.
@export var spend_share: float = 0.5
## Run length in seconds.
@export var seconds: float = 60.0
## Chance the run fails before staff reduce it (see Sim.training_fail_factor).
@export var fail_chance: float = 0.12
## Multiplies the run's score: bigger, riskier runs score higher.
@export var score_mult: float = 1.0
