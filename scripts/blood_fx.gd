class_name BloodFX
extends RefCounted

## Shared blood visual effects: a particle spray off a hit body, a splatter
## decal on any wall caught behind that hit, a sustained spurt (artery or
## headshot wound) that splats wherever its stream lands, and a pool that
## fades in on the ground once a ragdoll settles. No texture assets needed -- the splat
## shape is generated once in code the first time it's needed and reused for
## every spray/pool/splatter after that (Rule 2: regenerating it per-instance
## would be pure wasted work for a shape that's identical every time).
##
## Called from weapon_controller.gd (impact spray + wall splatter, right when
## a shot lands) and enemy_ragdoll.gd (ground pool, once the corpse settles).

const SPLAT_TEXTURE_SIZE := 128
## Every decal (blood, goo, bullet holes, dig holes) stays about DECAL_LIFETIME
## seconds -- each one randomly up to DECAL_LIFETIME_VARIANCE either side, so
## they don't all vanish at once -- then fades out over DECAL_FADE_OUT_TIME
## and is removed. Also keeps a long fight from piling up hundreds of decals.
const DECAL_LIFETIME := 25.0
const DECAL_LIFETIME_VARIANCE := 5.0
const DECAL_FADE_OUT_TIME := 2.0
const BLOOD_COLOR := Color(0.35, 0.02, 0.02)
## The spurt's physics, shared by the visible GPU droplets AND the invisible
## traced droplets that decide where blood lands -- one source of truth, so
## splats end up where the spray visibly comes down.
const SPURT_SPREAD_DEGREES := 25.0
const SPURT_SPEED_MIN := 4.5
const SPURT_SPEED_MAX := 8.5
## The artery's shape instead (spawn_artery_stream()): a tight cone and a
## narrow speed range, so every droplet follows nearly the same arc and the
## whole thing reads as one flowing line of blood rather than a radial spray.
const STREAM_SPREAD_DEGREES := 12.0
const STREAM_SPEED_MIN := 6.0
const STREAM_SPEED_MAX := 7.0
## Stronger than real gravity on purpose -- pulls the stream into a pronounced
## curve within its flight time instead of a flat, ballistic-looking spray.
const SPURT_GRAVITY := Vector3(0.0, -14.0, 0.0)
## Longer-lived droplets travel further along their arc before vanishing --
## with the speed above, that's what makes the stream read as long.
const SPURT_LIFETIME := 1.6
## Seconds between traced landing droplets (each one leaves a splat).
const SPURT_LANDING_INTERVAL := 0.2
## Ray segments per traced droplet arc. More = follows the curve more tightly.
const SPURT_TRACE_STEPS := 8

## Tunable streak look for spurts -- see BloodTrailSettings.
const TRAIL_SETTINGS_PATH := "res://fx/blood_trail.tres"

## How many outward blood streaks/arcs a mutation explosion throws -- see
## spawn_mutation_explosion().
const MUTATION_ARC_COUNT := 9
const MUTATION_ARC_MIN_DISTANCE := 1.5
const MUTATION_ARC_MAX_DISTANCE := 4.5
## Brighter and more saturated than BLOOD_COLOR, just for the core blast --
## it needs to read as a burst of fresh blood, not another dark pool.
const MUTATION_BLAST_COLOR := Color(0.75, 0.05, 0.05)

static var _splat_texture: ImageTexture
static var _bullet_hole_texture: ImageTexture
static var _impact_mesh: BoxMesh
## Splat textures in colours other than blood (see _get_splat_texture()).
static var _tinted_splat_textures: Dictionary = {}
static var _trail_settings: BloodTrailSettings
static var _trail_mesh: TubeTrailMesh


## A short, one-shot particle burst at a hit point, kicked out along the
## surface normal it hit. Removes itself once it finishes. `color` lets a
## non-human enemy bleed something else (the roach's green goo). `strength`
## scales it up for a bigger, more dramatic burst (2 = twice the droplets,
## flying further, a bit bigger).
static func spawn_impact(world: Node, position: Vector3, normal: Vector3, color: Color = BLOOD_COLOR, strength: float = 1.0) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = int(18 * strength)
	particles.lifetime = 0.5 + 0.15 * (strength - 1.0)
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.draw_pass_1 = _get_impact_mesh()

	var mat := ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 35.0
	var reach := 1.0 + 0.4 * (strength - 1.0)
	mat.initial_velocity_min = 2.125 * reach
	mat.initial_velocity_max = 5.1 * reach
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.scale_min = 0.25 * sqrt(strength)
	mat.scale_max = 0.6 * sqrt(strength)
	mat.color = color
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
## `local_offset`/`local_direction` place the wound and aim the spray in the
## bone's own space -- the artery uses the defaults (bone center, straight
## out), the headshot bleed passes the spot on the skull that was hit.
## Droplets drag streaks behind them (fx/blood_trail.tres, BloodTrailSettings).
static func spawn_artery_spurt(bone: Node3D, duration: float = 7.0, exclude: Array[RID] = [],
		local_offset: Vector3 = Vector3.ZERO, local_direction: Vector3 = Vector3.UP) -> void:
	_spawn_spurt(bone, duration, exclude, local_offset, local_direction, false)


## The artery: one steady, narrow line of blood instead of the headshot's
## wider spray -- see STREAM_SPREAD_DEGREES. Same trails, same landing trace.
static func spawn_artery_stream(bone: Node3D, duration: float, exclude: Array[RID] = []) -> void:
	_spawn_spurt(bone, duration, exclude, Vector3.ZERO, Vector3.UP, true)


static func _spawn_spurt(bone: Node3D, duration: float, exclude: Array[RID],
		local_offset: Vector3, local_direction: Vector3, narrow: bool) -> void:
	var spread := STREAM_SPREAD_DEGREES if narrow else SPURT_SPREAD_DEGREES
	var speed_min := STREAM_SPEED_MIN if narrow else SPURT_SPEED_MIN
	var speed_max := STREAM_SPEED_MAX if narrow else SPURT_SPEED_MAX

	var particles := GPUParticles3D.new()
	# More, smaller droplets read as a finer, denser stream instead of a
	# handful of chunky flecks.
	particles.amount = 45
	particles.lifetime = SPURT_LIFETIME
	particles.one_shot = false
	# 0 = droplets released evenly, one after another -- that's what joins
	# them into a continuous line. The wider spray keeps a bit of clumping.
	particles.explosiveness = 0.0 if narrow else 0.3
	_apply_trail(particles)

	var mat := ParticleProcessMaterial.new()
	mat.direction = local_direction
	mat.spread = spread
	mat.initial_velocity_min = speed_min
	mat.initial_velocity_max = speed_max
	mat.gravity = SPURT_GRAVITY
	mat.scale_min = 0.4 if narrow else 0.3
	mat.scale_max = 0.55 if narrow else 0.65
	mat.color = BLOOD_COLOR
	particles.process_material = mat

	bone.add_child(particles)
	particles.position = local_offset
	particles.emitting = true

	var tree := bone.get_tree()
	if tree == null:
		return
	# Stop emitting after `duration`, free once the last droplets have landed.
	# Connected to the particles' own methods rather than lambdas, so if the
	# corpse is removed (or the level restarts) first, the connections vanish
	# with it instead of firing into a freed node.
	tree.create_timer(duration).timeout.connect(particles.set.bind(&"emitting", false))
	tree.create_timer(duration + particles.lifetime).timeout.connect(particles.queue_free)

	_start_landing_trace(particles, local_direction, duration, exclude, spread, speed_min, speed_max)


## Puts blood where the spray actually comes down. GPU particles can't report
## where they land, so every SPURT_LANDING_INTERVAL one invisible droplet is
## launched from the wound with the same speed, spread and gravity as the
## visible ones and traced along its arc; a splat goes wherever it hits --
## floor, wall, or another corpse. As the body falls and thrashes, the splats
## follow the stream around.
##
## Mask is EnemyRagdoll.WORLD_MASK (world + ragdoll layer) so blood can land on
## another nearby corpse; `exclude` stops it hitting the body it comes from.
## Rule 1 (co-op): cosmetic and local -- each player's game traces its own
## random droplets, so splat positions differ slightly between players, which
## nobody can tell and nothing in gameplay reads.
##
## Driven by a Timer node parented to the emitter, not get_tree().create_timer():
## if the body is freed mid-spurt, the Timer is freed with it and simply stops,
## instead of a scene-tree timer firing later into a freed emitter.
static func _start_landing_trace(emitter: Node3D, local_direction: Vector3, duration: float, exclude: Array[RID],
		spread: float, speed_min: float, speed_max: float) -> void:
	_trace_one_droplet(emitter, local_direction, exclude, spread, speed_min, speed_max)
	var timer := Timer.new()
	timer.wait_time = SPURT_LANDING_INTERVAL
	timer.autostart = true
	emitter.add_child(timer)
	var stop_msec := Time.get_ticks_msec() + int(duration * 1000.0)
	timer.timeout.connect(func() -> void:
		if Time.get_ticks_msec() >= stop_msec:
			timer.queue_free()
			return
		_trace_one_droplet(emitter, local_direction, exclude, spread, speed_min, speed_max)
	)


static func _trace_one_droplet(emitter: Node3D, local_direction: Vector3, exclude: Array[RID],
		spread: float, speed_min: float, speed_max: float) -> void:
	var direction := (emitter.global_transform.basis * local_direction).normalized()
	var velocity := _random_in_cone(direction, spread) * randf_range(speed_min, speed_max)
	var hit := _trace_arc(emitter.get_world_3d().direct_space_state, emitter.global_position, velocity, exclude)
	if not hit.is_empty():
		spawn_splatter(emitter.get_tree().current_scene, hit.position, hit.normal, randf_range(0.25, 0.4))


## Follows one droplet's arc in SPURT_TRACE_STEPS straight ray segments and
## returns the first hit, or {} if it never lands within its lifetime.
static func _trace_arc(space: PhysicsDirectSpaceState3D, origin: Vector3, velocity: Vector3, exclude: Array[RID]) -> Dictionary:
	var step := SPURT_LIFETIME / SPURT_TRACE_STEPS
	var point := origin
	for _step_index in SPURT_TRACE_STEPS:
		var next := point + velocity * step + SPURT_GRAVITY * (0.5 * step * step)
		var query := PhysicsRayQueryParameters3D.create(point, next)
		query.collision_mask = EnemyRagdoll.WORLD_MASK
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit
		velocity += SPURT_GRAVITY * step
		point = next
	return {}


## `direction` nudged randomly inside a cone of `degrees` half-angle -- the
## same shape ParticleProcessMaterial.spread uses for the visible droplets.
static func _random_in_cone(direction: Vector3, degrees: float) -> Vector3:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var aim := Basis.looking_at(direction, up) # -Z of this basis is `direction`
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0)
	var offset := jitter * tan(deg_to_rad(degrees))
	return (aim * Vector3(offset.x, offset.y, -1.0)).normalized()


## Droplets drag streaks behind them, tuned in fx/blood_trail.tres. The trail
## mesh is built once and shared by every spurt.
static func _apply_trail(particles: GPUParticles3D) -> void:
	var settings := _get_trail_settings()
	if not settings.enabled:
		particles.draw_pass_1 = _get_impact_mesh()
		return
	particles.trail_enabled = true
	particles.trail_lifetime = settings.lifetime
	particles.draw_pass_1 = _get_trail_mesh(settings)


static func _get_trail_settings() -> BloodTrailSettings:
	if _trail_settings == null:
		_trail_settings = load(TRAIL_SETTINGS_PATH) as BloodTrailSettings
		if _trail_settings == null:
			_trail_settings = BloodTrailSettings.new() # file missing: use the defaults
	return _trail_settings


## A TubeTrailMesh bends along each droplet's recent path; its material needs
## use_particle_trails or the tube renders as a straight, unbent stick.
static func _get_trail_mesh(settings: BloodTrailSettings) -> TubeTrailMesh:
	if _trail_mesh == null:
		_trail_mesh = TubeTrailMesh.new()
		_trail_mesh.radius = settings.radius
		_trail_mesh.radial_steps = settings.radial_steps
		_trail_mesh.sections = settings.sections
		var mat := StandardMaterial3D.new()
		mat.albedo_color = settings.color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.use_particle_trails = true
		_trail_mesh.material = mat
	return _trail_mesh


## The mutation payoff: a big saturated red blast right at the explosion's
## center, plus several longer blood streaks/arcs thrown outward at varying
## angles and distances that each land and leave their own pool -- meant to
## read as something violently bursting, not just a bigger version of a
## normal kill's spray. Called once, from enemy_ragdoll.gd's
## _explode_and_spawn_mutant().
static func spawn_mutation_explosion(world: Node, center: Vector3) -> void:
	_spawn_blast_core(world, center)
	for i in MUTATION_ARC_COUNT:
		# Evenly spaced base angle with random jitter mixed in, so the arcs
		# fan out in every direction but don't look like a perfect,
		# mechanical ring -- "varying", not uniform.
		var angle: float = (TAU / MUTATION_ARC_COUNT) * i + randf_range(-0.4, 0.4)
		var horizontal := Vector3(cos(angle), 0.0, sin(angle))
		var distance := randf_range(MUTATION_ARC_MIN_DISTANCE, MUTATION_ARC_MAX_DISTANCE)
		_spawn_blood_arc(world, center, horizontal, distance)


## The central flash: bigger and brighter than a normal impact spray, thrown
## in every direction (spread 180, no single surface normal to kick off of)
## instead of one directional cone -- this is what reads as "burst" rather
## than "sprayed".
static func _spawn_blast_core(world: Node, center: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.draw_pass_1 = _get_impact_mesh()

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 11.0
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.scale_min = 0.4
	mat.scale_max = 0.9
	mat.color = MUTATION_BLAST_COLOR
	particles.process_material = mat

	world.add_child(particles)
	particles.global_position = center
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## One outward streak/arc: a one-shot directional burst thrown along
## `horizontal` and up, curving down under gravity the same way
## spawn_artery_spurt()'s stream does, then a landing pool wherever it comes
## down -- a straight-down raycast at the arc's landing XZ, same
## "approximate, not a true per-particle trace" technique _pool_landing_spot()
## uses, just a single check since this is one one-shot burst, not a
## sustained spray to keep re-checking.
static func _spawn_blood_arc(world: Node, center: Vector3, horizontal: Vector3, distance: float) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.draw_pass_1 = _get_impact_mesh()

	var mat := ParticleProcessMaterial.new()
	mat.direction = (horizontal + Vector3.UP * 0.6).normalized()
	mat.spread = 12.0
	mat.initial_velocity_min = distance * 3.0
	mat.initial_velocity_max = distance * 4.0
	mat.gravity = Vector3(0.0, -14.0, 0.0)
	mat.scale_min = 0.25
	mat.scale_max = 0.55
	mat.color = BLOOD_COLOR
	particles.process_material = mat

	world.add_child(particles)
	particles.global_position = center
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

	var landing_xz := center + horizontal * distance
	# get_world_3d() lives on Node3D, not the plain Node this function (like
	# every other spawn_*() here) takes -- `world` is always a Node3D in
	# practice (the level root), so the cast is safe.
	var space := (world as Node3D).get_world_3d().direct_space_state
	var down_query := PhysicsRayQueryParameters3D.create(
			landing_xz + Vector3.UP * 3.0, landing_xz + Vector3.DOWN * 6.0)
	down_query.collision_mask = EnemyRagdoll.WORLD_MASK
	var down_result := space.intersect_ray(down_query)
	if not down_result.is_empty():
		spawn_splatter(world, down_result.position, down_result.normal, randf_range(0.7, 1.1))


## A blood decal stuck to whatever surface is at `position`, facing away
## along `normal` -- used for both wall splatter (a shot punching through to
## a wall behind the target) and, from enemy_ragdoll.gd, the ground pool
## (normal = Vector3.UP). Fades in rather than popping, and both the size and
## the facing get a little randomness so repeated hits don't look identical.
static func spawn_splatter(world: Node, position: Vector3, normal: Vector3, base_size: float = 1.0, color: Color = BLOOD_COLOR) -> void:
	_place_decal(world, _get_splat_texture(color), position, normal, base_size, 0.4)


## Builds the splat texture for `color` ahead of time. Generating one takes a
## moment, so an enemy that bleeds another colour calls this when it spawns
## instead of hitching the game on its first death.
static func warm_splat_texture(color: Color) -> void:
	_get_splat_texture(color)


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
## look identical, then fades it in over `fade_time`, and out again after its
## lifetime (DECAL_LIFETIME).
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
	var stay := DECAL_LIFETIME + randf_range(-DECAL_LIFETIME_VARIANCE, DECAL_LIFETIME_VARIANCE)
	tween.tween_interval(maxf(stay - fade_time - DECAL_FADE_OUT_TIME, 0.0))
	tween.tween_property(decal, "modulate:a", 0.0, DECAL_FADE_OUT_TIME)
	tween.tween_callback(decal.queue_free)


## The little cube every blood/goo particle is drawn with, for other effects
## that drip the same way (AcidSpit's trail). Tinted by the particle colour.
static func droplet_mesh() -> BoxMesh:
	return _get_impact_mesh()


## White and tinted per burst by each ParticleProcessMaterial's `color`
## (vertex_color_use_as_albedo), so one shared mesh serves red blood, the
## mutation blast and green roach goo alike.
static func _get_impact_mesh() -> BoxMesh:
	if _impact_mesh == null:
		_impact_mesh = BoxMesh.new()
		_impact_mesh.size = Vector3.ONE * 0.05
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_impact_mesh.material = mat
	return _impact_mesh


## One splat texture per colour, generated once and kept.
static func _get_splat_texture(color: Color = BLOOD_COLOR) -> ImageTexture:
	if color == BLOOD_COLOR:
		if _splat_texture == null:
			_splat_texture = _generate_splat_texture(color)
		return _splat_texture
	if not _tinted_splat_textures.has(color):
		_tinted_splat_textures[color] = _generate_splat_texture(color)
	return _tinted_splat_textures[color]


## Public on purpose (unlike the underscore-prefixed getters here) -- hud.gd
## calls this directly for the screen blood droplets.
##
## Just reuses the plain circular splat texture. There WAS a separate,
## fancier irregular-blob version here (per-pixel angle()/sin() calls over
## the whole 128x128 image), but generating it the first time it was needed
## -- mid-gameplay, right as a kill landed -- caused a real, reported hitch.
## Simple and instant beats fancy and freezes. Same per-colour cache as the
## world splats, so a roach's goo texture is already built (it warms it on
## spawn) by the time one dies in your face.
static func get_screen_splat_texture(color: Color = BLOOD_COLOR) -> ImageTexture:
	return _get_splat_texture(color)


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
static func _generate_splat_texture(color: Color) -> ImageTexture:
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
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))

	return ImageTexture.create_from_image(image)
