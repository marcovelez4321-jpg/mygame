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
@export var barnacle_nests: int = 16
## The outside nests grow up to this high (where players get to).
@export var nest_height: float = 600.0
@export var cluster_scene: PackedScene = preload("res://scenes/enemy/barnacle_cluster.tscn")
## How far the camera sees (metres): enough for its top from anywhere.
@export var view_distance: float = 16000.0
@export_group("Shell Fog")
## The shell's fog (shaders/skyline.gdshader).
@export var fog_floor: float = 0.0
@export var thin_height: float = 700.0
@export var near_reach: float = 260.0
@export var far_reach: float = 12000.0

const SKYLINE := preload("res://shaders/skyline.gdshader")
## Megastructure lairs (WormDirector picks them up).
const LAIR_GROUP := "megastructure_lairs"

var _camera_check := 0.0


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
