extends RefCounted

## The Stack's bake (StackBuilder), run by tools/make_the_stack.gd once it has
## stood in for the autoloads: --script mode doesn't load them, and the
## Stack's scripts reach them (its fires: BurningBarrel). See that file.

const SCENE := "res://scenes/megastructures/the_stack.scn"
const MAP := "res://maps/megastructures/the_stack.map"
const MAP_SETTINGS := "res://maps/megastructures/megastructure_map_settings.tres"
const TEXTURE_DIR := "res://trenchbroom/textures/Megastructure"
const ART_DIR := "res://art/megastructures"
const WIND := "res://audio/sfx/ambience/stack_wind.res"
const DRONE := "res://audio/sfx/ambience/stack_drone.res"


static func run(tree: SceneTree) -> void:
	for path in [SCENE, MAP, TEXTURE_DIR + "/x", ART_DIR + "/x", WIND]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# What it's made of: the textures (PNGs for TrenchBroom, textures for the game).
	var textures := {}
	for kind in [["windows", "stack_concrete", true, false], ["plain", "stack_plain", false, false], ["stained", "stack_stained", true, true]]:
		var image := StackBuilder.make_concrete(kind[2], kind[3])
		image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [TEXTURE_DIR, kind[1]]))
		var path := "%s/%s.res" % [ART_DIR, kind[1]]
		ResourceSaver.save(ImageTexture.create_from_image(image), path)
		textures[kind[0]] = load(path)
	ResourceSaver.save(StackBuilder.make_wind(), WIND)
	ResourceSaver.save(StackBuilder.make_drone(), DRONE)
	# The Stack.
	var builder := StackBuilder.new()
	var stack := builder.build_scene(textures, load(WIND) as AudioStream, load(DRONE) as AudioStream)
	var scene := PackedScene.new()
	var error := scene.pack(stack)
	if error == OK:
		error = ResourceSaver.save(scene, SCENE, ResourceSaver.FLAG_COMPRESS)
	var counts := {}
	for b in builder.boxes:
		counts[b.part] = int(counts.get(b.part, 0)) + 1
	print("the Stack: ", counts, " boxes, ", builder.halls.size(), " halls, ", builder.window_rooms.size(), " window rooms, ",
			builder.entrance_spots.size(), " entrance eyes, ", builder.lamps.size(), " lamps, ", builder.openings.size(),
			" openings -> ", SCENE, " (error ", error, ")")
	stack.free()
	# The same boxes for TrenchBroom, and the map settings megastructure maps use
	# (8 units a metre, so kilometres stay workable).
	var names := {&"concrete": "Megastructure/stack_concrete", &"plain": "Megastructure/stack_plain", &"stained": "Megastructure/stack_stained",
			&"rubble": "Megastructure/stack_plain", &"clay": "Megastructure/stack_plain",
			&"metal": "Megastructure/stack_plain", &"sludge": "Megastructure/stack_plain"}
	print("skybridges: ", builder.bridge_report)
	print("hive: ", builder.hive_holes.size(), " holes; panic stairs: ", builder.panic_report)
	print("cobwebs: ", builder.web_quads.size(), " (", builder.web_quads.filter(func(w: Dictionary) -> bool: return w.indoors).size(), " inside)")
	print("map: ", MAP, " (error ", builder.write_map(ProjectSettings.globalize_path(MAP), names), ")")
	var settings := (load("res://addons/func_godot/func_godot_default_map_settings.tres") as Resource).duplicate()
	settings.set("inverse_scale_factor", StackBuilder.MAP_UNITS)
	print("map settings: ", MAP_SETTINGS, " (error ", ResourceSaver.save(settings, MAP_SETTINGS), ")")
	pass