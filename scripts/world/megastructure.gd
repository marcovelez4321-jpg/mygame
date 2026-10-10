class_name Megastructure
extends Node3D

## A walk-up megastructure (docs/WORLD.md, Rule 9): kilometres tall, and you
## can reach it, climb it and go inside. Four versions of itself by
## distance, so it's a spectacle from anywhere and cheap everywhere:
##   Shell (child "Shell"): the outside -- towers, bridges, walls. Always
##   drawn, with the skyline's fog (thick at the ground, thinning with
##   height), so from kilometres off its feet drown in the murk while its
##   upper reaches loom; casts its shadow; its collision always on (you
##   land on it, grapple it). Simple boxes: cheap.
##   Interior (child "Interior"): the insides -- floors, halls, shafts,
##   depths. Only drawn within interior_distance (its collision stays: static
##   boxes cost almost nothing).
##   Decor (child "Decor"): windows, lights, growth, things moving on it --
##   each piece sets its own draw distance.
##   Occluders: every big solid block of the shell (built by StackBuilder,
##   or any OccluderInstance3D you add): what's behind it isn't drawn.
## Its base is a lair for the boss worm (child CollisionShape3D "Lair", in
## no body, so it collides with nothing: WormDirector only reads its size).
## Barnacle nests grow on it (barnacle_nests): half up its outside walls (up
## to nest_height), half inside (within `inside`), found by rays against it.
## Made from TrenchBroom: build the outside and the inside as separate maps
## (megastructure maps are 8 units a metre:
## maps/megastructures/megastructure_map_settings.tres), func_godot them, and
## put the outside's scene under Shell and the inside's under Interior.

@export var interior_distance: float = 600.0
## Its insides (local space): where the inside nests go.
@export var inside := AABB()
@export_group("Nests")
@export var barnacle_nests: int = 20
## The outside nests grow up to this high (where players get to).
@export var nest_height: float = 600.0
@export var cluster_scene: PackedScene = preload("res://scenes/enemy/barnacle_cluster.tscn")
@export_group("Infestation")
## While a player's within infest_range of it, its insides are infested:
## roach swarms, spider hordes and big rat hordes, each wandering its own
## patch of a floor (RoamingGroup, staying put). Gone again once everyone's
## more than infest_range + 150 m away; far-off ones sleep meanwhile.
@export var infest_range: float = 500.0
@export var roach_swarms: int = 3
@export var spider_hordes: int = 2
@export var rat_hordes: int = 2
## Everything in its infestation is this much bigger (bites x size; health
## stays the same) -- a place not built for people breeds things to match.
## Only its own hordes: a Rat Bender's keep their size.
@export var infest_magnify: float = 2.0
## How far the camera sees (metres): enough for its top from anywhere.
@export var view_distance: float = 16000.0
@export_group("Shell Fog")
## The shell's fog (shaders/skyline.gdshader).
@export var fog_floor: float = 0.0
@export var thin_height: float = 700.0
@export var near_reach: float = 260.0
@export var far_reach: float = 12000.0

const SKYLINE := preload("res://shaders/skyline.gdshader")
const ROACH := preload("res://scenes/enemy/roach.tscn")
const SPIDER_PACK := preload("res://scenes/enemy/spider_pack.tscn")
const RAT_NEST := preload("res://scenes/enemy/rat_nest.tscn")
## Megastructure lairs (WormDirector picks them up).
const LAIR_GROUP := "megastructure_lairs"

var _camera_check := 0.0
var _infestation: Array[RoamingGroup] = []


func _ready() -> void:
	var shell := get_node_or_null(^"Shell")
	if shell:
		_skyline_shell(shell)
	var interior := get_node_or_null(^"Interior")
	if interior:
		for node in interior.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			geometry.visibility_range_end = interior_distance
			geometry.visibility_range_end_margin = interior_distance * 0.1
			geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var lair := get_node_or_null(^"Lair")
	if lair:
		lair.add_to_group(LAIR_GROUP)
		lair.set_meta(&"hunger_scale", 2.0) # its home: it gets hungry here twice as fast
	if multiplayer.is_server() and barnacle_nests > 0:
		_grow_nests.call_deferred()


## Barnacle nests on it: rays from outside in at the walls (half), and from
## inside out at the walls and blocks there (half), each nest where one lands.
func _grow_nests() -> void:
	await get_tree().physics_frame # its collision has to be in the world first
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var grown := 0
	for attempt in barnacle_nests * 6:
		if grown >= barnacle_nests:
			return
		var outside := grown % 2 == 0 or inside.size == Vector3.ZERO
		var direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var from: Vector3
		var to: Vector3
		if outside:
			var y := randf_range(8.0, nest_height)
			from = Vector3(0.0, y, 0.0) - direction * 900.0
			to = Vector3(0.0, y, 0.0)
		else:
			from = inside.position + Vector3(randf(), randf(), randf()) * inside.size
			to = from + direction * 120.0
		var query := PhysicsRayQueryParameters3D.create(to_global(from), to_global(to))
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not LevelGeometry.is_static(hit.collider):
			continue
		var cluster := cluster_scene.instantiate() as Node3D
		add_child(cluster)
		var normal := hit.normal as Vector3
		var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var side := normal.cross(reference).normalized()
		cluster.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), hit.position)
		grown += 1


func _process(delta: float) -> void:
	_camera_check -= delta
	if _camera_check > 0.0:
		return
	_camera_check = 1.0
	var camera := get_viewport().get_camera_3d()
	if camera and camera.far < view_distance:
		camera.far = view_distance
	if multiplayer.is_server() and inside.size != Vector3.ZERO:
		_update_infestation()


## Infested while someone's near; cleared once everyone's well away.
func _update_infestation() -> void:
	var nearest := INF
	var middle := to_global(inside.get_center())
	for node in get_tree().get_nodes_in_group("player"):
		var at := (node as Node3D).global_position
		nearest = minf(nearest, Vector2(at.x - middle.x, at.z - middle.z).length())
	var live: Array[RoamingGroup] = []
	for group in _infestation:
		if is_instance_valid(group):
			live.append(group)
	_infestation = live
	if nearest < infest_range and _infestation.is_empty():
		_infest()
	elif nearest > infest_range + 150.0 and not _infestation.is_empty():
		for group in _infestation:
			group.disband()
		_infestation.clear()


func _infest() -> void:
	for i in roach_swarms:
		var group := _floor_group("Roaches")
		if group:
			for r in randi_range(6, 12):
				var roach := ROACH.instantiate() as FlyingRoach
				roach.size = infest_magnify
				_member(group, roach, r, 1.5 * infest_magnify)
	for i in spider_hordes:
		var group := _floor_group("Spiders")
		if group:
			var pack := SPIDER_PACK.instantiate() as SpiderPack
			pack.start_count = randi_range(12, 20)
			pack.spider_scale = infest_magnify
			_member(group, pack, 0)
	for i in rat_hordes:
		var group := _floor_group("Rats")
		if group:
			var nest := RAT_NEST.instantiate() as RatNest
			nest.rat_count = randi_range(15, 22) # x2 (leaderless): 30-44
			nest.bodyguard_count = randi_range(2, 3)
			var swarm := nest.get_node(^"RatSwarm") as RatSwarm
			swarm.rat_scale = infest_magnify
			swarm.rat_damage_multiplier = infest_magnify
			swarm.separation_distance *= infest_magnify
			_member(group, nest, 0)


## A group staying on a patch of floor somewhere inside, or null if no
## floor turned up.
func _floor_group(what: String) -> RoamingGroup:
	var spot := _inside_spot()
	if not spot.is_finite():
		return null
	var group := RoamingGroup.new()
	group.name = "Infestation_" + what
	group.use_navmesh = false
	group.anchor = spot
	group.anchor_radius = 45.0
	group.drift_speed = 0.8
	add_child(group)
	group.global_position = spot
	_infestation.append(group)
	return group


func _member(group: RoamingGroup, member: Node, index: int, lift: float = 0.0) -> void:
	var around := Vector2.from_angle(index * 2.4 + randf()) * (0.0 if index == 0 else randf_range(1.5, 4.0))
	(member as Node3D).position = Vector3(around.x, lift, around.y)
	group.add_child(member)


## A spot on a floor inside (a random point in `inside`, straight down onto
## whatever's under it), or a non-finite vector if none turned up.
func _inside_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	for attempt in 12:
		var from := to_global(inside.position + Vector3(randf(), randf(), randf()) * inside.size)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and LevelGeometry.is_static(hit.collider) and (hit.normal as Vector3).y > 0.7:
			return hit.position
	return Vector3.INF


## The shell's materials made skyline (texture and colour kept), unless
## they already are.
func _skyline_shell(shell: Node) -> void:
	var converted := {}
	for node in shell.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.get_active_material(surface)
			if original is ShaderMaterial and (original as ShaderMaterial).shader == SKYLINE:
				continue
			if not converted.has(original):
				converted[original] = _skyline_material(original as BaseMaterial3D)
			mesh_instance.set_surface_override_material(surface, converted[original])


func _skyline_material(base: BaseMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SKYLINE
	if base:
		if base.albedo_texture:
			material.set_shader_parameter("albedo_texture", base.albedo_texture)
		material.set_shader_parameter("albedo_color", base.albedo_color)
	material.set_shader_parameter("fog_floor", fog_floor)
	material.set_shader_parameter("thin_height", thin_height)
	material.set_shader_parameter("near_reach", near_reach)
	material.set_shader_parameter("far_reach", far_reach)
	return material
