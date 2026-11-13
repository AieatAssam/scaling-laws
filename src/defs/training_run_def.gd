class_name TrainingRunDef
extends ContentDef
## One training run type (content/training_runs/*.tres). Score = log10(spend) x training x score_mult x roll.
## A success also pays a cash burst of revenue_seconds x the cash income rate (Sim._train_tick).

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
## Cash burst on success, in seconds of current cash income (0 = none). Failure pays nothing.
@export var revenue_seconds: float = 0.0
## Sim.pick_training chases this run only when its predicted score beats the generation best by this share.
## Risky runs ask for more (0.1); a safe run only has to match the best (0).
@export var chase_margin: float = 0.1
