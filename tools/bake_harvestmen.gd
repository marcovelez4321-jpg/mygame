extends SceneTree

## Bakes the Harvestman model scenes (HarvestmanBuilder) into
## scenes/enemy/harvestman/models/ -- one per kind -- so you can open them in
## the editor and change them by hand. A model that's already there is left
## alone (your changes are safe) unless you pass "force".
##
## Run from the project folder:
##   godot --headless --path . --script res://tools/bake_harvestmen.gd
##   godot --headless --path . --script res://tools/bake_harvestmen.gd -- force

const OUT_DIR := "res://scenes/enemy/harvestman/models/"
## name, core kind, leech legs
const VARIANTS := [
	["barnacle", HarvestmanCore.Kind.BARNACLE, false],
	["deepmaw", HarvestmanCore.Kind.DEEPMAW, false],
	["fused", HarvestmanCore.Kind.FUSED, false],
	["leech", HarvestmanCore.Kind.BARNACLE, true],
]


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var force := OS.get_cmdline_user_args().has("force")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for variant in VARIANTS:
		var path: String = OUT_DIR + "harvestman_%s_model.tscn" % variant[0]
		if ResourceLoader.exists(path) and not force:
			print("BAKE skip (already there, pass force to redo): ", path)
			continue
		var settings := HarvestmanBuilder.Settings.new()
		settings.core = variant[1]
		settings.leech_legs = variant[2]
		settings.seed = hash(variant[0])
		var model := HarvestmanBuilder.build(settings, get_root())
		HarvestmanBuilder.claim(model)
		var packed := PackedScene.new()
		var err := packed.pack(model)
		if err == OK:
			err = ResourceSaver.save(packed, path)
		print("BAKE ", path, ": ", error_string(err))
		model.free()
	quit()
