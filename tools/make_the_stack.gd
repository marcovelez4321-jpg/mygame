extends SceneTree

## Builds the Stack (StackBuilder): its scene, its TrenchBroom map, and the
## things it's made with (the concrete texture, the wind and the drone).
##   godot --headless --path <project> --script res://tools/make_the_stack.gd
## Re-running overwrites the scene and the map (so once the map's been
## edited by hand in TrenchBroom, build that with func_godot instead).

const SCENE := "res://scenes/megastructures/the_stack.scn"
const MAP := "res://maps/megastructures/the_stack.map"
const MAP_SETTINGS := "res://maps/megastructures/megastructure_map_settings.tres"
const TEXTURE_PNG := "res://trenchbroom/textures/Megastructure/stack_concrete.png"
const TEXTURE := "res://art/megastructures/stack_concrete.res"
const WIND := "res://audio/sfx/ambience/stack_wind.res"
const DRONE := "res://audio/sfx/ambience/stack_drone.res"


func _initialize() -> void:
	create_timer(600.0).timeout.connect(quit) # never hang on a script error
	for path in [SCENE, MAP, TEXTURE_PNG, TEXTURE, WIND]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# What it's made of.
	var concrete := StackBuilder.make_concrete()
	concrete.save_png(ProjectSettings.globalize_path(TEXTURE_PNG)) # for TrenchBroom
	ResourceSaver.save(ImageTexture.create_from_image(concrete), TEXTURE)
	ResourceSaver.save(StackBuilder.make_wind(), WIND)
	ResourceSaver.save(StackBuilder.make_drone(), DRONE)
	# The Stack.
	var builder := StackBuilder.new()
	var stack := builder.build_scene(load(TEXTURE) as Texture2D, load(WIND) as AudioStream, load(DRONE) as AudioStream)
	var scene := PackedScene.new()
	var error := scene.pack(stack)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE, ResourceSaver.FLAG_COMPRESS)
	var shell := 0
	var inside := 0
	for b in builder.boxes:
		if b.part == &"shell":
			shell += 1
		else:
			inside += 1
	print("the Stack: ", shell, " shell boxes, ", inside, " interior boxes, ", builder.openings.size(), " openings -> ", SCENE, " (error ", error, ")")
	stack.free()
	# The same boxes for TrenchBroom, and the map settings megastructure maps use
	# (8 units a metre, so kilometres stay workable).
	print("map: ", MAP, " (error ", builder.write_map(ProjectSettings.globalize_path(MAP), "Megastructure/stack_concrete"), ")")
	var settings := (load("res://addons/func_godot/func_godot_default_map_settings.tres") as Resource).duplicate()
	settings.set("inverse_scale_factor", StackBuilder.MAP_UNITS)
	print("map settings: ", MAP_SETTINGS, " (error ", ResourceSaver.save(settings, MAP_SETTINGS), ")")
	quit()
