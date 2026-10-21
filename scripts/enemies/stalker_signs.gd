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
		&"window":
			window_shadow(tree, at, dir)
		&"window_off":
			window_shadow_off()
		&"camp_visit":
			camp_visit(tree, at, dir)


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


## The window (the user's: its shadow on the glass): the pane goes pale, lit
## from outside, and its antlered shadow stands against it -- dead still,
## its long arms hanging. It fades if you walk at it (WINDOW_NEAR), or when
## the stunt's done.
const WINDOW_NEAR := 4.0
const WINDOW_FADE_IN := 1.5
static var _window: MeshInstance3D
static var _window_texture: ImageTexture


static func window_shadow(tree: SceneTree, at: Vector3, out: Vector3) -> void:
	window_shadow_off()
	var world := tree.current_scene
	if world == null:
		return
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 2.7) # (inside the frames of all three)
	card.mesh = quad
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_texture = _silhouette()
	look.albedo_color = Color(1, 1, 1, 0)
	look.disable_fog = true
	card.material_override = look
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(card)
	# Just inside the pane, facing in.
	card.global_position = at - out * 0.06
	card.global_basis = Basis.looking_at(out, Vector3.UP) # (a quad faces +Z: looking at out turns it inward)
	_window = card
	var tween := card.create_tween()
	tween.tween_property(look, "albedo_color:a", 1.0, WINDOW_FADE_IN)
	# Walked at: gone (checked every few frames, on this game's own player).
	var check := func() -> void:
		if not is_instance_valid(card):
			return
		var camera := card.get_viewport().get_camera_3d()
		if camera == null:
			return
		var gap := camera.global_position.distance_to(at)
		if not card.has_meta(&"start_gap"): # (kept on the card: a lambda's locals are copies)
			card.set_meta(&"start_gap", gap)
		if gap < WINDOW_NEAR or gap < float(card.get_meta(&"start_gap")) - 2.0:
			window_shadow_off()
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.autostart = true
	timer.timeout.connect(check)
	card.add_child(timer)


static func window_shadow_off() -> void:
	if _window == null or not is_instance_valid(_window):
		_window = null
		return
	var card := _window
	_window = null
	var look := card.material_override as StandardMaterial3D
	var tween := card.create_tween()
	tween.tween_property(look, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(card.queue_free)


## A pane lit pale and cold from outside, the shadow of something standing
## against it: too tall, thin, its arms hanging past its hips, small antlers.
static func _silhouette() -> ImageTexture:
	if _window_texture:
		return _window_texture
	var w := 64
	var h := 96
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var glow := Color(0.72, 0.78, 0.84)
	for y in h:
		for x in w:
			var u := (x - w * 0.5) / (w * 0.5)
			var v := (y - h * 0.45) / (h * 0.6)
			var a := clampf(1.0 - (u * u * 0.6 + v * v * 0.5), 0.0, 1.0) * 0.85
			image.set_pixel(x, y, Color(glow, a))
	var dark := Color(0.04, 0.04, 0.05, 1.0)
	var fill := func(x0: int, y0: int, x1: int, y1: int) -> void:
		for y in range(maxi(y0, 0), mini(y1, h)):
			for x in range(maxi(x0, 0), mini(x1, w)):
				image.set_pixel(x, y, dark)
	var mid := w / 2
	fill.call(mid - 5, 30, mid + 5, 62) # the body, thin
	fill.call(mid - 5, 62, mid - 2, 96) # legs
	fill.call(mid + 2, 62, mid + 5, 96)
	fill.call(mid - 9, 32, mid - 6, 74) # long arms, hanging past its hips
	fill.call(mid + 6, 32, mid + 9, 74)
	fill.call(mid - 11, 72, mid - 7, 79) # its hands
	fill.call(mid + 7, 72, mid + 11, 79)
	for y in range(18, 31): # the head, tipped over
		for x in range(mid - 4, mid + 5):
			var dx := (x - mid - (30 - y) * 0.25) / 4.0
			var dy := (y - 24.0) / 6.5
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(x, y, dark)
	fill.call(mid - 5, 12, mid - 3, 20) # antlers: one stub, one with a tine
	fill.call(mid + 3, 9, mid + 5, 19)
	fill.call(mid + 5, 12, mid + 8, 14)
	_window_texture = ImageTexture.create_from_image(image)
	return _window_texture


## Its camp visit (the user's: tracks, fire out, the totem): round the
## bedroll at `at` (its length along `along`).
const TRACKS := 14
const TRACK_RING := 2.4
const TRACKS_LAST := 600.0
static var _hand_texture: ImageTexture
static var _foot_texture: ImageTexture


static func camp_visit(tree: SceneTree, at: Vector3, along: Vector3) -> void:
	var world := tree.current_scene as Node3D
	if world == null:
		return
	var camp: Camp = null
	for node in tree.get_nodes_in_group(Camp.GROUP):
		var each := node as Camp
		if each and each.global_position.distance_to(at) < 8.0 and (camp == null or each.global_position.distance_to(at) < camp.global_position.distance_to(at)):
			camp = each
	if camp:
		camp.put_out()
	var holder: Node3D = camp if camp else world
	var space := world.get_world_3d().direct_space_state
	# Its tracks: round and round the bed, hands and feet, long-fingered.
	var turn := randf() * TAU
	for i in TRACKS:
		var a := turn + TAU * i / TRACKS + randf_range(-0.12, 0.12)
		var spot := at + Vector3(cos(a), 0.0, sin(a)) * (TRACK_RING + randf_range(-0.3, 0.3))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 3.0, 1))
		if hit.is_empty():
			continue
		var mark := Decal.new()
		var hand := i % 2 == 0
		mark.texture_albedo = _print(hand)
		mark.size = Vector3(0.45, 1.0, 0.95) if hand else Vector3(0.35, 1.0, 0.85)
		mark.modulate = Color(0.08, 0.07, 0.07, 0.9)
		holder.add_child(mark)
		mark.global_position = (hit.position as Vector3) + Vector3.UP * 0.2
		# Pointed round the ring (it went round you).
		var going := Vector3(-sin(a), 0.0, cos(a))
		mark.global_basis = Basis(Vector3.UP, atan2(going.x, going.z))
		tree.create_timer(TRACKS_LAST).timeout.connect(func() -> void:
			if is_instance_valid(mark):
				mark.queue_free())
	# The totem, stuck in the ground by your head.
	var head := at + along.normalized() * (Camp.BED_LENGTH * 0.5 + 0.5)
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(head + Vector3.UP * 2.0, head + Vector3.DOWN * 3.0, 1))
	var totem := _totem()
	holder.add_child(totem)
	totem.global_position = (ground.position as Vector3) if not ground.is_empty() else head
	totem.global_basis = Basis(Vector3.UP, randf() * TAU)


## A little totem: three sticks lashed in a tripod, a small antler crowning it,
## a bone hung off it.
static func _totem() -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.24, 0.18, 0.13)
	var bone := Color(0.8, 0.76, 0.66)
	for i in 3:
		var a := TAU * i / 3.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * 0.28
		_stick(tool, foot + Vector3.DOWN * 0.15, Vector3.UP * 1.15 - foot * 0.15, 0.025, wood)
	# The antler on top: a beam and two tines.
	var crown := Vector3.UP * 1.12
	_stick(tool, crown, crown + Vector3(0.18, 0.28, 0.0), 0.02, bone)
	_stick(tool, crown + Vector3(0.09, 0.14, 0.0), crown + Vector3(0.05, 0.3, 0.08), 0.012, bone)
	_stick(tool, crown, crown + Vector3(-0.14, 0.22, 0.04), 0.018, bone)
	# A bone hung off it.
	_stick(tool, Vector3(0.0, 0.75, 0.12), Vector3(0.02, 0.45, 0.14), 0.02, bone)
	tool.generate_normals()
	var totem := MeshInstance3D.new()
	totem.mesh = tool.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.95
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	totem.material_override = look
	return totem


static func _stick(tool: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var along := (to - from).normalized()
	var side := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(along)
	var sides := 5
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var o0 := (side * cos(a0) + up * sin(a0)) * radius
		var o1 := (side * cos(a1) + up * sin(a1)) * radius
		for corner: Vector3 in [from + o0, to + o0 * 0.6, to + o1 * 0.6, from + o0, to + o1 * 0.6, from + o1]:
			tool.set_color(color)
			tool.add_vertex(corner)


## A print: a long hand (a palm and five long thin fingers) or a long narrow
## foot with toes -- white where it's pressed in, for a decal.
static func _print(hand: bool) -> ImageTexture:
	if hand and _hand_texture:
		return _hand_texture
	if not hand and _foot_texture:
		return _foot_texture
	var w := 40
	var h := 84
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var blot := func(cx: float, cy: float, rx: float, ry: float) -> void:
		for y in range(int(cy - ry - 1), int(cy + ry + 2)):
			for x in range(int(cx - rx - 1), int(cx + rx + 2)):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var d := pow((x - cx) / rx, 2.0) + pow((y - cy) / ry, 2.0)
				if d <= 1.0:
					image.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 2.0, 0.0, 1.0)))
	if hand:
		blot.call(20.0, 62.0, 10.0, 13.0) # the palm
		for f in 4: # four long fingers
			var fx := 11.0 + f * 6.0
			for k in 7:
				blot.call(fx + (f - 1.5) * k * 0.4, 46.0 - k * 6.0, 2.0, 3.6)
		for k in 4: # the thumb, off to the side
			blot.call(32.0 + k * 1.5, 58.0 - k * 4.0, 2.0, 3.0)
	else:
		blot.call(20.0, 52.0, 8.0, 26.0) # a long narrow foot
		for t in 4:
			blot.call(12.0 + t * 5.5, 20.0 - absf(t - 1.5) * 2.0, 2.2, 4.0)
	var texture := ImageTexture.create_from_image(image)
	if hand:
		_hand_texture = texture
	else:
		_foot_texture = texture
	return texture
