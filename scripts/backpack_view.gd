class_name BackpackView
extends Node3D

## The open backpack in first person (the user's: diegetic, no menus). Tab
## and your left arm swings the pack round off your back and holds it up by
## its top handle in a fist; the top unzips and you see inside -- every kind
## thing you carry as a small 3D prop, really tumbling and sliding about in it as
## you move (and shuffled now and then on your back as you climb), the one
## under the cursor outlined like anything you can use. Click a prop to use
## it (Backpack.use() through the input packet). Tab again and it goes back
## on your back.
## Picking (the user's): you keep looking around with the mouse while it's
## open; hold Left Alt and looking stops, a small cursor appears over the
## bag's opening and the mouse moves it over the items. Hold left click on
## one to grab it and move it about in the bag (it shoves the others aside);
## double-click one to use it. Let go of Alt and you're looking again.
## How it's held -- the bag's place, the hand on it, the fist, the elbow,
## the unzip, each finger -- is BackpackHold (scenes/player/backpack_hold.tres),
## tuned in game with O while it's out (Viewmodel) and saved with F3.
## Lives with the first-person arms (same space, so it sways and kicks with
## them). Your own view only: nothing here is simulation.

const HOLD_PATH := "res://scenes/player/backpack_hold.tres"
## The pack (the user's: the survival pack's second backpack, its straps
## close in so they don't clip into anything) and its texture.
const BAG_SCENE := "res://art/Survival/Models/Survival.fbx"
const BAG_NODE := "Backpack_001"
const BAG_TEXTURE := "res://art/Survival/Textures/Backpack.png"
## The forest props (the camp kit's sleeping pad) and their texture (the
## model doesn't point at it itself).
const FOREST_SCENE := "res://art/PSX Forest Props.fbx"
const FOREST_TEXTURE := "res://art/Texture/Texture Forest.png"

const MEGA := "res://NEWPSXMODELS/PSX Mega Pack/Models/GLB (recommended)/"
## Clicks only ever hit the item props (their own physics layer).
const ITEM_LAYER := 1 << 19
## The look of each kind: a model (a scene path, or [scene, node name] in a
## pack), or empty for one made in code.
const PROPS := {
	# The bottle you hold when you take them (weapons/pills.tres), the user's.
	Backpack.Kind.PILLS: MEGA + "Items & Weapons/pills_bottle_2.glb",
	Backpack.Kind.BANDAGE: MEGA + "Items & Weapons/bandage_mp_1.glb",
	Backpack.Kind.BULLETS: MEGA + "Items & Weapons/ammo_box_mp_1.glb",
	# A box with its shells showing (the user's: not the "Big Chief" box).
	Backpack.Kind.SHELLS: MEGA + "Items & Weapons/shotgun_ammo_2.glb",
	# The RPG's own rocket (its loaded rocket is a part of its model).
	Backpack.Kind.ROCKETS: ["res://art/weapons/NEWPSXWEAPONS/RPG/RPG.glb", "Rocket"],
	Backpack.Kind.SCRAP: MEGA + "Small Props/tin_can_mp_1_rusty.glb",
	Backpack.Kind.CAMP_KIT: [FOREST_SCENE, "Foam Sleeping Pad"],
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
var _contents_left := 0.0
var _time := 0.0
## Picking: Left Alt held; the cursor (pixels from the bag's opening on
## screen) and its dot.
var _alt_held := false
var _cursor := Vector2.ZERO
var _dot: Control
## Tuning: the items' box drawn as a yellow wireframe, seen through the bag.
var _box_lines: MeshInstance3D
## The weight over the bag (the user's): only once you're overweight; red
## once it's too heavy.
var _weight_label: Label3D

static var _scenes := {}
static var _forest: StandardMaterial3D
static var _pack: ArrayMesh
static var _pack_look: StandardMaterial3D
static var _hull := {}


func setup(player: PlayerMovement, arms: FirstPersonArms) -> void:
	_player = player
	_arms = arms
	hold = load(HOLD_PATH) as BackpackHold if ResourceLoader.exists(HOLD_PATH) else BackpackHold.new()
	_build_bag()
	# The props, in metres (not under the scaled bag), placed where the bag's
	# own origin is: the items' world's frame.
	_items = Node3D.new()
	_items.name = "Items"
	add_child(_items)
	visible = false
	player.look_filter = _free_aim
	_make_dot()
	_weight_label = Label3D.new()
	_weight_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_weight_label.no_depth_test = true
	_weight_label.shaded = false
	_weight_label.render_priority = 10
	_weight_label.font_size = 40
	_weight_label.outline_size = 10
	_weight_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_weight_label.pixel_size = 0.0005
	_weight_label.visible = false
	add_child(_weight_label)


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
		_cursor = Vector2.ZERO
		_alt_held = false
		_held = {}
		if not out and _shuffle_left <= 0.0:
			_freeze(true) # on your back: they stop
	visible = out
	if not visible:
		_dot.visible = false
		_weight_label.visible = false
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
	_items.position = _bag.position
	# Unzipped: the top cut away down to the opening.
	var clip := _bag_box.end.y - _bag_box.size.y * hold.zipper_open_share * smoothstep(0.0, 1.0, unzip)
	for material in _materials:
		material.set_shader_parameter("clip_height", clip if unzip > 0.0 else _bag_box.end.y + 1.0)
		# The straps (the -x side past the back) hidden while it's open: held
		# up like this they lay across the opening (the user's).
		material.set_shader_parameter("strap_x", _bag_box.position.x + _bag_box.size.x * STRAP_CUT if unzip > 0.0 else -1000.0)
	_hold_with_left_hand()
	_update_items(delta)
	if _box_lines and _box_lines.visible:
		_draw_container()
	_show_weight()
	_dot.visible = _picking()
	_dot.position = _cursor_at() - _dot.size * 0.5
	return true


## The items while it's open: in step with what's in the pack, simulated in
## the bag as it's held, drawn, the one under the cursor outlined.
func _update_items(delta: float) -> void:
	_ensure_world()
	# What's in the pack, looked at four times a second (not every frame).
	_contents_left -= delta
	if _contents_left <= 0.0 or _bodies.is_empty():
		_contents_left = 0.25
		var stacks := _player.backpack.stacks()
		var key := ""
		for stack in stacks:
			key += "%d:%d:%s," % [stack.kind, mini(stack.count, MAX_COPIES), stack.weapon.resource_path if stack.weapon else ""]
		if key != _shown_key:
			_shown_key = key
			_sync_bodies(stacks)
	_items.visible = unzip > 0.3
	_push_items(delta)
	_update_hover()


## Away on your back (the user's: nearly free, just vaguely rearranged after
## you've moved a while): twice a second, how much you've been thrown about
## (distance, and jolts: landings, launches) is added up; once it's enough
## the items are let tumble for a moment. Frozen in between.
func _on_your_back(delta: float) -> void:
	if _bodies.is_empty():
		return
	if _shuffle_left > 0.0:
		_shuffle_left -= delta
		if _shuffle_left <= 0.0:
			_freeze(true)
		return
	_on_back_left -= delta
	if _on_back_left > 0.0:
		return
	_on_back_left = RESTLESS_CHECK
	var velocity := _player.velocity
	_restless += velocity.length() * RESTLESS_CHECK + (velocity - _back_velocity).length()
	_back_velocity = velocity
	if _restless >= RESTLESS_SHUFFLE:
		_restless = 0.0
		_shuffle()


## The pack's weight just above the bag (straight up on screen, however it's
## turned): only while you're overweight, white, then red once too heavy.
func _show_weight() -> void:
	var pack := _player.backpack
	_weight_label.visible = pack.is_overweight() and unzip > 0.5
	if not _weight_label.visible:
		return
	_weight_label.text = "%.1f kg" % pack.current_weight()
	_weight_label.modulate = Color(0.9, 0.12, 0.08) if pack.is_too_heavy() else Color(0.95, 0.93, 0.86)
	var camera := get_viewport().get_camera_3d()
	var up := camera.global_basis.y if camera else Vector3.UP
	var reach := _bag_box.size.length() * 0.5 * hold.bag_scale * 0.75
	_weight_label.global_position = global_position + up * (reach + 0.03)


## Tuning (Viewmodel, O then X): the items' container (the pack's own shape)
## shown as a yellow wireframe, through the bag, or hidden.
func show_container(on: bool) -> void:
	if on and _box_lines == null and _bag:
		_box_lines = MeshInstance3D.new()
		_box_lines.mesh = ImmediateMesh.new()
		_box_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.85, 0.1)
		material.no_depth_test = true
		material.render_priority = 10
		_box_lines.material_override = material
		_bag.add_child(_box_lines)
	if _box_lines:
		_box_lines.visible = on
		if on:
			_draw_container()


## The pack's hull's edges, and the lid under the opening.
func _draw_container() -> void:
	var lines := _box_lines.mesh as ImmediateMesh
	lines.clear_surfaces()
	var hull := pack_hull()
	var edges: PackedVector3Array = hull.get("edges", PackedVector3Array())
	if edges.is_empty():
		return
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in edges:
		lines.surface_add_vertex(point)
	var space := _space()
	var lid := space.end.y
	for corner in [[0, 0, 1, 0], [1, 0, 1, 1], [1, 1, 0, 1], [0, 1, 0, 0]]:
		lines.surface_add_vertex(Vector3(lerpf(space.position.x, space.end.x, corner[0]), lid, lerpf(space.position.z, space.end.z, corner[1])))
		lines.surface_add_vertex(Vector3(lerpf(space.position.x, space.end.x, corner[2]), lid, lerpf(space.position.z, space.end.z, corner[3])))
	lines.surface_end()


## One rough rearrangement on your back: the items woken, given a knock, and
## left to fall and tumble a moment (SHUFFLE_TIME), then frozen again.
func _shuffle() -> void:
	_ensure_world()
	for body in _bodies:
		var rigid := body.body as RigidBody3D
		rigid.freeze = false
		rigid.constant_force = Vector3(0.0, -9.8, 0.0) * rigid.mass
		rigid.apply_central_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)) * 0.5 * rigid.mass)
		rigid.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.002)
	_shuffle_left = SHUFFLE_TIME

## The left hand in a fist round the handle, the arm reaching it by IK.
func _hold_with_left_hand() -> void:
	var handle_local := _bag_box.get_center() + _bag_box.size * hold.handle_point
	var handle := transform * (_bag.transform * handle_local) # this node's parent's space: the arms'
	# Gripping from above: the palm down onto the handle, the fingers along it.
	var grip := transform.basis.orthonormalized() * Basis(Vector3.RIGHT, PI)
	var to_rig := _arms.transform.affine_inverse()
	_arms.set_bag(true)
	_arms.set_bag_fingers(hold.finger_curl)
	_arms.set_support_grip(to_rig * handle, to_rig.basis * grip, hold.fist, hold.hand_rotation_degrees,
			to_rig.basis * hold.elbow_direction, hold.elbow_degrees)


## Puts the arm back to whatever the gun wants (the Viewmodel calls this as
## the bag goes away).
func release_arm() -> void:
	if _arms:
		_arms.set_bag(false)
	if _dot:
		_dot.visible = false


# ---- The items: real physics inside the bag -------------------------------------
# Every item is a real rigid body (the user's: they tumble over each other,
# at about their real size), in a little physics world of the bag's own
# (a SubViewport with its own World3D, never drawn) so nothing in the level
# touches them. The bag's walls are its own shape (the user's: not a box):
# its hull, worked out from the model, brought in by the wall's thickness,
# as slabs round the outside, with a lid just under the opening. Each item's
# shape is its model's own (convex), so cans roll and packets flip.
# Simulated in the bag's frame: the pull on them is gravity turned the way
# the bag's held, plus the bag's own movement (swing your view, jump, land,
# get launched: they slosh), and a flick of the bag swirls them (the turn's
# change pushes them the other way, as it would). The props you see copy
# their bodies every frame. On your back: frozen, but now and then shuffled
# (_shuffle), so you find them moved when you next look.

## Strength of the push from the bag's own movement (1 = fully real).
const INERTIA := 0.6
## How much a change in the bag's turning pushes what's inside (0..1).
const SWIRL := 0.35
## How thick the pack's walls are (metres: a little thicker than they look,
## for the physics' few millimetres of give), and how far under the opening
## the items stop (bag units), so none pokes out of the top.
const WALL := 0.045
const LID_GAP := 0.02
## The walls' slabs (metres thick).
const SLAB := 0.3
## The straps' share of the pack's width (its -x side): left out of the hull,
## and hidden while it's open.
const STRAP_CUT := 0.13
## The walls' own physics layer in the items' world (items collide with each
## other on 1, and with the walls).
const CONTAINER_LAYER := 2
## At most this many of one kind shown (a crowded pack squeezes things
## through its walls).
const MAX_COPIES := 2
## Nothing's longer than this share of the inside's narrowest width (the
## user's: things shrink to fit the bag, never poke out of it).
const FIT_SHARE := 0.8
## On your back: how often the jostling's added up (s), how much (metres
## moved + m/s of jolts) shuffles the items once, and how long they tumble.
const RESTLESS_CHECK := 0.5
const RESTLESS_SHUFFLE := 40.0
const SHUFFLE_TIME := 1.2
## About how big each thing is in real life (metres, its longest side). A
## gun is its own (WeaponData.backpack_length), or as long as fits.
const REAL_SIZE := {
	Backpack.Kind.PILLS: 0.09, Backpack.Kind.BANDAGE: 0.1, Backpack.Kind.BULLETS: 0.09,
	Backpack.Kind.SHELLS: 0.11, Backpack.Kind.ROCKETS: 0.26, Backpack.Kind.GRENADES: 0.22,
	Backpack.Kind.SCRAP: 0.11, Backpack.Kind.SILK: 0.12, Backpack.Kind.CAMP_KIT: 0.3,
}

var _bodies: Array[Dictionary] = [] # {key, kind, body: RigidBody3D, node: the prop, area: its click zone}
var _world: SubViewport
var _container: StaticBody3D
var _built_scale := 0.0
## The container, in metres: its walls (each normal . p <= d inside, the lid
## too), its middle, and how far across it is along x, y and z there.
var _walls: Array[Plane] = []
## The real walls: the pack's surface pushed in by WALL (triangles, metres).
var _faces := PackedVector3Array()
var _inner_center := Vector3.ZERO
var _inner_size := Vector3.ONE
var _last_axes := Basis.IDENTITY
var _last_origin := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _last_spin := Vector3.ZERO
var _last_pull := Vector3.ZERO
var _have_last := false
var _on_back_left := 0.0
var _restless := 0.0
var _back_velocity := Vector3.ZERO
var _shuffle_left := 0.0
var _frozen := false
var _hovered := -1
var _outline: ShaderMaterial
## Picking: the item held by left click (moved about by the cursor), the
## plane it's moved on (through it, facing you), and the last click (a
## second on the same item within DOUBLE_CLICK uses it).
const DOUBLE_CLICK := 0.35
const DRAG_FOLLOW := 0.06
const DRAG_TOP_SPEED := 3.0
var _held: Dictionary = {}
var _held_plane := Plane()
var _last_click_msec := -100000
var _last_click_body: Object

static var _item_material: PhysicsMaterial


## Where the items stop under the opening (bag units).
func _lid_height() -> float:
	return _bag_box.end.y - _bag_box.size.y * hold.zipper_open_share - LID_GAP


## The box round the inside (bag units: for the cursor's home and the
## tuning view): the pack's bounds brought in by its wall, up to the lid.
func _space() -> AABB:
	var box := _bag_box.grow(-WALL / maxf(hold.bag_scale, 0.01))
	box.size.y = maxf(_lid_height() - box.position.y, 0.01)
	return box


## The same, in metres (the items' world).
func _space_m() -> AABB:
	var box := _space()
	return AABB(box.position * hold.bag_scale, box.size * hold.bag_scale)


## The items' own physics world, and the bag's walls in it (made again, and
## the items with them, if the bag's size is tuned).
func _ensure_world() -> void:
	if _world == null:
		_world = SubViewport.new()
		_world.name = "ItemsWorld"
		_world.own_world_3d = true
		_world.size = Vector2i(2, 2)
		_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_world)
	if absf(_built_scale - hold.bag_scale) > 0.0005:
		_built_scale = hold.bag_scale
		_clear_bodies()
		_build_container()


## The bag's walls (the user's: true to the model, not a box or a hull): the
## pack's own surface pushed in by WALL (_inset_faces), as collision; the lid
## under the opening; and, outside it all, a slab past each side of its hull
## as a backstop. The walls are on their own layer (CONTAINER_LAYER).
func _build_container() -> void:
	if _container:
		_container.free()
	_container = StaticBody3D.new()
	_container.collision_layer = CONTAINER_LAYER
	_container.collision_mask = 0
	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = 0.1
	_container.physics_material_override = material
	var s := hold.bag_scale
	_faces = _inset_faces(s)
	var surface := CollisionShape3D.new()
	var shell := ConcavePolygonShape3D.new()
	shell.set_faces(_faces)
	shell.backface_collision = true
	surface.shape = shell
	_container.add_child(surface)
	var sides: Array[Plane] = []
	for side: Plane in pack_hull().get("planes", []):
		sides.append(Plane(side.normal, side.d * s))
	var lid := Plane(Vector3.UP, _lid_height() * s)
	sides.append(lid)
	_walls = [lid]
	_measure_inside(s)
	for side in sides:
		var shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(4.0, 4.0, SLAB)
		shape.shape = slab
		var up := Vector3.UP if absf(side.normal.y) < 0.99 else Vector3.FORWARD
		shape.transform = Transform3D(Basis.looking_at(-side.normal, up), side.normal * (side.d + SLAB * 0.5))
		_container.add_child(shape)
	_world.add_child(_container)


## The pack's surface (triangles, metres) pushed WALL inward: each corner
## moved in along the smoothed normal of the faces round it.
func _inset_faces(s: float) -> PackedVector3Array:
	var faces := pack_mesh().get_faces()
	var middle: Vector3 = pack_hull().get("middle", _bag_box.get_center())
	var normals := {}
	for i in range(0, faces.size() - 2, 3):
		var turn := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		for k in 3:
			var key := faces[i + k].snapped(Vector3.ONE * 0.0005)
			normals[key] = (normals.get(key, Vector3.ZERO) as Vector3) + turn
	# Which way the faces wind: out is away from the middle, mostly.
	var outward := 0.0
	for key: Vector3 in normals:
		outward += (normals[key] as Vector3).normalized().dot(key - middle)
	var out_sign := 1.0 if outward >= 0.0 else -1.0
	var inset := WALL / maxf(s, 0.01)
	var result := PackedVector3Array()
	result.resize(faces.size())
	for i in faces.size():
		var normal := (normals[faces[i].snapped(Vector3.ONE * 0.0005)] as Vector3).normalized() * out_sign
		result[i] = (faces[i] - normal * inset) * s
	return result


## The inside's middle (the hull's, kept under the lid) and how far across
## it is through there, along x, y and z -- to the real walls.
func _measure_inside(s: float) -> void:
	var middle: Vector3 = pack_hull().get("middle", _bag_box.get_center()) * s
	middle.y = minf(middle.y, _lid_height() * s - 0.05)
	_inner_center = middle
	for axis in 3:
		var along := Vector3.ZERO
		along[axis] = 1.0
		_inner_size[axis] = _reach(middle, along) + _reach(middle, -along)


## How far from `from` the walls (the real ones, and the lid) are along
## `direction`.
func _reach(from: Vector3, direction: Vector3) -> float:
	var nearest := 10.0
	for i in range(0, _faces.size() - 2, 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, direction, _faces[i], _faces[i + 1], _faces[i + 2])
		if hit != null:
			nearest = minf(nearest, ((hit as Vector3) - from).length())
	for wall in _walls:
		var facing := wall.normal.dot(direction)
		if facing > 0.0001:
			nearest = minf(nearest, (wall.d - wall.normal.dot(from)) / facing)
	return maxf(nearest, 0.0)


## Whether a ball of `radius` at `point` is inside the walls: nothing between
## it (and `radius` beyond it) and the middle.
func _inside_walls(point: Vector3, radius: float) -> bool:
	var offset := point - _inner_center
	var distance := offset.length()
	if distance < 0.001:
		return true
	return _reach(_inner_center, offset / distance) >= distance + radius


## Whether a body's middle has got outside the real walls (a ray from the
## inside's middle to it crosses them) -- quick, through the physics.
func _escaped(at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_inner_center, at)
	query.collision_mask = CONTAINER_LAYER
	query.hit_back_faces = true
	return not _container.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Where a new item of `size` drops in: over the middle of the opening (a
## little to the side, at random), as high as it fits -- checked against
## the walls, so it never starts outside them.
func _drop_point(size: Vector3) -> Vector3:
	var radius := size.length() * 0.5
	var top := _inner_center.y + _reach(_inner_center, Vector3.UP) - radius
	for attempt in 8:
		var spread := 0.35 * (1.0 - attempt / 8.0)
		var point := _inner_center + Vector3(randf_range(-0.5, 0.5) * _inner_size.x * spread, 0.0,
				randf_range(-0.5, 0.5) * _inner_size.z * spread)
		point.y = maxf(top, _inner_center.y)
		if _inside_walls(point, radius):
			return point
	return _inner_center

func _clear_bodies() -> void:
	for body in _bodies:
		if is_instance_valid(body.body):
			(body.body as Node).queue_free()
		if is_instance_valid(body.node):
			(body.node as Node).queue_free()
	_bodies.clear()
	_shown_key = ""
	_hovered = -1


## Held out, every frame: the pull on each item -- gravity turned into the
## bag's frame, less the bag's own acceleration -- and a flick of the bag
## swirling them; then the props shown where their bodies are.
func _push_items(delta: float) -> void:
	if _frozen:
		_freeze(false)
	var frame := _bag.global_transform
	var axes := frame.basis.orthonormalized()
	var velocity := (frame.origin - _last_origin) / maxf(delta, 0.0001) if _have_last else Vector3.ZERO
	var accel := ((velocity - _last_velocity) / maxf(delta, 0.0001)).limit_length(60.0) if _have_last else Vector3.ZERO
	var pull := axes.inverse() * (Vector3(0.0, -9.8, 0.0) - accel * INERTIA)
	# The bag turning: in its frame what's inside turns the other way. A
	# change in that turning (a flick, a stop) pushes them (the Euler force).
	var spin := Vector3.ZERO
	if _have_last:
		var change := (axes.inverse() * _last_axes).get_rotation_quaternion()
		var angle := change.get_angle()
		if angle > 0.00001:
			spin = change.get_axis().normalized() * angle / maxf(delta, 0.0001)
	var kick := (spin - _last_spin) * SWIRL if _have_last else Vector3.ZERO
	var middle := _space_m().get_center()
	var wake := pull.distance_to(_last_pull) > 0.3 or kick.length() > 0.5
	for body in _bodies:
		var rigid := body.body as RigidBody3D
		# Got outside the real walls somehow (squeezed through): dropped back in.
		if _escaped(rigid.global_position):
			rigid.global_position = _drop_point(Vector3.ONE * 0.05)
			rigid.linear_velocity = Vector3.ZERO
			rigid.angular_velocity = Vector3.ZERO
		rigid.constant_force = pull * rigid.mass
		if not _held.is_empty() and _held.body == rigid:
			_follow_cursor(rigid)
			(body.node as Node3D).transform = rigid.global_transform
			continue
		if kick != Vector3.ZERO:
			rigid.linear_velocity += kick.cross(rigid.global_position - middle).limit_length(2.0)
		if wake:
			rigid.sleeping = false
		(body.node as Node3D).transform = rigid.global_transform
	_last_axes = axes
	_last_origin = frame.origin
	_last_velocity = velocity
	_last_spin = spin
	if wake:
		_last_pull = pull
	_have_last = true


## The held item pulled toward where the cursor points on its plane (kept
## inside the walls), by its speed -- a real push, so it shoves the others.
func _follow_cursor(rigid: RigidBody3D) -> void:
	if not _picking():
		_held = {}
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := _cursor_at()
	var hit: Variant = _held_plane.intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	if hit == null:
		return
	var target := _items.global_transform.affine_inverse() * (hit as Vector3)
	# Kept inside the real walls: pulled back toward the middle till it is.
	var offset := target - _inner_center
	var distance := offset.length()
	if distance > 0.001:
		var room := _reach(_inner_center, offset / distance) - 0.04
		if distance > room:
			target = _inner_center + offset / distance * maxf(room, 0.0)
	rigid.sleeping = false
	rigid.linear_velocity = ((target - rigid.global_position) / DRAG_FOLLOW).limit_length(DRAG_TOP_SPEED)
	rigid.angular_velocity *= 0.8


## Every item stopped (on your back) or let go again.
func _freeze(on: bool) -> void:
	_frozen = on
	for body in _bodies:
		(body.body as RigidBody3D).freeze = on


## The bodies match what's in the pack: one for each pill packet, bandage and
## ammo box (up to three of a kind), one gun, one kit... New ones drop in
## from the top; gone ones vanish; the rest stay where they've tumbled to.
func _sync_bodies(stacks: Array[Dictionary]) -> void:
	_ensure_world()
	if _hovered >= 0 and _hovered < _bodies.size():
		_outline_on(_bodies[_hovered].node, false)
	_hovered = -1
	var wanted := {} # "kind:weapon" -> copies
	for stack in stacks:
		var copies := 1 if stack.kind in [Backpack.Kind.GUN, Backpack.Kind.CAMP_KIT] else mini(stack.count, MAX_COPIES)
		wanted["%d:%s" % [stack.kind, stack.weapon.resource_path if stack.weapon else ""]] = [stack, copies]
	var kept: Array[Dictionary] = []
	var have := {}
	for body in _bodies:
		var key: String = body.key
		var limit: int = wanted[key][1] if wanted.has(key) else 0
		if int(have.get(key, 0)) < limit:
			have[key] = int(have.get(key, 0)) + 1
			kept.append(body)
		else:
			if is_instance_valid(body.node):
				(body.node as Node).queue_free()
			if is_instance_valid(body.body):
				(body.body as Node).queue_free()
	_bodies = kept
	var inside := _space_m()
	for key: String in wanted:
		var stack: Dictionary = wanted[key][0]
		for i in int(wanted[key][1]) - int(have.get(key, 0)):
			var body := _new_body(stack, key, inside)
			if not body.is_empty():
				_bodies.append(body)


## How long a thing is in the bag (metres, its longest side): about its real
## size, but never more than FIT_SHARE of the inside's narrowest width (the
## user's: shrunk to fit, not poking out). A gun with no length of its own
## is as long as fits.
func _real_size(stack: Dictionary) -> float:
	# Lying along the inside's longer way across (long things drop in that way).
	var fits := maxf(_inner_size.x, _inner_size.z) * FIT_SHARE
	var sized := item_scale(stack.kind)
	if stack.kind == Backpack.Kind.GUN:
		var weapon: WeaponData = stack.weapon
		return minf(weapon.backpack_length * sized, fits) if weapon and weapon.backpack_length > 0.0 else fits * minf(sized, 1.0)
	return minf(float(REAL_SIZE.get(stack.kind, 0.1)) * sized, fits)


## A kind's own scale (BackpackHold.item_scales; 1 if not set).
func item_scale(kind: int) -> float:
	return float(hold.item_scales.get(Backpack.Kind.keys()[kind + 1], 1.0))


## Tuning (the Viewmodel's O, while picking): scroll over an item to size
## its kind; that kind's items are made again at the new size.
var tuning := false


func _resize_kind(kind: int, by: float) -> void:
	var name: String = Backpack.Kind.keys()[kind + 1]
	hold.item_scales[name] = clampf(item_scale(kind) * by, 0.2, 3.0)
	var kept: Array[Dictionary] = []
	for body in _bodies:
		if body.kind == kind:
			(body.node as Node).queue_free()
			(body.body as Node).queue_free()
		else:
			kept.append(body)
	_bodies = kept
	_hovered = -1
	_shown_key = "" # made again next look at the pack
	_contents_left = 0.0


## A new item: its prop at about its real size, a click zone round it, and
## its body (the model's own shape) dropped in at the top, any way up.
func _new_body(stack: Dictionary, key: String, inside: AABB) -> Dictionary:
	var model := _model_for(stack)
	if model == null:
		return {}
	var holder := Node3D.new()
	_items.add_child(holder)
	holder.add_child(model)
	var box := _bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := _real_size(stack) / maxf(longest, 0.0001)
	model.scale *= fit
	model.position -= box.get_center() * fit
	var size := (box.size * fit).max(Vector3.ONE * 0.01)
	var pick := Area3D.new()
	pick.collision_layer = ITEM_LAYER
	pick.collision_mask = 0
	pick.monitoring = false
	var pick_shape := CollisionShape3D.new()
	var pick_box := BoxShape3D.new()
	pick_box.size = size
	pick_shape.shape = pick_box
	pick.add_child(pick_shape)
	holder.add_child(pick)
	if _item_material == null:
		_item_material = PhysicsMaterial.new()
		_item_material.friction = 0.55
		_item_material.bounce = 0.15
	var rigid := RigidBody3D.new()
	rigid.mass = clampf(_mass_of(stack), 0.05, 6.0)
	rigid.gravity_scale = 0.0 # its pull is the bag's (constant_force)
	rigid.continuous_cd = true
	rigid.linear_damp = 0.3
	rigid.angular_damp = 0.6
	rigid.physics_material_override = _item_material
	rigid.collision_layer = 1
	rigid.collision_mask = 1 | CONTAINER_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = _shape_of(holder, size)
	rigid.add_child(shape)
	_world.add_child(rigid)
	# Any way up -- but something too long to lie across the narrow way drops
	# in lengthwise (its longest side along the inside's longer way).
	var lay := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	var long_side := maxf(size.x, maxf(size.y, size.z))
	if long_side > minf(_inner_size.x, _inner_size.z) * FIT_SHARE:
		var along := Vector3.RIGHT if size.x >= maxf(size.y, size.z) else (Vector3.UP if size.y >= size.z else Vector3.BACK)
		var lengthwise := Vector3.RIGHT if _inner_size.x >= _inner_size.z else Vector3.BACK
		lay = Basis(lengthwise, randf() * TAU) * Basis(Quaternion(along, lengthwise))
	rigid.global_transform = Transform3D(lay, _drop_point(size))
	rigid.freeze = _frozen
	holder.transform = rigid.global_transform
	return {key = key, kind = stack.kind, body = rigid, node = holder, area = pick}


func _mass_of(stack: Dictionary) -> float:
	if stack.kind == Backpack.Kind.GUN:
		return (stack.weapon as WeaponData).carry_weight if stack.weapon else 3.5
	return float(Backpack.WEIGHTS.get(stack.kind, 0.1)) * 3.0


## The prop's own shape (convex, from its meshes as they sit in `holder`),
## or a box of `size` if there's nothing to make it from.
static func _shape_of(holder: Node3D, size: Vector3) -> Shape3D:
	var points := PackedVector3Array()
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var place := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk and walk != holder:
			place = (walk as Node3D).transform * place
			walk = walk.get_parent()
		var hull := mesh.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		if hull:
			for point in hull.points:
				points.append(place * point)
	if points.size() >= 4:
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		return convex
	var box := BoxShape3D.new()
	box.size = size
	return box

## The item under the cursor lit up with the interactables' outline.
func _update_hover() -> void:
	var index := -1
	if _picking():
		var hit := _under_cursor(_cursor_at())
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
		var part := whole.find_child(source[1], true, false) as Node3D
		var copy: Node3D = null
		if part is MeshInstance3D and (part as MeshInstance3D).mesh:
			var mesh := MeshInstance3D.new()
			mesh.mesh = (part as MeshInstance3D).mesh
			textured(mesh, part as MeshInstance3D)
			copy = mesh
		elif part:
			copy = part.duplicate() as Node3D # a part made of parts (the rocket)
			copy.transform = Transform3D(part.basis, Vector3.ZERO)
			copy.visible = true
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


## A forest prop's mesh copied with its look: its own textured materials, or
## the forest props' texture where the model has none (it doesn't link it).
static func textured(copy: MeshInstance3D, source: MeshInstance3D) -> void:
	for surface in source.mesh.get_surface_count():
		var original := source.get_active_material(surface) as BaseMaterial3D
		copy.set_surface_override_material(surface, original if original and original.albedo_texture else forest_material())


## The forest props' texture as a plain PS1-looking material (shared).
static func forest_material() -> StandardMaterial3D:
	if _forest == null:
		_forest = StandardMaterial3D.new()
		_forest.albedo_texture = load(FOREST_TEXTURE) as Texture2D if ResourceLoader.exists(FOREST_TEXTURE) else null
		_forest.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_forest.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_forest.roughness = 1.0
	return _forest


# ---- Picking and clicking ------------------------------------------------------

## Whether you're picking: the bag open and Left Alt held.
func _picking() -> bool:
	return visible and unzip >= 1.0 and _alt_held


## The mouse while the bag's out (PlayerMovement.look_filter): picking, it
## all moves the cursor (kept on screen) and none of it looks; otherwise it
## all looks.
func _free_aim(motion: Vector2) -> Vector2:
	if not _picking():
		return motion
	var opening := _cursor_at() - _cursor
	var at := (opening + _cursor + motion).clamp(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_cursor = at - opening
	return Vector2.ZERO


## Where the cursor is on screen: the bag's opening on screen plus the
## cursor.
func _cursor_at() -> Vector2:
	var middle := get_viewport().get_visible_rect().size * 0.5
	var camera := get_viewport().get_camera_3d()
	if camera and _bag:
		var opening := _bag.global_transform * _space().get_center()
		if not camera.is_position_behind(opening):
			middle = camera.unproject_position(opening)
	return middle + _cursor


## The cursor's dot: small and pale, outlined dark.
func _make_dot() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_dot = ColorRect.new()
	_dot.color = Color(0.0, 0.0, 0.0, 0.8)
	_dot.size = Vector2(7.0, 7.0)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var middle := ColorRect.new()
	middle.color = Color(0.95, 0.92, 0.8)
	middle.position = Vector2(2.0, 2.0)
	middle.size = Vector2(3.0, 3.0)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.add_child(middle)
	_dot.visible = false
	layer.add_child(_dot)


## Left Alt, held or let go (watched before anything else can take it).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.keycode == KEY_ALT and not key.echo and key.location != KEY_LOCATION_RIGHT:
		_alt_held = key.pressed and visible


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_alt_held = false # alt-tabbed away: the release never comes


func _unhandled_input(event: InputEvent) -> void:
	if not _picking() or not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	# Tuning: the wheel over an item sizes its kind.
	if tuning and click.pressed and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var over := _under_cursor(_cursor_at())
		for body in _bodies:
			if body.area == over:
				_resize_kind(body.kind, 1.05 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.05)
				get_viewport().set_input_as_handled()
				return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not click.pressed:
		_held = {} # let go: it drops
		return
	var hit := _under_cursor(_cursor_at())
	if hit == null:
		return
	for body in _bodies:
		if body.area == hit:
			get_viewport().set_input_as_handled()
			var now := Time.get_ticks_msec()
			if _last_click_body == hit and now - _last_click_msec <= DOUBLE_CLICK * 1000.0:
				# Double-click: use it.
				_last_click_msec = -100000
				_held = {}
				_player.request_use(body.kind)
				return
			_last_click_msec = now
			_last_click_body = hit
			# Held: it follows the cursor on a plane through it, facing you.
			_held = body
			var camera := get_viewport().get_camera_3d()
			var where := (body.node as Node3D).global_position
			_held_plane = Plane(-camera.global_basis.z if camera else Vector3.FORWARD, where)
			return

# ---- The bag itself ------------------------------------------------------------

## The pack's model upright and in metres (it's stored lying down at 1/170):
## its straps toward -x, as the first pack's were, so it sits exactly where
## that one did. Made once, shared by every view and body.
static func pack_mesh() -> ArrayMesh:
	if _pack:
		return _pack
	var scene := _scene(BAG_SCENE)
	if scene == null:
		return null
	var whole := scene.instantiate()
	var source := whole.find_child(BAG_NODE, true, false) as MeshInstance3D
	if source and source.mesh:
		var turn := source.transform.basis
		var rotation := turn.orthonormalized()
		_pack = ArrayMesh.new()
		for surface in source.mesh.get_surface_count():
			var arrays := source.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for i in vertices.size():
				vertices[i] = turn * vertices[i]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
				for i in normals.size():
					normals[i] = (rotation * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			_pack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	whole.free()
	return _pack


## The pack's own shape for the items to keep inside (the user's: not a box):
## its convex hull, from the model -- {planes: the outward sides (normal . p
## <= d inside), edges: line pairs for the tuning view}. Worked out once.
static func pack_hull() -> Dictionary:
	if not _hull.is_empty():
		return _hull
	var mesh := pack_mesh()
	if mesh == null:
		return _hull
	# The main body only: not the straps (the -x side's outer STRAP_CUT of its
	# width) -- the gap between them and its back would count as inside, and
	# what settled there showed outside the bag.
	var box := mesh.get_aabb()
	var cut := box.position.x + box.size.x * STRAP_CUT
	var body := PackedVector3Array()
	for surface in mesh.get_surface_count():
		for point in (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if point.x > cut:
				body.append(point)
	if body.size() < 4:
		return _hull
	while body.size() % 3 != 0:
		body.append(body[0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = body
	var cloud := ArrayMesh.new()
	cloud.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var points := (cloud.create_convex_shape(true, true) as ConvexPolygonShape3D).points
	var planes: Array[Plane] = []
	var count := points.size()
	for a in count:
		for b in range(a + 1, count):
			for c in range(b + 1, count):
				var normal := (points[b] - points[a]).cross(points[c] - points[a])
				if normal.length_squared() < 1e-10:
					continue
				normal = normal.normalized()
				var d := normal.dot(points[a])
				var above := false
				var below := false
				for p in points:
					var side := normal.dot(p) - d
					if side > 0.001:
						above = true
					elif side < -0.001:
						below = true
					if above and below:
						break
				if above and below:
					continue # cuts through it: not a side
				if above:
					normal = -normal
					d = -d
				var known := false
				for plane in planes:
					if plane.normal.dot(normal) > 0.999 and absf(plane.d - d) < 0.002:
						known = true
						break
				if not known:
					planes.append(Plane(normal, d))
	# Edges: two corners that share two sides.
	var edges := PackedVector3Array()
	for a in count:
		for b in range(a + 1, count):
			var shared := 0
			for plane in planes:
				if absf(plane.distance_to(points[a])) < 0.002 and absf(plane.distance_to(points[b])) < 0.002:
					shared += 1
					if shared >= 2:
						break
			if shared >= 2:
				edges.append(points[a])
				edges.append(points[b])
	var middle := Vector3.ZERO
	for point in points:
		middle += point
	_hull = {planes = planes, edges = edges, middle = middle / maxf(points.size(), 1.0)}
	return _hull


## The pack's texture as a plain PS1-looking material (the one on your back).
static func pack_material() -> StandardMaterial3D:
	if _pack_look == null:
		_pack_look = StandardMaterial3D.new()
		_pack_look.albedo_texture = load(BAG_TEXTURE) as Texture2D if ResourceLoader.exists(BAG_TEXTURE) else null
		_pack_look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_pack_look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_pack_look.roughness = 1.0
	return _pack_look


## The pack in your hand: its material swapped for one that can cut its top
## away (the unzip) and shows its insides darker.
func _build_bag() -> void:
	var mesh := pack_mesh()
	if mesh == null:
		return
	_bag = MeshInstance3D.new()
	_bag.name = "Bag"
	_bag.mesh = mesh
	_bag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bag_box = mesh.get_aabb()
	var shader := preload("res://shaders/backpack_open.gdshader")
	for surface in mesh.get_surface_count():
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo_texture", pack_material().albedo_texture)
		material.set_shader_parameter("albedo_color", Color.WHITE)
		_bag.set_surface_override_material(surface, material)
		_materials.append(material)
	# Centred on its own middle, so placing it places the middle.
	_bag.position = -_bag_box.get_center() * hold.bag_scale
	add_child(_bag)
