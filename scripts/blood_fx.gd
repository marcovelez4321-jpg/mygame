class_name BloodFX
extends RefCounted

## Shared blood visual effects: a particle spray off a hit body, a splatter
## decal on any wall caught behind that hit, and a pool that fades in on the
## ground once a ragdoll settles. No texture assets needed -- the splat
## shape is generated once in code the first time it's needed and reused for
## every spray/pool/splatter after that (Rule 2: regenerating it per-instance
## would be pure wasted work for a shape that's identical every time).
##
## Called from weapon_controller.gd (impact spray + wall splatter, right when
## a shot lands) and enemy_ragdoll.gd (ground pool, once the corpse settles).

const SPLAT_TEXTURE_SIZE := 128
const BLOOD_COLOR := Color(0.35, 0.02, 0.02)
## How often spawn_artery_spurt() re-checks where the spray is currently
## landing, in seconds -- frequent enough to paint a believable pool as the
## body thrashes and the neck bone swings around, not one static splat.
const ARTERY_POOL_INTERVAL := 0.2
## How far that landing check reaches (floor first, then a nearby wall) from
## the bone's current position.
const ARTERY_POOL_REACH := 3.0

static var _splat_texture: ImageTexture
static var _bullet_hole_texture: ImageTexture
static var _impact_mesh: BoxMesh


## A short, one-shot particle burst at a hit point, kicked out along the
## surface normal it hit. Removes itself once it finishes.
static func spawn_impact(world: Node, position: Vector3, normal: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.draw_pass_1 = _get_impact_mesh()

	var mat := ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 35.0
	mat.initial_velocity_min = 2.125 # 2.5 - 15%
	mat.initial_velocity_max = 5.1   # 6.0 - 15%
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.scale_min = 0.25
	mat.scale_max = 0.6
	mat.color = BLOOD_COLOR
	particles.process_material = mat

	world.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## A sustained, pulsing spray -- an artery hit, not a normal impact.
## Different from spawn_impact() in the way that actually matters here:
## parented directly to `bone` (the neck's PhysicalBone3D) instead of the
## level root at a fixed world position, so the spray keeps coming from the
## right spot and moves/rotates with the body as it ragdolls and falls,
## rather than hanging in empty air where the neck used to be. Stops
## emitting after `duration`, then waits out its particles' own lifetime
## before freeing so the last burst doesn't get cut off mid-flight.
## `exclude` is the owning ragdoll's own list of bone RIDs (see
## weapon_controller.gd's _spawn_artery_spurt(), which builds it from all of
## that Enemy's own PhysicalBone3D children) -- fed into the landing-pool
## raycast below so the spray can paint another nearby corpse or a wall/floor,
## but never the very body it's spraying out of.
static func spawn_artery_spurt(bone: Node3D, duration: float = 7.0, exclude: Array[RID] = []) -> void:
	var particles := GPUParticles3D.new()
	# More, smaller droplets read as a finer, denser mist/stream instead of a
	# handful of chunky flecks.
	particles.amount = 45
	# Longer-lived particles travel further along their arc before vanishing
	# -- combined with the velocity below, that's what makes the stream read
	# as long, not just fast.
	particles.lifetime = 1.6
	particles.one_shot = false
	particles.explosiveness = 0.3
	particles.draw_pass_1 = _get_impact_mesh()

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 25.0
	mat.initial_velocity_min = 4.5
	mat.initial_velocity_max = 8.5
	# Stronger than real gravity on purpose -- pulls the stream down into a
	# more pronounced curve within its flight time instead of a flatter,
	# more ballistic-looking spray.
	mat.gravity = Vector3(0.0, -14.0, 0.0)
	mat.scale_min = 0.3
	mat.scale_max = 0.65
	mat.color = BLOOD_COLOR
	particles.process_material = mat

	bone.add_child(particles)
	particles.emitting = true

	var tree := bone.get_tree()
	if tree == null:
		return
	tree.create_timer(duration).timeout.connect(func() -> void:
		if not is_instance_valid(particles):
			return
		particles.emitting = false
		tree.create_timer(particles.lifetime).timeout.connect(func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
		)
	)

	_pool_landing_spot(bone, tree, duration, exclude)


## Approximates where the spray is currently landing and leaves blood there
## as it goes -- not a true per-particle physics trace (GPU particles don't
## expose that cheaply), just a periodic raycast from the bone's current
## position: straight down for a floor, or outward for a nearby wall if
## there's no floor in reach. Re-checks every ARTERY_POOL_INTERVAL for the
## spurt's whole duration, so as the body thrashes and the neck bone swings
## around, the blood on the ground/wall spreads to follow it instead of being
## one static splat.
##
## Mask includes EnemyRagdoll.WORLD_MASK (world geometry AND the ragdoll
## layer, not just world) so the spray CAN land on another nearby corpse, not
## only floors/walls -- `exclude` is what stops it from ever hitting the very
## body it's spraying out of, which world-only masking used to do as an (in
## hindsight, overly broad) side effect.
static func _pool_landing_spot(bone: Node3D, tree: SceneTree, time_left: float, exclude: Array[RID]) -> void:
	if not is_instance_valid(bone) or time_left <= 0.0:
		return

	var world := bone.get_tree().current_scene
	var space := bone.get_world_3d().direct_space_state
	var origin := bone.global_position

	var down_query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * ARTERY_POOL_REACH)
	down_query.collision_mask = EnemyRagdoll.WORLD_MASK
	down_query.exclude = exclude
	var down_result := space.intersect_ray(down_query)
	if not down_result.is_empty():
		spawn_splatter(world, down_result.position, Vector3.UP, 0.5)
	else:
		# No floor in reach (e.g. hanging over an edge) -- try outward for a wall.
		var outward := bone.global_transform.basis.z
		var wall_query := PhysicsRayQueryParameters3D.create(origin, origin + outward * ARTERY_POOL_REACH)
		wall_query.collision_mask = EnemyRagdoll.WORLD_MASK
		wall_query.exclude = exclude
		var wall_result := space.intersect_ray(wall_query)
		if not wall_result.is_empty():
			spawn_splatter(world, wall_result.position, wall_result.normal, 0.5)

	tree.create_timer(ARTERY_POOL_INTERVAL).timeout.connect(func() -> void:
		_pool_landing_spot(bone, tree, time_left - ARTERY_POOL_INTERVAL, exclude)
	)


## A blood decal stuck to whatever surface is at `position`, facing away
## along `normal` -- used for both wall splatter (a shot punching through to
## a wall behind the target) and, from enemy_ragdoll.gd, the ground pool
## (normal = Vector3.UP). Fades in rather than popping, and both the size and
## the facing get a little randomness so repeated hits don't look identical.
static func spawn_splatter(world: Node, position: Vector3, normal: Vector3, base_size: float = 1.0) -> void:
	_place_decal(world, _get_splat_texture(), position, normal, base_size, 0.4)


## A dark scorch/hole decal for a shot that hit plain world geometry (no
## Health on the collider) instead of flesh -- so missing/wall shots leave a
## mark too, not just kills. Same placement logic as spawn_splatter(), just a
## smaller, darker texture and a snappier fade-in (a bullet hole reads
## instantly; blood spatter reading as it "arrives" a beat later is the part
## that felt right for that one, not this).
static func spawn_bullet_hole(world: Node, position: Vector3, normal: Vector3, base_size: float = 0.25) -> void:
	_place_decal(world, _get_bullet_hole_texture(), position, normal, base_size, 0.1)


## Shared decal placement: builds a basis whose Y axis points INTO the
## surface (-normal) so the decal sticks to it regardless of whether that
## surface is a floor, wall, or ceiling (a Decal projects along its own
## local -Y), with some randomness in size/orientation so repeated hits don't
## look identical, then fades it in over `fade_time`.
static func _place_decal(world: Node, texture: Texture2D, position: Vector3, normal: Vector3, base_size: float, fade_time: float) -> void:
	var decal := Decal.new()
	decal.texture_albedo = texture
	var size := base_size * randf_range(0.8, 1.3)
	decal.size = Vector3(size, size * 0.4, size)
	decal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0

	var into_surface := -normal
	var side := into_surface.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = into_surface.cross(Vector3.RIGHT)
	side = side.normalized()
	var forward := side.cross(into_surface).normalized()
	decal.global_transform = Transform3D(Basis(side, into_surface, forward), position)
	decal.rotate_object_local(Vector3.UP, randf() * TAU)

	world.add_child(decal)
	var tween := decal.create_tween()
	tween.tween_property(decal, "modulate:a", 1.0, fade_time)


static func _get_impact_mesh() -> BoxMesh:
	if _impact_mesh == null:
		_impact_mesh = BoxMesh.new()
		_impact_mesh.size = Vector3.ONE * 0.05
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BLOOD_COLOR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_impact_mesh.material = mat
	return _impact_mesh


static func _get_splat_texture() -> ImageTexture:
	if _splat_texture == null:
		_splat_texture = _generate_splat_texture()
	return _splat_texture


## Public on purpose (unlike the underscore-prefixed getters here) -- hud.gd
## calls this directly for the screen blood droplets.
##
## Just reuses the plain circular splat texture. There WAS a separate,
## fancier irregular-blob version here (per-pixel angle()/sin() calls over
## the whole 128x128 image), but generating it the first time it was needed
## -- mid-gameplay, right as a kill landed -- caused a real, reported hitch.
## Simple and instant beats fancy and freezes.
static func get_screen_splat_texture() -> ImageTexture:
	return _get_splat_texture()


static func _get_bullet_hole_texture() -> ImageTexture:
	if _bullet_hole_texture == null:
		_bullet_hole_texture = _generate_bullet_hole_texture()
	return _bullet_hole_texture


## A dark core with a soft grey scorch ring around it -- reads as a punched-
## in hole with charring, not just a flat dot. Generated once and cached.
static func _generate_bullet_hole_texture() -> ImageTexture:
	var size := SPLAT_TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5

	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center) / (size * 0.5)
			var hole := clampf(1.0 - d / 0.35, 0.0, 1.0) # small solid dark core
			var scorch := clampf(1.0 - d, 0.0, 1.0) * 0.5 # wider, fainter grey char
			var alpha := maxf(hole, scorch)
			var shade := lerpf(0.35, 0.05, hole) # core darker than the scorch ring
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))

	return ImageTexture.create_from_image(image)


## A handful of overlapping SOFT-EDGED CIRCULAR blobs, offset randomly around
## a center, so the splat reads as an organic splash instead of one perfect
## circle -- the original shape, used for every 3D world decal (wall
## splatter, ground pools) where a soft, slightly-rounded splat reads right.
## Generated once and cached (see _get_splat_texture()).
static func _generate_splat_texture() -> ImageTexture:
	var size := SPLAT_TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5

	var blobs: Array[Dictionary] = [{"pos": center, "radius": size * 0.4}]
	for i in range(6):
		var angle := randf() * TAU
		var dist := randf_range(0.08, 0.32) * size
		blobs.append({
			"pos": center + Vector2(cos(angle), sin(angle)) * dist,
			"radius": randf_range(0.12, 0.28) * size,
		})

	for y in range(size):
		for x in range(size):
			var p := Vector2(x, y)
			var alpha := 0.0
			for blob in blobs:
				var d: float = p.distance_to(blob["pos"]) / blob["radius"]
				alpha = maxf(alpha, clampf(1.0 - d, 0.0, 1.0))
			alpha = clampf(alpha * 1.7, 0.0, 1.0) # sharpen the falloff toward the edge
			image.set_pixel(x, y, Color(BLOOD_COLOR.r, BLOOD_COLOR.g, BLOOD_COLOR.b, alpha))

	return ImageTexture.create_from_image(image)
