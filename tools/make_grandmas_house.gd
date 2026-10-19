extends SceneTree

## Builds Grandma's house (tools/house_bake.gd): its TrenchBroom map
## (maps/grandmas_house.map), map settings, window texture, and its scene
## (scenes/world/grandmas_house.tscn).
##   godot --headless --path <project> --script res://tools/make_grandmas_house.gd
## The first run makes the window texture and stops: let the editor import it
## (open the project, or --headless --editor --quit), then run it again.
## Re-running overwrites the map and the scene, so once the map's been edited
## in TrenchBroom, rebuild with the scene's "Map" node (Build) instead.
## The game's autoloads don't load in --script mode, so they're stood in for
## first and the bake is loaded only after -- nothing here names a game
## class, so this file always compiles.


func _initialize() -> void:
	create_timer(300.0).timeout.connect(quit) # never hang on a script error
	for name in ["GameSettings", "SewerLook", "PauseMenu", "FrameCounter", "Network", "PS1Dither"]:
		if not Engine.has_singleton(name):
			Engine.register_singleton(name, Node.new())
	(load("res://tools/house_bake.gd") as GDScript).new().call(&"run", self)
	quit()
