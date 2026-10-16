class_name CarryItem
extends RigidBody3D

## A thing you can have in your right hand (PlayerHand), lying in the world:
## a meat chunk dropped by a big enemy, a Flesh Tree pod, or something taken
## out of the backpack (double-clicked, then dropped with G). Grapple it and
## it flies into your hand (the user's, 2026-10-15). Outlined like any pickup.
##   MEAT rots once it's ROT_TIME old, wherever it is (the backpack and your
##   hand too): green-grey, with flies. Fresh meat on, over or within
##   COOK_REACH of a fire (FireSource) cooks in COOK_TIME; stepping away
##   keeps what it's cooked so far. Rot can't be cooked.
## Rule 1 (co-op): only the host's runs (ages, cooks) -- the clients see a
## puppet (NetEntities: net_spawn_args()/net_restore(), net_state()/
## net_apply() for rotting or cooking). Its age, not a clock time, so it means
## the same on every machine.
## Cheap: only fresh meat thinks, and rarely -- it looks for a fire once
## every COOK_EVERY and ages in AGE_EVERY steps (the user's: every couple of
## minutes is plenty); the rest never runs. Its look is made once per change,
## from materials shared by every chunk.

const ROT_TIME := 600.0
const COOK_TIME := 25.0
const COOK_REACH := 1.0
## Seconds between looking for a fire, and between aging steps.
const COOK_EVERY := 1.0
const AGE_EVERY := 120.0
## Meat's density (water's): a chunk's size from its weight.
const MEAT_DENSITY := 1000.0
## How much bigger than life a chunk is in the world (the user's: 3x).
const MEAT_SIZE := 3.0
## Every other thing out in the world, how much bigger than life (the user's:
## twice, so they're easy to spot -- guns stay real size).
const ITEM_SIZE := 2.0
## Seen (and its flies) out to this far.
const SEEN_RANGE := 60.0
const FLIES_RANGE := 15.0

## The user's models (New assets/): Flesh2 is raw, Flesh cooked.
const RAW_MODEL := "res://New assets/Flesh2.fbx"
const RAW_TEXTURE := "res://New assets/Flesh_2.png"
const COOKED_MODEL := "res://New assets/Flesh.fbx"
const COOKED_TEXTURE := "res://New assets/Flesh_1.png"
## Rotten: the raw chunk tinted sickly green-grey (the user's).
const ROT_TINT := Color(0.55, 0.62, 0.42)

## What it is: a backpack kind (Backpack.Kind, MEAT and COOKED_MEAT
## included), or a pod (POD).
const POD := 100

var kind: int = Backpack.Kind.NONE
## How many of the kind (ammo: rounds; most things: 1).
var amount := 1
## A gun's own data (kind GUN).
var weapon: WeaponData
## Meat: its weight (kg: 1 small enemy, 2 human, 4 boss), whether it came off
## a boss, how old it is (s) and how long it's been cooking (s).
var meat_weight := 1.0
var boss := false
var age := 0.0
var cooked_for := 0.0
## A pod: its mutation (Virus).
var mutation: StringName

var _model: Node3D
var _shape: CollisionShape3D
var _flies: GPUParticles3D
## Whoever just dropped it: ignored till they've stepped off it.
var ignore: Node
## Walk into it and it's in your bag (the user's: like the old pickups).
const PICKUP_RADIUS := 1.0
var _shown := -1
var _cook_left := 0.0
var _age_left := AGE_EVERY

static var _scenes := {}
## [raw, rotten, cooked] meat materials, shared by every chunk.
static var _meat_materials: Array[StandardMaterial3D] = []
static var _fly_process: ParticleProcessMaterial
static var _fly_dot: QuadMesh


## A fresh meat chunk where an enemy died (the host's).
static func spawn_meat(where: Node, at: Vector3, weight: float, from_boss: bool) -> CarryItem:
	var item := CarryItem.new()
	item.kind = Backpack.Kind.MEAT
	item.meat_weight = weight
	item.boss = from_boss
	return item._place(where, at)


## Something out in the world from its data (dropped from the hand).
static func spawn(where: Node, at: Vector3, data: Dictionary) -> CarryItem:
	var item := CarryItem.new()
	item.from_data(data)
	return item._place(where, at)


func _place(where: Node, at: Vector3) -> CarryItem:
	var level := where.get_tree().current_scene if where.is_inside_tree() else null
	(level if level else where).add_child(self)
	global_position = _above_ground(at)
	return self


## Never made inside the ground (the user's: chunks clipped through the
## terrain): lifted onto it if t is below it.
func _above_ground(at: Vector3) -> Vector3:
	if kind == POD:
		return at # (hangs off a limb: never moved)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return at
	var floor_y := (hit.position as Vector3).y + world_size() * 0.5
	return Vector3(at.x, maxf(at.y, floor_y), at.z)


## What it is, as plain data (the hand, the backpack, the network).
func to_data() -> Dictionary:
	return {kind = kind, amount = amount, weapon = weapon.resource_path if weapon else "", meat_weight = meat_weight,
			boss = boss, age = age, cooked_for = cooked_for, mutation = mutation}


func from_data(data: Dictionary) -> void:
	kind = data.get("kind", Backpack.Kind.NONE)
	amount = data.get("amount", 1)
	var path: String = data.get("weapon", "")
	weapon = load(path) as WeaponData if path != "" and ResourceLoader.exists(path) else null
	meat_weight = data.get("meat_weight", 1.0)
	boss = data.get("boss", false)
	age = data.get("age", 0.0)
	cooked_for = data.get("cooked_for", 0.0)
	mutation = data.get("mutation", &"")


# ---- Co-op (NetEntities) --------------------------------------------------------------

func net_spawn_args() -> Dictionary:
	return to_data()


func net_restore(data: Dictionary) -> void:
	from_data(data)


## Sent with each update: what it is now (it can rot or cook).
func net_state() -> int:
	return kind * 2 + (1 if is_rotten() else 0)


func net_apply(state: int) -> void:
	kind = state >> 1
	age = ROT_TIME if state & 1 else 0.0
	_refresh_look()


# ---- Life -------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(InteractHighlight.GROUP)
	add_to_group(NetEntities.GROUP)
	mass = clampf(weight(), 0.05, 15.0)
	continuous_cd = kind == Backpack.Kind.MEAT or kind == Backpack.Kind.COOKED_MEAT
	can_sleep = true
	_cook_left = randf() * COOK_EVERY # a pile of them don't all look at once
	_refresh_look()
	_make_pickup_zone()
	# Only fresh meat on the host has anything to do (age, cook).
	set_physics_process(kind == Backpack.Kind.MEAT and not NetEntities.is_puppet(self) \
			and (not Network.is_online() or multiplayer.is_server()))


static func is_rotten_data(data: Dictionary) -> bool:
	return data.get("kind", -1) == Backpack.Kind.MEAT and float(data.get("age", 0.0)) >= ROT_TIME


func is_rotten() -> bool:
	return kind == Backpack.Kind.MEAT and age >= ROT_TIME


## Its weight (kg): meat by its enemy, a gun its own, the rest the backpack's.
func weight() -> float:
	match kind:
		Backpack.Kind.MEAT, Backpack.Kind.COOKED_MEAT:
			return meat_weight
		Backpack.Kind.GUN:
			return weapon.carry_weight if weapon else 3.5
		POD:
			return 1.0
	return float(Backpack.WEIGHTS.get(kind, 0.1)) * amount


func _physics_process(delta: float) -> void:
	_cook_left -= delta
	_age_left -= delta
	var changed := false
	if _cook_left <= 0.0:
		_cook_left += COOK_EVERY
		changed = cook(self, COOK_EVERY, global_position)
	if _age_left <= 0.0:
		_age_left += AGE_EVERY
		changed = grow_old(self, AGE_EVERY) or changed
	if changed:
		_refresh_look()
	if kind != Backpack.Kind.MEAT or is_rotten():
		set_physics_process(false) # cooked or rotten: nothing more happens to it


## Fresh meat `step` seconds older (`target`: a CarryItem, or a chunk's data
## in a hand or a pack). True if that rotted it.
static func grow_old(target: Variant, step: float) -> bool:
	# (Indexing works the same on the node's properties and the data's keys.)
	if int(target["kind"]) != Backpack.Kind.MEAT:
		return false
	var was_rotten: bool = float(target["age"]) >= ROT_TIME
	target["age"] = float(target["age"]) + step
	return not was_rotten and float(target["age"]) >= ROT_TIME


## Fresh meat cooked `step` seconds more if a fire's within reach of `at`.
## True if that finished it.
static func cook(target: Variant, step: float, at: Vector3) -> bool:
	if int(target["kind"]) != Backpack.Kind.MEAT or float(target["age"]) >= ROT_TIME:
		return false
	if not FireSource.near_point(at, COOK_REACH):
		return false
	target["cooked_for"] = float(target["cooked_for"]) + step
	if float(target["cooked_for"]) >= COOK_TIME:
		target["kind"] = Backpack.Kind.COOKED_MEAT
		return true
	return false


## Walking into it puts it in your backpack (the host's; pods are grapple
## only). A thing just dropped waits till its dropper steps off it.
func _make_pickup_zone() -> void:
	if kind == POD or NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	zone.add_child(shape)
	add_child(zone)
	zone.body_entered.connect(_on_walked_into)
	zone.body_exited.connect(func(body: Node3D) -> void:
		if body == ignore:
			ignore = null)


func _on_walked_into(body: Node3D) -> void:
	var player := body as PlayerMovement
	if player == null or body == ignore or player.is_dead() or has_meta(&"on_tree") or has_meta(&"fetched"):
		return
	var item := to_data()
	if not player.hand.store(item):
		return # no room: it stays
	player.hand.tell_owner_stored(item)
	if player.is_multiplayer_authority():
		MapIO.show_pickup(get_tree(), "+ %s" % _pickup_name())
	queue_free()


func _pickup_name() -> String:
	if kind == POD:
		return "Pod"
	return (Backpack.Kind.keys()[kind + 1] as String).capitalize()

## A pod left on the Flesh Tree when another was taken: it withers and goes.
func shrivel() -> void:
	remove_from_group(InteractHighlight.GROUP)
	collision_layer = 0
	var fade := create_tween()
	if _model:
		fade.tween_property(_model, "scale", _model.scale * 0.05, 1.5).set_ease(Tween.EASE_IN)
	fade.tween_callback(queue_free)


## Outlined (InteractHighlight). (A pod used to say what it holds here; now
## you read it once it's in your hand -- the user's.)
func set_highlighted(_on: bool) -> void:
	pass


# ---- Look -------------------------------------------------------------------------------

## Remade only when what it looks like changed: raw, rotten, cooked, other.
func _refresh_look() -> void:
	var look := kind * 2 + (1 if is_rotten() else 0)
	if look == _shown:
		return
	_shown = look
	if _model:
		_model.queue_free()
	_model = model_for(to_data(), _player_grenade())
	if _model == null:
		_model = _lump()
	add_child(_model)
	var box := BackpackView._bounds(_model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := world_size() / maxf(longest, 0.0001)
	_model.scale *= fit
	_model.position = -box.get_center() * fit
	for node in _model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.visibility_range_end = SEEN_RANGE
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
	(_shape.shape as BoxShape3D).size = (box.size * fit).max(Vector3.ONE * 0.03)
	_set_flies(is_rotten())


## Its longest side in the world (m): meat from its weight, a pod 1 m (the
## user's), the rest the backpack's real sizes.
func world_size() -> float:
	return size_of(to_data())


## The same, for a thing's data (the hand shows it this size, up to 30 cm).
static func size_of(data: Dictionary) -> float:
	var item_kind: int = data.get("kind", Backpack.Kind.NONE)
	match item_kind:
		Backpack.Kind.MEAT, Backpack.Kind.COOKED_MEAT:
			# A lump's longest side, three times life size (the user's: easy to see).
			return pow(float(data.get("meat_weight", 1.0)) / MEAT_DENSITY, 1.0 / 3.0) * 1.6 * MEAT_SIZE
		POD:
			return 1.0
		Backpack.Kind.GUN:
			var path: String = data.get("weapon", "")
			var gun := load(path) as WeaponData if path != "" and ResourceLoader.exists(path) else null
			return gun.backpack_length if gun and gun.backpack_length > 0.0 else WeaponPickup.LONG_GUN
	return float(BackpackView.REAL_SIZE.get(item_kind, 0.12)) * ITEM_SIZE


func _player_grenade() -> WeaponData:
	if kind != Backpack.Kind.GRENADES or not is_inside_tree():
		return null
	var player := PlayerMovement.local_player(get_tree())
	return player.weapons.grenade_weapon() if player else null


## A fresh copy of what `data` looks like (the hand's view uses it too).
static func model_for(data: Dictionary, grenade: WeaponData = null) -> Node3D:
	var item_kind: int = data.get("kind", Backpack.Kind.NONE)
	match item_kind:
		Backpack.Kind.MEAT:
			return meat_model(false, is_rotten_data(data))
		Backpack.Kind.COOKED_MEAT:
			return meat_model(true, false)
		POD:
			return FleshTree.pod_model(data.get("mutation", &""))
	var path: String = data.get("weapon", "")
	var gun := load(path) as WeaponData if path != "" and ResourceLoader.exists(path) else null
	return BackpackView.model_of(item_kind, gun, grenade)


## The user's flesh chunk: raw (rotten: green-grey) or cooked, textured with
## a shared material.
static func meat_model(cooked: bool, rotten: bool) -> Node3D:
	var scene := _scene(COOKED_MODEL if cooked else RAW_MODEL)
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var material := _meat_material(2 if cooked else (1 if rotten else 0))
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh:
			for surface in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, material)
	return BackpackView._wrapped(model)


static func _meat_material(which: int) -> StandardMaterial3D:
	if _meat_materials.is_empty():
		for i in 3:
			var material := StandardMaterial3D.new()
			var texture_path := COOKED_TEXTURE if i == 2 else RAW_TEXTURE
			material.albedo_texture = load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			material.roughness = 0.6
			if i == 1:
				material.albedo_color = ROT_TINT
			_meat_materials.append(material)
	return _meat_materials[which]


## A red lump, if a model's missing.
func _lump() -> Node3D:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.8
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	mesh.material_override = _meat_material(0)
	holder.add_child(mesh)
	return holder


## A few small flies buzzing round it (rotten meat), only seen up close.
func _set_flies(on: bool) -> void:
	if not on:
		if _flies:
			_flies.queue_free()
			_flies = null
		return
	if _flies:
		return
	if _fly_process == null:
		_fly_process = ParticleProcessMaterial.new()
		_fly_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_fly_process.emission_sphere_radius = 0.25
		_fly_process.gravity = Vector3.ZERO
		_fly_process.initial_velocity_min = 0.3
		_fly_process.initial_velocity_max = 0.8
		_fly_process.direction = Vector3.UP
		_fly_process.spread = 180.0
		_fly_process.orbit_velocity_min = 0.6
		_fly_process.orbit_velocity_max = 1.2
		_fly_process.turbulence_enabled = true
		_fly_process.turbulence_noise_strength = 2.0
		_fly_dot = QuadMesh.new()
		_fly_dot.size = Vector2(0.02, 0.02)
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.03, 0.03, 0.03)
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_fly_dot.material = black
	_flies = GPUParticles3D.new()
	_flies.amount = 6
	_flies.lifetime = 1.6
	_flies.local_coords = true
	_flies.process_material = _fly_process
	_flies.draw_pass_1 = _fly_dot
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flies.visibility_range_end = FLIES_RANGE
	_flies.position = Vector3.UP * 0.15
	add_child(_flies)


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]
