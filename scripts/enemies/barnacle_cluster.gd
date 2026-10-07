class_name BarnacleCluster
extends Node3D

## A little fungal growth of barnacles on a floor, wall or ceiling. Place it
## touching the surface with its up (green Y arrow) pointing out of it: up for
## a floor, sideways out of a wall, down from a ceiling. When the level starts
## it grows `count` barnacles (Barnacle) scattered within radius of itself
## across that surface, their sizes spread from size_min to size_max (the
## biggest in the middle, a little jitter on each), among fungus_count flat
## fungal mounds -- and leech_count leeches (Leech) set around it as guards
## (on a wall or ceiling clump they drop to the floor below and guard there).
##
## Each clump is a roach nest or a spider nest (nest; RANDOM rolls it, a
## spider nest spider_nest_chance of the time): a spider nest's barnacles
## are paler, its fungus webby grey, and they spit spiders into one shared
## SpiderPack, so a clump's spiders swarm together.
##
## Rule 1 (co-op): the host grows the barnacles; the mounds are just the look.

enum Nest { RANDOM, ROACHES, SPIDERS }

@export var barnacle_scene: PackedScene = preload("res://scenes/enemy/barnacle.tscn")
## Roach nest, spider nest, or roll it (spider_nest_chance of a spider nest).
@export var nest: Nest = Nest.RANDOM
@export_range(0.0, 1.0, 0.05) var spider_nest_chance: float = 0.4
@export var spider_fungus_color: Color = Color(0.5, 0.5, 0.47)
@export var count: int = 6
## How far from the middle barnacles and mounds can grow.
@export var radius: float = 1.8
@export var size_min: float = 0.6
@export var size_max: float = 1.6
## Flat fungal mounds around the barnacles (no collision, look only).
@export var fungus_count: int = 7
@export var fungus_color: Color = Color(0.26, 0.24, 0.12)
@export var leech_scene: PackedScene = preload("res://scenes/enemy/leech.tscn")
@export var leech_count: int = 3

const GROUP := "barnacle_clusters"

static var _fungus_mesh: SphereMesh
var _fungus_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	_grow.call_deferred() # once the level around it exists


func _grow() -> void:
	var up := global_basis.y.normalized()
	if nest == Nest.RANDOM:
		nest = Nest.SPIDERS if randf() < spider_nest_chance else Nest.ROACHES
	if nest == Nest.SPIDERS:
		fungus_color = spider_fungus_color
	var pack: SpiderPack = null
	if multiplayer.is_server():
		if nest == Nest.SPIDERS:
			pack = SpiderPack.new()
			pack.start_count = 0
			pack.free_when_empty = false # more are coming
			pack.position = global_position # the level's root sits at the origin
			get_tree().current_scene.add_child(pack)
		for i in count:
			var hit := _surface_near(up, 0.0 if i == 0 else radius)
			if hit.is_empty():
				continue
			var barnacle := barnacle_scene.instantiate() as Barnacle
			# Biggest first (in the middle), down to the smallest, so every
			# clump has a spread of sizes -- each nudged a little.
			var t := 1.0 - float(i) / maxf(count - 1, 1)
			barnacle.size = clampf(lerpf(size_min, size_max, t) + randf_range(-0.08, 0.08), size_min, size_max)
			barnacle.brood = Barnacle.Brood.SPIDERS if nest == Nest.SPIDERS else Barnacle.Brood.ROACHES
			barnacle.spider_pack = pack
			add_child(barnacle)
			barnacle.global_transform = Transform3D(_basis_on(hit.normal), hit.position)
		for i in leech_count:
			var flat := Vector2.from_angle(randf() * TAU) * randf_range(radius, radius * 1.8)
			var leech := leech_scene.instantiate() as Node3D
			add_child(leech)
			leech.global_position = global_position + global_basis * Vector3(flat.x, 0.0, flat.y) + up * 0.4
	for i in fungus_count:
		var hit := _surface_near(up, radius * 1.2)
		if not hit.is_empty():
			_add_fungus(hit.position, hit.normal)


## A spot on the surface under a random point within `within` of the middle
## (a ray from just off the surface back into it), or {} if there's nothing
## there (off the edge of a wall).
func _surface_near(up: Vector3, within: float) -> Dictionary:
	var flat := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * within
	var along := global_basis * Vector3(flat.x, 0.0, flat.y)
	var from := global_position + along + up * 0.6
	var query := PhysicsRayQueryParameters3D.create(from, from - up * 1.6)
	query.collision_mask = 1
	query.exclude = _barnacle_rids()
	return get_world_3d().direct_space_state.intersect_ray(query)


func _barnacle_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child in get_children():
		if child is Barnacle:
			rids.append((child as Barnacle).get_rid())
	return rids


## Standing out of a surface with this normal, turned a random way around it.
func _basis_on(normal: Vector3) -> Basis:
	var reference := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := normal.cross(reference).normalized()
	var standing := Basis(side, normal, side.cross(normal))
	return standing.rotated(normal, randf() * TAU)


## A flattened lump of fungus sunk into the surface.
func _add_fungus(at: Vector3, normal: Vector3) -> void:
	if _fungus_mesh == null:
		_fungus_mesh = SphereMesh.new() # one shared mesh for every mound
		_fungus_mesh.radial_segments = 8 # PS1-chunky
		_fungus_mesh.rings = 4
	if _fungus_material == null:
		_fungus_material = StandardMaterial3D.new() # this clump's colour
		_fungus_material.albedo_color = fungus_color
		_fungus_material.roughness = 1.0
	var mound := MeshInstance3D.new()
	mound.mesh = _fungus_mesh
	mound.material_override = _fungus_material
	mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mound)
	var width := randf_range(0.35, 0.9)
	var mound_basis := _basis_on(normal) * Basis.from_scale(Vector3(width, width * randf_range(0.25, 0.45), width * randf_range(0.7, 1.0)))
	mound.global_transform = Transform3D(mound_basis, at)
