class_name LaunchDef
extends ContentDef
## Launch action: pay a share of one currency, get a timed boost, then wait out a cooldown. Cooldowns live in
## run["launches"] and survive a Funding Round. `effects` are timed_mod entries (one per key at a time: replace).

@export var order: int = 0
## Currency paid, and the share of its current holding that the launch costs.
@export var cost_currency: String = "compute"
@export var cost_share: float = 0.0
## Seconds before the launch can be fired again.
@export var cooldown: float = 600.0
## Unlock conditions.
@export var conditions: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []
