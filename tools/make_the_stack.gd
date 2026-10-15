extends SceneTree

## Builds the Stack (StackBuilder): its scene, its TrenchBroom map, and the
## things it's made with (its concrete -- windowed outside, plain inside and
## for the rubble, stained for the hive -- the wind and the drone).
##   godot --headless --path <project> --script res://tools/make_the_stack.gd
## Re-running overwrites the scene and the map (so once the map's been
## edited by hand in TrenchBroom, build that with func_godot instead).
## The game's autoloads don't load in --script mode, and the Stack's scripts
## reach them, so they're stood in for first and the bake itself
## (tools/stack_bake.gd) is loaded only after -- nothing here names a game
## class, so this file always compiles.


func _initialize() -> void:
	create_timer(600.0).timeout.connect(quit) # never hang on a script error
	for name in ["GameSettings", "SewerLook", "PauseMenu", "FrameCounter", "Network", "PS1Dither"]:
		if not Engine.has_singleton(name):
			Engine.register_singleton(name, Node.new())
	(load("res://tools/stack_bake.gd") as GDScript).call(&"run", self)
	quit()