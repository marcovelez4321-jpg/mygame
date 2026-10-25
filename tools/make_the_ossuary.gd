extends SceneTree

## Builds the Crawling Ossuary's building (tools/ossuary_bake.gd): its
## TrenchBroom map (maps/megastructures/the_ossuary.map) and its scene
## (scenes/megastructures/the_ossuary.tscn).
##   godot --headless --path <project> --script res://tools/make_the_ossuary.gd
## Re-running overwrites the map and the scene, so once the map's been edited
## in TrenchBroom, rebuild with the scene's "Map" node (Build) instead.
## The game's autoloads don't load in --script mode: stood in for first.


func _initialize() -> void:
	create_timer(600.0).timeout.connect(quit) # never hang on a script error
	for name in ["GameSettings", "SewerLook", "PauseMenu", "FrameCounter", "Network", "PS1Dither"]:
		if not Engine.has_singleton(name):
			Engine.register_singleton(name, Node.new())
	(load("res://tools/ossuary_bake.gd") as GDScript).new().call(&"run", self)
	quit()
