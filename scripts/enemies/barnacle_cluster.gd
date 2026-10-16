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
@export var count: int = 12
## How far from the middle barnacles and mounds can grow (spread wider as
## the count went up, so a clump covers more ground rather than piling up).
@export var radius: float = 3.0
@export var size_min: float = 0.6
@export var size_max: float = 1.6
## Flat fungal mounds around the barnacles (no collision, look only).
@export var fungus_count: int = 14
@export var fungus_color: Color = Color(0.26, 0.24, 0.12)
## Look-only barnacles filling the clump out (no hitbox, no spawning, no
## thinking): they throb along with the real ones near them, a ripple
## spreading out from each one that's about to spit.
@export var decoy_count: int = 18
@export var decoy_size_min: float = 0.5
@export var decoy_size_max: float = 1.3
## How far a real barnacle's throb carries to the decoys round it (metres).
@export var decoy_reach: float = 3.5
@export var leech_scene: PackedScene = preload("res://scenes/enemy/leech.tscn")
@export var leech_count: int = 3
## Off for now: leeches are switched off game-wide until they're fixed. Turn
## this on to bring back a clump's leech guards.
@export var spawn_leeches: bool = false
## Deepmaws lurking under the floor below the clump, coming up at anyone
## who gets near it (on a wall or ceiling clump: under the floor beneath it).
@export var defender_scene: PackedScene = preload("res://scenes/enemy/deepmaw.tscn")
@export var defender_count: int = 0 # off: Deepmaws guard the worm boss, not the barnacles
## A pack of surface Deepmaws (DeepmawCrawler, the rats' pack behaviour)
## guarding the clump from the floor under it; 0 = none.
@export var guard_pack_scene: PackedScene = preload("res://scenes/enemy/deepmaw_pack.tscn")
@export var guard_count: int = 0 # off for now: the crawlers are shelved (scripts and scenes kept)

const GROUP := "barnacle_clusters"
const BARNACLE_MODEL := preload("res://art/props/PSX Creatures/Models/FBX/barnacle.fbx")
const BARNACLE_TEXTURE := preload("res://art/props/PSX Creatures/Textures/barnacle.png")
## The barnacles' throb (as Barnacle's: swell_time, swell_amount).
const THROB_TIME := 1.2
const THROB_AMOUNT := 0.3

static var _fungus_mesh: SphereMesh
## The decoys' skin, roach nest and spider nest (made once).
static var _decoy_skins := {}
var _fungus_material: StandardMaterial3D
var _decoys: Array[Node3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	_grow.call_deferred() # once the level around it exists


func _grow() -> void:
	var up := global_basis.y.normalized()
	if nest == Nest.RANDOM:
		nest = Nest.SPIDERS if randf() < spider_nest_chance else Nest.ROACHES
	if nest == Nest.SPIDERS:
		fungus_color = spider_fungus_color
		
	var is_server := multiplayer.is_server()
	var pack: SpiderPack = null
	
	if is_server:
		if nest == Nest.SPIDERS:
			pack = SpiderPack.new()
			pack.start_count = 0
			pack.free_when_empty = false # more are coming
			pack.position = global_position # the level's root sits at the origin
			get_tree().current_scene.add_child(pack)
			
		for i in count:
			while FrameBudget.over(): # (spread over frames: no stutter)
				await get_tree().process_frame
			if not is_inside_tree():
				return
			var hit := _surface_near(up, 0.0 if i == 0 else radius)
			if hit.is_empty():
				continue
			var barnacle := barnacle_scene.instantiate() as Barnacle
			if not barnacle:
				continue
			# Biggest first (in the middle), down to the smallest, so every
			# clump has a spread of sizes -- each nudged a little.
			var t := 1.0 - float(i) / maxf(count - 1, 1)
			barnacle.size = clampf(lerpf(size_min, size_max, t) + randf_range(-0.08, 0.08), size_min, size_max)
			barnacle.brood = Barnacle.Brood.SPIDERS if nest == Nest.SPIDERS else Barnacle.Brood.ROACHES
			barnacle.spider_pack = pack
			barnacle.swelling.connect(_on_barnacle_swelling.bind(barnacle))
			add_child(barnacle)
			barnacle.global_transform = Transform3D(_basis_on(hit.normal), hit.position)
			
		_spawn_defenders()
		_spawn_guard_pack()
		
		for i in (leech_count if spawn_leeches else 0):
			while FrameBudget.over():
				await get_tree().process_frame
			if not is_inside_tree():
				return
			var flat := Vector2.from_angle(randf() * TAU) * randf_range(radius, radius * 1.8)
			var leech := leech_scene.instantiate() as Node3D
			if leech:
				add_child(leech)
				leech.global_position = global_position + global_basis * Vector3(flat.x, 0.0, flat.y) + up * 0.4
				
	for i in fungus_count:
		while FrameBudget.over():
			await get_tree().process_frame
		if not is_inside_tree():
			return
		var hit := _surface_near(up, radius * 1.2)
		if not hit.is_empty():
			_add_fungus(hit.position, hit.normal)
			
	for i in decoy_count:
		while FrameBudget.over():
			await get_tree().process_frame
		if not is_inside_tree():
			return
		var hit := _surface_near(up, radius * 1.3)
		if not hit.is_empty():
			_add_decoy(hit.position, hit.normal)


## A look-only barnacle: just the model, in the PS1 look, the nest's skin.
func _add_decoy(at: Vector3, normal: Vector3) -> void:
	var spiders := nest == Nest.SPIDERS
	if not _decoy_skins.has(spiders):
		_decoy_skins[spiders] = PS1Look.material(BARNACLE_TEXTURE, Color(0.72, 0.76, 0.9) if spiders else Color.WHITE, false)
	var decoy := BARNACLE_MODEL.instantiate() as Node3D
	if not decoy:
		return
	add_child(decoy)
	for mesh in decoy.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = _decoy_skins[spiders]
	var size := randf_range(decoy_size_min, decoy_size_max) * 1.4 # as big as the real ones (Barnacle.scale_boost)
	decoy.global_transform = Transform3D(_basis_on(normal), at)
	decoy.scale = Vector3.ONE * size
	decoy.set_meta(&"rest", decoy.scale)
	_decoys.append(decoy)


## A real one's about to spit: the decoys round it throb too, the nearest
## first, a ripple spreading out.
func _on_barnacle_swelling(barnacle: Barnacle) -> void:
	if not is_instance_valid(barnacle):
		return
	var barnacle_pos := barnacle.global_position
	for decoy in _decoys:
		if not is_instance_valid(decoy):
			continue
		var distance := decoy.global_position.distance_to(barnacle_pos)
		if distance < decoy_reach:
			_throb(decoy, distance * 0.12)


## Three swelling pulses, each bigger than the last (taller than wide), then
## a little squash: Barnacle's throb, without the spit.
func _throb(decoy: Node3D, delay: float) -> void:
	if decoy.has_meta(&"throb"):
		var previous := decoy.get_meta(&"throb") as Tween
		if previous and previous.is_valid():
			return # already throbbing
			
	var rest: Vector3 = decoy.get_meta(&"rest")
	var pulse := THROB_TIME / 6.0
	var tween := create_tween()
	tween.tween_interval(delay)
	for i in 3:
		var amount := THROB_AMOUNT * (i + 1) / 3.0
		tween.tween_property(decoy, "scale", rest * Vector3(1.0 + amount * 0.6, 1.0 + amount, 1.0 + amount * 0.6), pulse) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(decoy, "scale", rest, pulse).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(decoy, "scale", rest * Vector3(1.15, 0.8, 1.15), 0.08)
	tween.tween_property(decoy, "scale", rest, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	decoy.set_meta(&"throb", tween)

## A spot on the surface under a random point within `within` of the middle
## (a ray from just off the surface back into it), or {} if there's nothing
## there (off the edge of a wall).
func _surface_near(up: Vector3, within: float) -> Dictionary:
	var flat := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * within
	var along := global_basis * Vector3(flat.x, 0.0, flat.y)
	# Reaching well past the surface either way: the open world's hillsides
	# rise and fall across a clump's width.
	var from := global_position + along + up * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, from - up * 3.5)
	query.collision_mask = 1
	query.exclude = _barnacle_rids()
	return get_world_3d().direct_space_state.intersect_ray(query)


func _barnacle_rids() -> Array[RID]:
	var children := get_children()
	var rids: Array[RID] = []
	for child in children:
		if child is Barnacle:
			rids.append(child.get_rid())
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


func _spawn_defenders() -> void:
	if defender_scene == null or defender_count <= 0:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	query.exclude = _barnacle_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var floor_at: Vector3 = hit.position if not hit.is_empty() else global_position
	for i in defender_count:
		var defender := defender_scene.instantiate() as Node3D
		if defender:
			var around := Vector2.from_angle(randf() * TAU) * randf_range(1.0, radius * 1.5)
			defender.position = floor_at + Vector3(around.x, 0.0, around.y) # the level's root sits at the origin
			get_tree().current_scene.add_child(defender)


func _spawn_guard_pack() -> void:
	if guard_pack_scene == null or guard_count <= 0:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	query.exclude = _barnacle_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var pack := guard_pack_scene.instantiate() as Node3D
	if pack:
		pack.set("count", guard_count)
		pack.position = hit.position if not hit.is_empty() else global_position # the level's root sits at the origin
		get_tree().current_scene.add_child(pack)
