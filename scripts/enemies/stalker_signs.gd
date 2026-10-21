class_name StalkerSigns
extends RefCounted

## What the Stalker (the wendigo) leaves and does to the world that every
## game shows for itself (Rule 1: presentation; the host sends them with
## Network.send_stalker_sign): the wrong silence before a stunt, and the
## signs of it -- see play().
## Its own sounds go on their own bus (BUS), so the silence never mutes it.

## The Stalker's own sounds (its voices, skitter, breathing): never silenced.
const BUS := &"Stalker"
## The wrong silence (the user's: world only, over 4 s): the world's sounds
## -- ambience, wind, creatures -- fade out; your own steps and gun, and the
## music, stay. Held till the stunt's done, then back over SILENCE_BACK.
const SILENCED_BUSES := [&"Ambience", &"Enemies"]
const SILENCE_FADE := 4.0
const SILENCE_BACK := 3.0
const SILENCE_DB := -60.0
## Never held longer than this (s), whatever happens to the stunt.
const SILENCE_LONGEST := 90.0

static var _held := {} # bus -> its volume before the silence
static var _silence_tween: Tween
static var _silence_serial := 0


## The bus its sounds play on (made the first time: sends where Enemies does).
static func bus() -> StringName:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master")
	return BUS


## A sign shown here (Network.send_stalker_sign, on every game it's for).
static func play(tree: SceneTree, kind: StringName, at: Vector3, dir: Vector3) -> void:
	match kind:
		&"silence_on":
			silence(tree, true)
		&"silence_off":
			silence(tree, false)
		&"help_signs":
			help_signs(tree, at, dir)


## The world's sounds fading out (`on`) or back.
static func silence(tree: SceneTree, on: bool) -> void:
	if _silence_tween and _silence_tween.is_valid():
		_silence_tween.kill()
	_silence_serial += 1
	var serial := _silence_serial
	var levels := {}
	for name: StringName in SILENCED_BUSES:
		var index := AudioServer.get_bus_index(name)
		if index == -1:
			continue
		if on and not _held.has(name):
			_held[name] = AudioServer.get_bus_volume_db(index)
		if _held.has(name):
			levels[index] = [AudioServer.get_bus_volume_db(index), SILENCE_DB if on else float(_held[name])]
	if levels.is_empty():
		return
	_silence_tween = tree.create_tween()
	_silence_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_silence_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_silence_tween.tween_method(func(t: float) -> void:
		for index: int in levels:
			# Eased in linear volume (a dB ramp sounds like it drops off a cliff).
			var from := db_to_linear(levels[index][0])
			var to := db_to_linear(levels[index][1])
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(lerpf(from, to, t), 0.00001))),
			0.0, 1.0, SILENCE_FADE if on else SILENCE_BACK)
	if not on:
		_silence_tween.tween_callback(func() -> void: _held.clear())
	else:
		# A failsafe: never held for ever.
		tree.create_timer(SILENCE_LONGEST).timeout.connect(func() -> void:
			if serial == _silence_serial:
				silence(tree, false))


## Signs stay this long (s), then go.
const SIGNS_LAST := 300.0
const CLOTH_COLOR := Color(0.2, 0.22, 0.25)
static var _scratch_texture: ImageTexture


## Where the help scream came from (the user's): nobody -- torn clothes, a
## blood trail leading off `away` into the dark, and its long scratches
## gouged in the ground.
static func help_signs(tree: SceneTree, at: Vector3, away: Vector3) -> void:
	var world := tree.current_scene
	if world == null:
		return
	var flat := Vector3(away.x, 0.0, away.z).normalized() if Vector2(away.x, away.z).length() > 0.01 else Vector3.FORWARD
	var space := (world as Node3D).get_world_3d().direct_space_state if world is Node3D else null
	var ground := func(point: Vector3) -> Dictionary:
		if space == null:
			return {}
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 6.0, 1))
	# The blood trail, off into the dark, thinning.
	for i in 11:
		var hit: Dictionary = ground.call(at + flat * (1.5 + i * 1.3) + flat.cross(Vector3.UP) * randf_range(-0.4, 0.4))
		if not hit.is_empty():
			BloodFX.spawn_splatter(world, hit.position, hit.normal, lerpf(0.9, 0.35, i / 10.0))
	# Its scratches, raked across the ground where it was.
	var hit_here: Dictionary = ground.call(at)
	if not hit_here.is_empty():
		var scratches := Decal.new()
		scratches.texture_albedo = _scratches()
		scratches.size = Vector3(1.2, 1.0, 3.2)
		scratches.modulate = Color(0.12, 0.1, 0.1)
		world.add_child(scratches)
		scratches.global_position = (hit_here.position as Vector3) + Vector3.UP * 0.2
		scratches.global_basis = Basis(Vector3.UP, atan2(flat.x, flat.z) + randf_range(-0.4, 0.4))
		tree.create_timer(SIGNS_LAST).timeout.connect(scratches.queue_free)
	# Torn clothes lying there, one bloodied.
	for i in 3:
		var hit: Dictionary = ground.call(at + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)))
		if hit.is_empty():
			continue
		var cloth := MeshInstance3D.new()
		var piece := BoxMesh.new()
		piece.size = Vector3(randf_range(0.3, 0.6), 0.015, randf_range(0.2, 0.45))
		cloth.mesh = piece
		var look := StandardMaterial3D.new()
		look.albedo_color = CLOTH_COLOR.lerp(BloodFX.BLOOD_COLOR, 0.55 if i == 0 else 0.1)
		look.roughness = 1.0
		cloth.material_override = look
		world.add_child(cloth)
		cloth.global_position = (hit.position as Vector3) + Vector3.UP * 0.01
		cloth.global_basis = Basis(Vector3.UP, randf() * TAU)
		tree.create_timer(SIGNS_LAST).timeout.connect(cloth.queue_free)


## Four long gouges side by side, ragged, dark at the middle (a decal's).
static func _scratches() -> ImageTexture:
	if _scratch_texture:
		return _scratch_texture
	var image := Image.create(48, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var dice := RandomNumberGenerator.new()
	dice.seed = 404
	for claw in 4:
		var x := 8.0 + claw * 10.0
		for y in range(6, 122):
			x += dice.randf_range(-0.6, 0.6)
			var width := 1.0 + 1.5 * sin(PI * (y - 6) / 116.0)
			for dx in range(int(-width - 1), int(width + 2)):
				var px := int(x) + dx
				if px < 0 or px >= 48:
					continue
				var a := clampf(1.0 - absf(px - x) / (width + 0.5), 0.0, 1.0)
				image.set_pixel(px, y, Color(1, 1, 1, maxf(image.get_pixel(px, y).a, a)))
	_scratch_texture = ImageTexture.create_from_image(image)
	return _scratch_texture
