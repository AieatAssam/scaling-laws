class_name UpgradeDef
extends ContentDef
## Lab upgrade: bought once with cash, for the current run only (a Funding Round wipes it, like producers).
## `kind` picks the effect (see Upgrades):
##   double        tier `target` makes x(1 + value) output (value 1.0 = x2)
##   synergy       tier `target` gets +value of its output per unit of tier `source` owned (capped at +100%)
##   cost          tier `target` costs (1 - value) of its price
##   revenue       cash x(1 + value)
##   train_speed   training runs take (1 - value) of their seconds

## Position in the upgrade list (ties sort by id).
@export var order: int = 0
## Cash price, one time.
@export var cost: float = 100.0
@export var kind: String = "double"
## Producer id the upgrade applies to ("" for revenue and train_speed).
@export var target: String = ""
## Synergy only: the producer whose owned units feed `target`.
@export var source: String = ""
@export var value: float = 1.0
## Unlock conditions (owned_gte on the tier, usually). Empty means always available.
@export var conditions: Array[Dictionary] = []
