class_name MissionPortal
extends Area3D

## The portal Grandma summons: walk into it and you're off to the mission
## it was opened for. A placeholder look (a glowing ring, a swirling disc and
## drifting sparks) until there's a real portal model -- set model_scene.
##
## For now walking in is a plain level change. The seamless see-through
## version is a later roadmap item.
## Rule 1 (co-op): the host spawns it and decides the level change for
## everyone; walking in on a client just asks the host to go.

const COLOR := Color(0.55, 0.3, 1.0)
const RING_RADIUS := 0.9
const SPIN_SPEED := 1.5
const ENTER_SOUND := preload("res://audio/events/map/portal_enter.tres")
const OPEN_SOUND := preload("res://audio/events/map/portal_open.tres")

## The mission this portal leads to.
var mission: MissionData
## A real portal model; empty = the placeholder.
var model_scene: PackedScene

var _visual: Node3D
var _entered := false


## Opens a portal for `mission` at `where`, facing `facing_toward`.
static func open_portal(world: Node, mission_data: MissionData, where: Vector3, facing_toward: Vector3,
		model: PackedScene = null) -> MissionPortal:
	var portal := MissionPortal.new()
	portal.mission = mission_data
	portal.model_scene = model
	world.add_child(portal)
	portal.global_position = where
	var flat_target := Vector3(facing_toward.x, where.y, facing_toward.z)
	if flat_target.distance_to(where) > 0.01:
		portal.look_at(flat_target, Vector3.UP)
	return portal


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RING_RADIUS * 1.8, RING_RADIUS * 2.2, 0.8)
	shape.shape = box
	shape.position = Vector3.UP * (RING_RADIUS + 0.15)
	add_child(shape)
	body_entered.connect(_on_body_entered)

	_visual = Node3D.new()
	_visual.position = Vector3.UP * (RING_RADIUS + 0.15)
	add_child(_visual)
	if model_scene:
		_visual.add_child(model_scene.instantiate())
	else:
		_build_placeholder()
	# Pops open instead of appearing.
	_visual.scale = Vector3.ONE * 0.01
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	SoundPlayer.play_3d(OPEN_SOUND, global_position, get_tree().current_scene)


func _process(delta: float) -> void:
	if model_scene == null and _visual:
		_visual.rotate_object_local(Vector3.FORWARD, SPIN_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	if _entered or not body is PlayerMovement or mission == null:
		return
	_entered = true
	SoundPlayer.play_2d(ENTER_SOUND)
	get_tree().change_scene_to_file.call_deferred(mission.scene)


func _build_placeholder() -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = COLOR
	glow.emission_enabled = true
	glow.emission = COLOR
	glow.emission_energy_multiplier = 2.5
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.08
	torus.outer_radius = RING_RADIUS
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = glow
	ring.rotation.x = PI * 0.5 # stand the ring up, facing along -Z
	_visual.add_child(ring)

	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = Color(COLOR.r * 0.4, COLOR.g * 0.2, COLOR.b * 0.6, 0.75)
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = RING_RADIUS - 0.05
	disc_mesh.bottom_radius = RING_RADIUS - 0.05
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 24
	disc.mesh = disc_mesh
	disc.material_override = disc_material
	disc.rotation.x = PI * 0.5
	_visual.add_child(disc)

	var sparks := GPUParticles3D.new()
	sparks.amount = 40
	sparks.lifetime = 1.2
	sparks.draw_pass_1 = BloodFX.droplet_mesh()
	var spark_material := ParticleProcessMaterial.new()
	spark_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	spark_material.emission_ring_axis = Vector3.FORWARD
	spark_material.emission_ring_radius = RING_RADIUS
	spark_material.emission_ring_inner_radius = RING_RADIUS * 0.8
	spark_material.emission_ring_height = 0.05
	spark_material.direction = Vector3.FORWARD
	spark_material.spread = 30.0
	spark_material.initial_velocity_min = 0.3
	spark_material.initial_velocity_max = 0.9
	spark_material.gravity = Vector3.ZERO
	spark_material.scale_min = 0.5
	spark_material.scale_max = 1.2
	spark_material.color = COLOR.lightened(0.4)
	sparks.process_material = spark_material
	_visual.add_child(sparks)
	sparks.emitting = true
