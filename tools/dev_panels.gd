extends SceneTree
## Entry point for the panel harness (dev only, not shipped). Run it with:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/dev_panels.gd
## The real harness is tools/dev_panels_run.gd. It is loaded here, at runtime, because under -s the
## autoload names (Game, Content, Sim...) are not visible when this script compiles.


func _initialize() -> void:
	var run: Node = load("res://tools/dev_panels_run.gd").new()
	root.add_child(run)
