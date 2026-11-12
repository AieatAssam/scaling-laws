class_name LayerDef
extends ContentDef
## Reset layer 1..4. Gain = floor(sqrt(cash earned since the previous reset / threshold)).

@export var index: int = 1
## Currency this reset grants.
@export var currency: String = ""
@export var threshold: float = 1000.0
## Rough first-pass length of the period this reset closes, in hours (for UI copy and pacing).
@export var target_hours: float = 0.5
