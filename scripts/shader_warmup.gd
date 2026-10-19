class_name ShaderWarmup
extends CanvasLayer

## Shader warm-up (the standard fix for first-use hitches): the first time an
## effect is drawn, Godot compiles its shaders -- the user's 72 ms freeze on
## the first blood hit, and the freeze on the heart's first blood orb. So at
## the start of a level, behind a short black cover (like a load fade), each
## effect is shown once in front of the camera for a few frames, then
## everything it made is removed. The HUD makes one.
## Everything made mid-game is here (the user's, 2026-10-19: "all other
## materials"): every effect, every material made in code, the screen
## overlays, and every scene that can turn up after the level's loaded --
## creatures, weapons, pickups, props, and the models their scripts hold --
## shown as lifeless copies (_show_scene: scripts, groups, sounds and
## networking taken off, so nothing of them runs).
## Your own screen only (Rule 1: presentation).

## Frames the effects are on screen for (the compiles happen on the first).
const FRAMES := 4
## Scenes that can turn up mid-game: these folders (and theirs), the
## pickups, and the weapons' and items' models (their data in DATA_FOLDERS).
const SCENE_FOLDERS := ["res://scenes/enemy", "res://scenes/npc", "res://scenes/props"]
const DATA_FOLDERS := ["res://weapons", "res://weapons/hand"]
## The most scenes it shows (models found inside scenes included).
const MAX_SCENES := 200

var _made: Array[Node] = []
var _at := Vector3.ZERO
var _side := Vector3.RIGHT


func _ready() -> void:
	layer = 127
	var cover := ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var camera := get_viewport().get_camera_3d()
	var world := get_tree().current_scene
	if camera == null or world == null:
		queue_free()
		return
	get_tree().node_added.connect(_on_added)
	# In the air ahead (nothing to splash onto, so nothing's left on the ground).
	_at = camera.global_transform * Vector3(0.0, 0.5, -4.0)
	_side = camera.global_basis.x
	var facing := camera.global_basis.z
	var forward := -facing
	_effects(world, facing, forward)
	_materials(world)
	_overlays()
	_scenes(world)
	for i in FRAMES:
		await get_tree().process_frame
	get_tree().node_added.disconnect(_on_added)
	for node in _made:
		if is_instance_valid(node) and node.is_inside_tree():
			node.queue_free()
	queue_free()


## Every effect, the way the game sets it off -- the look only (no sound, no
## harm: the harmful ones are the "not the host's" copies, or held still).
func _effects(world: Node, facing: Vector3, forward: Vector3) -> void:
	var at := _at
	BloodFX.spawn_impact(world, at, facing)
	BloodFX.spawn_splatter(world, at, facing)
	BloodFX.spawn_bullet_hole(world, at, facing)
	BloodFX.spawn_mutation_explosion(world, at)
	var artery := _keep(Node3D.new(), world, at)
	BloodFX.spawn_artery_spurt(artery, 0.5)
	BloodFX.spawn_artery_stream(artery, 0.5)
	BulletFX.spawn(world, at - _side * 3.0, at + _side * 3.0)
	BulletFX.spawn(world, at + _side * 3.0, at - _side * 3.0, true)
	BurningBarrel.place(world, at + Vector3.DOWN * 1.5)
	Explosion.play_visuals(world, at, 2.0)
	HeartQuake.dust(world, at, 3.0)
	HeartQuake.rubble(world, at, 0.6)
	HeartQuake.sheet(world, at, 10.0, 0.0)
	_still(FallingChunk.drop(world, at, Vector3.ZERO, 1.5, false))
	_still(BloodBeam.fire(world, at - forward * 1.0, forward, 0.0, false, [], 0))
	_still(AcidSpit.launch(world, at, Vector3.ZERO, 0.0, 0.0, Color(0.5, 0.8, 0.2), []))
	_made.append(SeededGrowth.burst(world, at + Vector3.DOWN * 1.5, Vector3.UP, false, null))
	_made.append(Rocket.warm_up(world, at))
	_made.append(WormFX.warm_up(world, at + Vector3.DOWN * 1.5))
	_made.append_array(HeartOrb.warm_up(world, at)) # (left running: the streak draws as it goes)
	BloodFX.spawn_burst(world, at, HeartOrb.POP_BURST)
	var smoke := _keep(Viewmodel.backblast_smoke(facing), world, at)
	(smoke as GPUParticles3D).emitting = true
	var flash := MuzzleFlash.new()
	_still(_keep(flash, world, at))
	var flies := _keep(CarryItem.make_flies(), world, at)
	(flies as GPUParticles3D).emitting = true
	for model in [CarryItem.meat_model(false, false), CarryItem.meat_model(false, true), CarryItem.meat_model(true, false),
			FleshTree.pod_model(Virus.WINGS), HeartOrb.look_model()]:
		if model:
			_keep(model, world, at + _side * randf_range(-1.0, 1.0))
	# The white hit flash, over the first of them.
	var meat := CarryItem.meat_model(false, false)
	if meat:
		_keep(meat, world, at)
		HitFlash.flash(meat)


## The materials made in code that no effect above draws: each on a card.
func _materials(world: Node) -> void:
	for material: Material in [InsectWings._material(), Stalker._glow_material(Color.WHITE, false),
			Stalker._glow_material(Color.WHITE, true), BackpackView.forest_material(), BackpackView.pack_material(),
			_shader_material(GrappleIndicator.SHADER, 10)]:
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		card.mesh = quad
		card.material_override = material
		_keep(card, world, _at + _side * randf_range(-1.0, 1.0))
	# The outline you see on things you can pick up (laid over a box).
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.material_overlay = _shader_material(InteractHighlight.OUTLINE_SHADER, 0)
	_keep(box, world, _at)


## The screen overlays (hunger's dimming, the trip's flash), drawn under the
## black cover.
func _overlays() -> void:
	for code: String in [HungerCues.VIGNETTE, TripFlash.SHADER_CODE]:
		var shader := Shader.new()
		shader.code = code
		var material := ShaderMaterial.new()
		material.shader = shader
		var rect := ColorRect.new()
		rect.material = material
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		move_child(rect, 0) # (under the cover)


## Every scene that can turn up mid-game, and every model held in them.
func _scenes(world: Node) -> void:
	var queue: Array[PackedScene] = []
	for folder: String in SCENE_FOLDERS:
		_scenes_in_folder(folder, queue)
	for file in ResourceLoader.list_directory("res://scenes"):
		if file.ends_with("_pickup.tscn") or file == "physics_prop.tscn":
			queue.append(load("res://scenes/" + file) as PackedScene)
	for folder: String in DATA_FOLDERS:
		for file in ResourceLoader.list_directory(folder):
			if file.ends_with(".tres"):
				_scenes_held(load(folder + "/" + file), queue)
	queue.append(Stalker.MODEL)
	var seen := {}
	var i := 0
	while i < queue.size() and seen.size() < MAX_SCENES:
		var scene := queue[i]
		i += 1
		if scene == null or seen.has(scene):
			continue
		seen[scene] = true
		_show_scene(scene, world, queue)


func _scenes_in_folder(folder: String, queue: Array[PackedScene]) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_scenes_in_folder(folder + "/" + entry.trim_suffix("/"), queue)
		elif entry.ends_with(".tscn"):
			queue.append(load(folder + "/" + entry) as PackedScene)


## The scenes a resource (a weapon's data, an item's) holds.
func _scenes_held(resource: Resource, queue: Array[PackedScene]) -> void:
	if resource == null:
		return
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			var value: Variant = resource.get(property.name)
			if value is PackedScene:
				queue.append(value)


## A lifeless copy of `scene` ahead: its look only. Before it goes in, every
## node's script (the models its script held go on the queue), groups,
## signal connections, sounds, cameras and networking are taken off, and
## nothing of it processes.
func _show_scene(scene: PackedScene, world: Node, queue: Array[PackedScene]) -> void:
	var node := scene.instantiate()
	if node == null:
		return
	_strip(node, queue)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_keep(node, world, _at)


func _strip(node: Node, queue: Array[PackedScene]) -> void:
	var script := node.get_script() as Script
	if script:
		for value: Variant in script.get_script_constant_map().values():
			if value is PackedScene:
				queue.append(value)
		for property in node.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var value: Variant = node.get(property.name)
				if value is PackedScene:
					queue.append(value)
		node.set_script(null)
	for group in node.get_groups():
		node.remove_from_group(group)
	# (Only the scene file's own connections -- to scripts that are gone now.)
	for signal_info in node.get_signal_list():
		for connection in node.get_signal_connection_list(signal_info.name):
			if connection.flags & CONNECT_PERSIST:
				node.disconnect(signal_info.name, connection.callable)
	node.process_mode = Node.PROCESS_MODE_INHERIT
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).autoplay = false
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).autoplay = false
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).autoplay = false
	for child in node.get_children():
		if child is Camera3D or child is MultiplayerSynchronizer or child is MultiplayerSpawner:
			node.remove_child(child)
			child.free()
			continue
		_strip(child, queue)


## `node` in the world at `at`, shown (every part of it, hidden ones too),
## and removed when the warm-up's done.
func _keep(node: Node, world: Node, at: Vector3) -> Node:
	world.add_child(node)
	if node is Node3D:
		(node as Node3D).global_position = at
	_show_all(node)
	_made.append(node)
	return node


## Holds a moving thing still where it is (still drawn), and shows all of it.
func _still(node: Node) -> void:
	if node == null:
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_show_all(node)
	if not _made.has(node):
		_made.append(node)


func _show_all(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = true
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true
	for child in node.get_children():
		_show_all(child)


func _shader_material(shader: Shader, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	return material


## Only the effects it set off (never a creature or anything else that
## happened to spawn meanwhile): particles, decals, barrels, and the bare
## (scriptless) holders, lights and meshes effects put in the level.
func _on_added(node: Node) -> void:
	if node.get_parent() != get_tree().current_scene or _made.has(node):
		return
	if node is GPUParticles3D or node is Decal or node is BurningBarrel \
			or (node.get_script() == null and (node is OmniLight3D or node is MeshInstance3D or node.get_class() == "Node3D")):
		_made.append(node)
