class_name BackpackView
extends Node3D

## The open backpack in first person (the user's: diegetic, no menus). Tab
## and your left arm swings the pack round off your back and holds it up by
## its top handle in a fist; the top unzips and you see inside -- every kind
## thing you carry as a small 3D prop, really tumbling and sliding about in it as
## you move (and still shifting on your back as you climb), the one under the
## cursor outlined like anything you can use. Click a prop to use it (Backpack.use() through the input
## packet). Tab again and it goes back on your back.
## How it's held -- the bag's place, the hand on it, the fist, the elbow,
## the unzip -- is BackpackHold (scenes/player/backpack_hold.tres), tuned in
## game with F2 then O (Viewmodel) and saved with F3.
## Lives with the first-person arms (same space, so it sways and kicks with
## them). Your own view only: nothing here is simulation.

const HOLD_PATH := "res://scenes/player/backpack_hold.tres"
const BAG_SCENE := "res://art/PSX Forest Props.fbx"
const MEGA := "res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/"
## Clicks only ever hit the item props (their own physics layer).
const ITEM_LAYER := 1 << 19
## The look of each kind: a model (a scene path, or [scene, node name] in a
## pack), or empty for one made in code.
const PROPS := {
	Backpack.Kind.PILLS: MEGA + "Items & Weapons/pills_packet_1.glb",
	Backpack.Kind.BANDAGE: MEGA + "Items & Weapons/bandage_mp_1.glb",
	Backpack.Kind.BULLETS: MEGA + "Items & Weapons/ammo_box_mp_1.glb",
	Backpack.Kind.SHELLS: MEGA + "Items & Weapons/shotgun_ammo_1.glb",
	Backpack.Kind.ROCKETS: MEGA + "Items & Weapons/ammo_box_1.glb",
	Backpack.Kind.SCRAP: MEGA + "Small Props/tin_can_mp_1_rusty.glb",
	Backpack.Kind.CAMP_KIT: [BAG_SCENE, "Foam Sleeping Pad"],
}

var hold: BackpackHold
## 0..1: swung round in front of you; unzipped.
var swing := 0.0
var unzip := 0.0

var _player: PlayerMovement
var _arms: FirstPersonArms
var _bag: MeshInstance3D
var _bag_box := AABB()
var _materials: Array[ShaderMaterial] = []
var _items: Node3D
var _shown_key := ""
var _time := 0.0

static var _scenes := {}


func setup(player: PlayerMovement, arms: FirstPersonArms) -> void:
	_player = player
	_arms = arms
	hold = load(HOLD_PATH) as BackpackHold if ResourceLoader.exists(HOLD_PATH) else BackpackHold.new()
	_build_bag()
	_items = Node3D.new()
	_items.name = "Items"
	_bag.add_child(_items)
	visible = false


## Every frame from the Viewmodel, before the arms: the swing and the unzip,
## the bag where it goes, the left hand on its handle, the items inside.
## True while the bag's out (the left arm's holding it).
func update(delta: float) -> bool:
	if _player == null or _bag == null:
		return false
	var want := _player.bag_open
	swing = move_toward(swing, 1.0 if want else 0.0, delta / maxf(hold.swing_time, 0.01))
	unzip = move_toward(unzip, 1.0 if want and swing >= 1.0 else 0.0, delta / maxf(hold.unzip_time, 0.01))
	var out := swing > 0.0
	if out != visible:
		_have_last = false # a new frame of reference: no jolt from the switch
	visible = out
	if not visible:
		_set_cursor(false)
		_on_your_back(delta)
		return false
	_time += delta
	# From down behind your shoulder up into place, eased.
	var t := smoothstep(0.0, 1.0, swing)
	var from := hold.bag_position + Vector3(-0.35, -0.55, 0.35)
	var turn := Basis.from_euler(hold.bag_rotation_degrees * (PI / 180.0))
	var from_turn := Basis.from_euler((hold.bag_rotation_degrees + Vector3(60.0, 40.0, 30.0)) * (PI / 180.0))
	transform = Transform3D(Basis(from_turn.get_rotation_quaternion().slerp(turn.get_rotation_quaternion(), t)), from.lerp(hold.bag_position, t))
	_bag.scale = Vector3.ONE * hold.bag_scale
	_bag.position = -_bag_box.get_center() * hold.bag_scale # centred on its middle
	# Unzipped: the top cut away down to the opening.
	var clip := _bag_box.end.y - _bag_box.size.y * hold.zipper_open_share * smoothstep(0.0, 1.0, unzip)
	for material in _materials:
		material.set_shader_parameter("clip_height", clip if unzip > 0.0 else _bag_box.end.y + 1.0)
	_hold_with_left_hand()
	_update_items(delta)
	_set_cursor(unzip >= 1.0)
	return true


## The items while it's open: in step with what's in the pack, simulated in
## the bag as it's held, drawn, the one under the cursor outlined.
func _update_items(delta: float) -> void:
	var stacks := _player.backpack.stacks()
	var key := ""
	for stack in stacks:
		key += "%d:%d:%s," % [stack.kind, mini(stack.count, 3), stack.weapon.resource_path if stack.weapon else ""]
	if key != _shown_key:
		_shown_key = key
		_sync_bodies(stacks)
	_items.visible = unzip > 0.6
	_simulate(_bag.global_transform, delta, true)
	_place_props()
	_update_hover()


## Away on your back: the items still shift as you climb, ten times a
## second, from your body's movement (positions only, nothing drawn).
func _on_your_back(delta: float) -> void:
	_on_back_left -= delta
	if _on_back_left > 0.0:
		return
	_on_back_left = ON_BACK_STEP
	_simulate(_player.global_transform, ON_BACK_STEP, false)


## The left hand in a fist round the handle, the arm reaching it by IK.
func _hold_with_left_hand() -> void:
	var handle_local := _bag_box.get_center() + _bag_box.size * hold.handle_point
	var handle := transform * (_bag.transform * handle_local) # this node's parent's space: the arms'
	# Gripping from above: the palm down onto the handle, the fingers along it.
	var grip := transform.basis.orthonormalized() * Basis(Vector3.RIGHT, PI)
	var to_rig := _arms.transform.affine_inverse()
	_arms.set_bag(true)
	_arms.set_support_grip(to_rig * handle, to_rig.basis * grip, hold.fist, hold.hand_rotation_degrees,
			to_rig.basis * hold.elbow_direction, hold.elbow_degrees)


## Puts the arm back to whatever the gun wants (the Viewmodel calls this as
## the bag goes away).
func release_arm() -> void:
	if _arms:
		_arms.set_bag(false)
	_set_cursor(false)


# ---- The items: a small physics world inside the bag -----------------------------
# Every item is a box (its prop's size) inside the bag's inner space (the
# items_area: a false bottom just under the zipper, so what's inside rests
# where you can see it). They fall, slide, pile up and knock each other
# apart -- pushed by gravity (tilted the way the bag's held) and by the bag's
# own movement: swing your view, jump, land, get launched, and they slosh.
# Simulated in the bag's own space, so nothing can fly out through its
# walls. Held out: every frame, leaning as they slide. On your back: ten
# times a second, positions only, from your body's movement -- so climbing
# rearranges them, and you find them moved when you next look.

## Strength of the push from the bag's own movement (1 = fully real).
const INERTIA := 0.6
## How much a turn of the bag swirls what's inside (0..1).
const SWIRL := 0.35
## Bounce off walls and each other; slide damping (per second).
const BOUNCE := 0.15
const DAMPING := 2.5
const ON_BACK_STEP := 0.1

var _bodies: Array[Dictionary] = [] # {kind, half: Vector3, p, v, node, area, tilt}
var _last_frame := Transform3D.IDENTITY
var _last_velocity := Vector3.ZERO
var _have_last := false
var _on_back_left := 0.0
var _hovered := -1
var _outline: ShaderMaterial


## The inner space, in the bag's own units.
func _inside() -> AABB:
	var area := hold.items_area
	return AABB(_bag_box.get_center() + _bag_box.size * area.position, _bag_box.size * area.size)


## Steps the items: held out (`frame` = the bag's world transform) every
## frame; on your back (the body's) ten times a second, positions only.
func _simulate(frame: Transform3D, delta: float, held: bool) -> void:
	if _bodies.is_empty():
		_have_last = false
		return
	var basis := frame.basis.orthonormalized()
	var units := maxf(hold.bag_scale, 0.01) # world metres per bag unit
	# The bag's own acceleration (world), from how it's been moving.
	var velocity := (frame.origin - _last_frame.origin) / maxf(delta, 0.0001) if _have_last else Vector3.ZERO
	var accel := (velocity - _last_velocity) / maxf(delta, 0.0001) if _have_last else Vector3.ZERO
	accel = accel.limit_length(60.0)
	var push := basis.inverse() * (Vector3(0.0, -9.8, 0.0) - accel * INERTIA) / units
	# A turn of the bag: what's inside lags behind it, swirling.
	var turn := Basis.IDENTITY
	if _have_last and held:
		var change := (basis.inverse() * _last_frame.basis.orthonormalized()).get_rotation_quaternion()
		turn = Basis(Quaternion.IDENTITY.slerp(change, SWIRL))
	_last_frame = Transform3D(basis, frame.origin)
	_last_velocity = velocity
	_have_last = true
	var inside := _inside()
	var middle := inside.get_center()
	for body in _bodies:
		var p: Vector3 = body.p
		var v: Vector3 = body.v
		p = middle + turn * (p - middle)
		v = turn * v + push * delta
		v *= maxf(1.0 - DAMPING * delta, 0.0)
		body.p = p + v * delta
		body.v = v
	for iteration in 3:
		for i in _bodies.size():
			_keep_inside(_bodies[i], inside)
			for j in range(i + 1, _bodies.size()):
				_separate(_bodies[i], _bodies[j])


## Back inside the walls, floor and lid, losing speed into them.
func _keep_inside(body: Dictionary, inside: AABB) -> void:
	var half: Vector3 = body.half
	var p: Vector3 = body.p
	var v: Vector3 = body.v
	for axis in 3:
		var low := inside.position[axis] + half[axis]
		var high := inside.end[axis] - half[axis]
		if low > high:
			p[axis] = (inside.position[axis] + inside.end[axis]) * 0.5
			v[axis] = 0.0
		elif p[axis] < low:
			p[axis] = low
			v[axis] = absf(v[axis]) * BOUNCE
		elif p[axis] > high:
			p[axis] = high
			v[axis] = -absf(v[axis]) * BOUNCE
	body.p = p
	body.v = v


## Two items overlapping: pushed apart along the shallowest way out (the
## bigger one moves less), and stop moving into each other.
func _separate(a: Dictionary, b: Dictionary) -> void:
	var ha: Vector3 = a.half
	var hb: Vector3 = b.half
	var gap: Vector3 = (b.p as Vector3) - (a.p as Vector3)
	var depth := ha + hb - gap.abs()
	if depth.x <= 0.0 or depth.y <= 0.0 or depth.z <= 0.0:
		return
	var axis := 0
	if depth.y < depth[axis]:
		axis = 1
	if depth.z < depth[axis]:
		axis = 2
	var sign := 1.0 if gap[axis] >= 0.0 else -1.0
	var mass_a := ha.x * ha.y * ha.z
	var mass_b := hb.x * hb.y * hb.z
	var share_a := mass_b / maxf(mass_a + mass_b, 0.000001)
	var pa: Vector3 = a.p
	var pb: Vector3 = b.p
	pa[axis] -= sign * depth[axis] * share_a
	pb[axis] += sign * depth[axis] * (1.0 - share_a)
	a.p = pa
	b.p = pb
	var va: Vector3 = a.v
	var vb: Vector3 = b.v
	var closing := (vb[axis] - va[axis]) * sign # below 0: moving into each other
	if closing < 0.0:
		var change := -closing * (1.0 + BOUNCE)
		va[axis] -= sign * change * share_a
		vb[axis] += sign * change * (1.0 - share_a)
		a.v = va
		b.v = vb


## The props where the simulation has them, leaning the way they slide.
func _place_props() -> void:
	for body in _bodies:
		var node := body.node as Node3D
		if node == null:
			continue
		var v: Vector3 = body.v
		var lean := Basis.from_euler(Vector3(clampf(v.z * 0.6, -0.5, 0.5), 0.0, clampf(-v.x * 0.6, -0.5, 0.5)))
		node.transform = Transform3D(lean * Basis(Vector3.UP, body.yaw), body.p)


## The bodies match what's in the pack: one for each pill packet, bandage and
## ammo box (up to three of a kind), one gun, one kit... New ones drop in
## from the top; gone ones vanish; the rest stay where they've rolled to.
func _sync_bodies(stacks: Array[Dictionary]) -> void:
	if _hovered >= 0 and _hovered < _bodies.size():
		_outline_on(_bodies[_hovered].node, false)
	_hovered = -1
	var wanted := {} # "kind:weapon" -> copies
	for stack in stacks:
		var copies := 1 if stack.kind in [Backpack.Kind.GUN, Backpack.Kind.CAMP_KIT] else mini(stack.count, 3)
		wanted["%d:%s" % [stack.kind, stack.weapon.resource_path if stack.weapon else ""]] = [stack, copies]
	var kept: Array[Dictionary] = []
	var have := {}
	for body in _bodies:
		var key: String = body.key
		var limit: int = wanted[key][1] if wanted.has(key) else 0
		if int(have.get(key, 0)) < limit:
			have[key] = int(have.get(key, 0)) + 1
			kept.append(body)
		elif is_instance_valid(body.node):
			(body.node as Node).queue_free()
	_bodies = kept
	var inside := _inside()
	for key: String in wanted:
		var stack: Dictionary = wanted[key][0]
		for i in int(wanted[key][1]) - int(have.get(key, 0)):
			var body := _new_body(stack, key, inside)
			if not body.is_empty():
				_bodies.append(body)


## A new item: its prop (fitted to the bag -- a gun no wider than the inside,
## the user's), a click zone round it, dropped in near the top.
func _new_body(stack: Dictionary, key: String, inside: AABB) -> Dictionary:
	var model := _model_for(stack)
	if model == null:
		return {}
	var holder := Node3D.new()
	_items.add_child(holder)
	holder.add_child(model)
	var box := _bounds(model)
	var units := maxf(hold.bag_scale, 0.01)
	var want := hold.item_size / units # its longest side, in bag units
	if stack.kind == Backpack.Kind.GUN:
		want = minf(inside.size.x, inside.size.z) * 0.95
	want = minf(want, minf(inside.size.x, inside.size.z) * 0.95)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := want / maxf(longest, 0.0001)
	model.scale *= fit
	model.position -= box.get_center() * fit
	var half := (box.size * fit * 0.5).max(Vector3.ONE * 0.004 / units)
	var pick := Area3D.new()
	pick.collision_layer = ITEM_LAYER
	pick.collision_mask = 0
	pick.monitoring = false
	var shape := CollisionShape3D.new()
	var pick_box := BoxShape3D.new()
	pick_box.size = half * 2.0
	shape.shape = pick_box
	pick.add_child(shape)
	holder.add_child(pick)
	var drop := Vector3(randf_range(inside.position.x + half.x, inside.end.x - half.x), inside.end.y - half.y,
			randf_range(inside.position.z + half.z, inside.end.z - half.z))
	return {key = key, kind = stack.kind, half = half, p = drop, v = Vector3.ZERO, node = holder, area = pick,
			yaw = 0.0 if stack.kind == Backpack.Kind.GUN else randf() * TAU}


## The item under the cursor lit up with the interactables' outline.
func _update_hover() -> void:
	var index := -1
	if unzip >= 1.0:
		var hit := _under_cursor(get_viewport().get_mouse_position())
		for i in _bodies.size():
			if _bodies[i].area == hit:
				index = i
				break
	if index == _hovered:
		return
	if _hovered >= 0 and _hovered < _bodies.size():
		_outline_on(_bodies[_hovered].node, false)
	_hovered = index
	if index >= 0:
		_outline_on(_bodies[index].node, true)


func _outline_on(node: Variant, on: bool) -> void:
	if not is_instance_valid(node):
		return
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = InteractHighlight.OUTLINE_SHADER
	for mesh in (node as Node).find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _outline if on else null


## What the cursor's over (an item's click zone), or null.
func _under_cursor(at: Vector2) -> Object:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * 3.0)
	query.collision_mask = ITEM_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider if not hit.is_empty() else null


## The prop for a stack (a fresh copy).
func _model_for(stack: Dictionary) -> Node3D:
	if stack.kind == Backpack.Kind.GUN:
		var weapon: WeaponData = stack.weapon
		if weapon and weapon.viewmodel_scene:
			var gun := weapon.viewmodel_scene.instantiate() as Node3D
			gun.basis = Basis.from_euler(weapon.model_facing_degrees * (PI / 180.0))
			return _wrapped(gun)
		return null
	if stack.kind == Backpack.Kind.SILK:
		return _silk()
	if stack.kind == Backpack.Kind.GRENADES:
		var grenade := _player.weapons.grenade_weapon()
		if grenade and grenade.viewmodel_scene:
			return _wrapped(grenade.viewmodel_scene.instantiate() as Node3D)
	var source: Variant = PROPS.get(stack.kind)
	if source == null:
		return null
	if source is Array:
		var pack := _scene(source[0])
		if pack == null:
			return null
		var whole := pack.instantiate() as Node3D
		var part := whole.find_child(source[1], true, false) as MeshInstance3D
		var copy: MeshInstance3D = null
		if part:
			copy = MeshInstance3D.new()
			copy.mesh = part.mesh
			for surface in part.get_surface_override_material_count():
				copy.set_surface_override_material(surface, part.get_surface_override_material(surface))
		whole.free()
		return _wrapped(copy) if copy else null
	var scene := _scene(source)
	return _wrapped(scene.instantiate() as Node3D) if scene else null


## A model inside a plain node (so scaling and centring it never touches the
## model's own transform), shadowless.
static func _wrapped(model: Node3D) -> Node3D:
	if model == null:
		return null
	var holder := Node3D.new()
	holder.add_child(model)
	for node in holder.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


## Silk: a few pale cocoon balls stuck together.
static func _silk() -> Node3D:
	var holder := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.9, 0.84)
	material.roughness = 0.4
	for i in 3:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5 - i * 0.1
		sphere.height = (0.5 - i * 0.1) * 2.4
		sphere.radial_segments = 8
		sphere.rings = 5
		sphere.material = material
		ball.mesh = sphere
		ball.position = Vector3(i * 0.35 - 0.35, 0.0, (i % 2) * 0.3)
		holder.add_child(ball)
	return holder


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


## A node's whole box (its own space), from every mesh under it.
static func _bounds(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var place := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk and walk != root:
			place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		var box := place * mesh.get_aabb()
		total = box if first else total.merge(box)
		first = false
	if root is MeshInstance3D and (root as MeshInstance3D).mesh:
		total = (root as MeshInstance3D).get_aabb() if first else total.merge((root as MeshInstance3D).get_aabb())
	return total


# ---- Clicking ------------------------------------------------------------------

## While it's open, the mouse is a cursor (looking stops; walking doesn't).
func _set_cursor(on: bool) -> void:
	if not _player or not _player.is_multiplayer_authority():
		return
	if on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not on and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _player.bag_open == false and not get_tree().paused \
			and swing <= 0.0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if unzip < 1.0 or not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	var hit := _under_cursor(click.position)
	if hit == null:
		return
	for body in _bodies:
		if body.area == hit:
			_player.request_use(body.kind)
			get_viewport().set_input_as_handled()
			return

# ---- The bag itself ------------------------------------------------------------

## The pack's backpack model, its materials swapped for one that can cut its
## top away (the unzip) and shows its insides darker.
func _build_bag() -> void:
	var pack := _scene(BAG_SCENE)
	if pack == null:
		return
	var whole := pack.instantiate() as Node3D
	var source := whole.find_child("Backpack", true, false) as MeshInstance3D
	if source == null:
		whole.free()
		return
	_bag = MeshInstance3D.new()
	_bag.name = "Bag"
	_bag.mesh = source.mesh
	_bag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bag_box = source.mesh.get_aabb()
	var shader := preload("res://shaders/backpack_open.gdshader")
	for surface in source.mesh.get_surface_count():
		var original := source.get_active_material(surface) as BaseMaterial3D
		var material := ShaderMaterial.new()
		material.shader = shader
		if original:
			material.set_shader_parameter("albedo_texture", original.albedo_texture)
			material.set_shader_parameter("albedo_color", original.albedo_color)
		_bag.set_surface_override_material(surface, material)
		_materials.append(material)
	whole.free()
	# Centred on its own middle, so placing it places the middle.
	_bag.position = -_bag_box.get_center() * hold.bag_scale
	add_child(_bag)
