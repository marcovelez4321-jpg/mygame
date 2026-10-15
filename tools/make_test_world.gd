extends SceneTree

## Bakes the M0 test world (docs/WORLD.md): a Terrain3D ground from
## AlienTerrain (4 x 4 km by default), saved as Terrain3D region data, its
## navmesh tiles, test chunks, plus a scene with the player standing in the
## middle (Grandma's yard) to walk around in.
##   godot --headless --path <project> --script res://tools/make_test_world.gd
##   ... --script res://tools/make_test_world.gd -- size=2048   (8 x 8 km)
## size = heightmap pixels across, 4 m each (256 = 1 km, 1024 = 4 km); a
## power of two, 256 or more. Re-run it after changing AlienTerrain's
## settings; it overwrites the terrain data, tiles, chunks and the scene.
## The game's autoloads don't load in --script mode and the world's scripts
## reach them, so they're stood in for first and the bake itself
## (tools/test_world_bake.gd) is loaded only after -- nothing here names a
## game class, so this file always compiles.

var _bake: RefCounted


func _initialize() -> void:
	# A script error stops the bake before it quits; never hang on one.
	create_timer(3600.0).timeout.connect(quit)
	for name in ["GameSettings", "SewerLook", "PauseMenu", "FrameCounter", "Network", "PS1Dither"]:
		if not Engine.has_singleton(name):
			Engine.register_singleton(name, Node.new())
	_bake = (load("res://tools/test_world_bake.gd") as GDScript).new()
	_bake.call(&"run", self)