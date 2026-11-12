class_name BenchmarkDef
extends ContentDef
## Achievement. Unlocks once when all `conditions` hold; `effects` apply once and persist across resets.

## One of: bronze, silver, gold, platinum, diamond, cosmic.
@export var badge: String = "bronze"
@export var conditions: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []
