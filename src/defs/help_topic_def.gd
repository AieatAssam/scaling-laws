class_name HelpTopicDef
extends ContentDef
## Help article. Shows as "???" plus `hint` until `conditions` hold, then `body` (markup, see HelpText).

## Position in the topic list (ties sort by id).
@export var order: int = 0
## Same schema as the other defs. Empty means always shown.
@export var conditions: Array[Dictionary] = []
## One line shown while the topic is locked.
@export_multiline var hint: String = ""
## Article markup: plain lines, "## Heading", "- item", "[training]", "[layers]", {TOKEN}, [icon:name].
@export_multiline var body: String = ""
