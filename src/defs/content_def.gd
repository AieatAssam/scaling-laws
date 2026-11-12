class_name ContentDef
extends Resource
## Base for every content resource. Subclasses add typed fields; see the other files in src/defs/.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: String = ""
