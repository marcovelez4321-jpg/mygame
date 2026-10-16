class_name BigOnes
extends RefCounted

## The big ones (the user's, 2026-10-15): in CHANCE of every group of
## enemies (RoamingGroup: a gang of people, a rat swarm, roaches, a spider
## pack) one member is visibly bigger -- SIZE times, HEALTH times the health,
## SPEED times as fast, DAMAGE times the damage -- and drops a meat chunk
## where it dies (CarryItem: SMALL_MEAT kg from a rat, roach or spider,
## HUMAN_MEAT from a person). The level bosses (the worm, the Harvestman, the
## Rat Bender and the Swarm King) drop a boss chunk (BOSS_MEAT, +3 points).
## Rule 1 (co-op): groups are the host's; the chunk is made on the host.

const CHANCE := 0.75
const SIZE := 2.0
const HEALTH := 2.0
## Big spiders on top of that (the user's, 2026-10-16: 25% more).
const BIG_SPIDER_HEALTH := 1.25
const SPEED := 0.8
const DAMAGE := 1.5
const SMALL_MEAT := 1.0
const HUMAN_MEAT := 2.0
const BOSS_MEAT := 4.0


## A new group (RoamingGroup._init()): rolls whether it has a big one, and if
## so makes the first member that can be one big as it arrives -- before its
## own _ready(), so it's born that size.
static func watch(group: RoamingGroup) -> void:
	group.set_meta(&"big_wanted", randf() < CHANCE)
	group.child_entered_tree.connect(_on_member.bind(group))


static func _on_member(member: Node, group: RoamingGroup) -> void:
	if not group.get_meta(&"big_wanted", false):
		return
	if member is RatBender or member is Harvestman:
		return # bosses: their own chunk
	if member is Enemy:
		_big_person(member as Enemy)
	elif member is FlyingRoach:
		_big_roach(member as FlyingRoach)
	elif member is SpiderPack:
		(member as SpiderPack).big_next = 1
	elif member is RatNest:
		var swarm := member.get_node_or_null(^"RatSwarm") as RatSwarm
		if swarm == null:
			return
		swarm.big_next = 1
	else:
		return
	group.set_meta(&"big_wanted", false)


## A person twice the size (the model and the body), before its _ready().
static func _big_person(person: Enemy) -> void:
	person.move_speed *= SPEED
	person.attack_damage *= DAMAGE
	_grow_person(person)
	_more_health(person)
	drops_meat(person, HUMAN_MEAT, false, true) # bursts, no ragdoll (the user's)


static func _grow_person(person: Node) -> void:
	var model := person.get_node_or_null(^"Model") as Node3D
	if model:
		model.scale *= SIZE
	_grow_shape(person.get_node_or_null(^"CollisionShape3D") as CollisionShape3D)


## Co-op, a client: the host's big one's puppet (NetEntities), made the
## same size before it's added. (Rats, spiders and roaches already carry
## their size over; a person's is its model's.)
static func make_puppet_big(node: Node) -> void:
	node.set_meta(&"big", true)
	if node is Enemy:
		_grow_person(node)
		# It bursts on the client's screen too (no ragdoll there either).
		node.ready.connect(func() -> void:
			var health := node.get_node_or_null(^"Health") as Health
			if health:
				health.died.connect(func(_a: int, _c: bool) -> void: _burst(node), CONNECT_ONE_SHOT)
		, CONNECT_ONE_SHOT)


## A roach twice the size (FlyingRoach._apply_size() does its look), before
## its _ready().
static func _big_roach(roach: FlyingRoach) -> void:
	roach.size *= SIZE
	roach.damage *= DAMAGE
	roach.spit_damage *= DAMAGE
	roach.cruise_speed *= SPEED
	roach.dive_speed *= SPEED
	_more_health(roach)
	drops_meat(roach, SMALL_MEAT, false)


## A spider about to be added by its pack (SpiderPack.spawn_spiders()):
## before, its size and bite; after (`added`), its health and pace -- its own
## _ready() gives a bigger spider size-squared health and a slower step, so
## those are brought to HEALTH and SPEED.
static func big_spider(spider: Spider, added: bool) -> void:
	if not added:
		spider.size_min *= SIZE
		spider.size_max *= SIZE
		spider.bite_damage *= DAMAGE
		spider.leap_damage *= DAMAGE
		drops_meat(spider, SMALL_MEAT, false)
		return
	spider.health.max_health *= HEALTH / (SIZE * SIZE) * BIG_SPIDER_HEALTH
	spider.health.current_health = spider.health.max_health
	spider.speed_scale *= SPEED * sqrt(SIZE)


## A rat about to be added by its swarm (RatSwarm.spawn_rats()): its size,
## health and bite before (its own bonuses), its pace after (`added`).
static func big_rat(rat: Rat, added: bool) -> void:
	if not added:
		rat.scale_bonus *= SIZE
		rat.health_bonus *= HEALTH
		rat.damage_bonus *= DAMAGE
		drops_meat(rat, SMALL_MEAT, false)
		return
	rat.speed_scale *= SPEED


static func _more_health(body: Node) -> void:
	var health := body.get_node_or_null(^"Health") as Health
	if health:
		health.max_health *= HEALTH # (it fills up to this in its own _ready())


static func _grow_shape(shape: CollisionShape3D) -> void:
	if shape == null or shape.shape == null:
		return
	shape.shape = shape.shape.duplicate()
	if shape.shape is CapsuleShape3D:
		(shape.shape as CapsuleShape3D).radius *= SIZE
		(shape.shape as CapsuleShape3D).height *= SIZE
	elif shape.shape is SphereShape3D:
		(shape.shape as SphereShape3D).radius *= SIZE
	elif shape.shape is BoxShape3D:
		(shape.shape as BoxShape3D).size *= SIZE
	elif shape.shape is CylinderShape3D:
		(shape.shape as CylinderShape3D).radius *= SIZE
		(shape.shape as CylinderShape3D).height *= SIZE
	shape.position *= SIZE


## When `body` dies, a meat chunk of `weight` kg lands where it died (a
## boss's where the last blow landed: its body is long). `burst` (a big
## person, the user's): no ragdoll -- it bursts in its own blood and the
## chunk is thrown out with the blast.
static func drops_meat(body: Node, weight: float, boss: bool, burst: bool = false) -> void:
	if not boss:
		body.set_meta(&"big", true) # (NetEntities makes its puppet big too)
	var connect_it := func() -> void:
		var health := body.get_node_or_null(^"Health") as Health
		if health == null:
			return
		health.died.connect(func(_attacker: int, _critical: bool) -> void:
			var culled := body.has_meta(&"culled")
			if burst and not culled:
				_burst(body)
			if culled or NetEntities.is_puppet(body) or (Network.is_online() and not body.multiplayer.is_server()):
				return # the host's chunk is the one (it reaches clients as a puppet)
			var at := (body as Node3D).global_position + Vector3.UP * (1.2 if burst else 0.5)
			if boss and health.last_hit_position != Vector3.ZERO:
				at = health.last_hit_position + Vector3.UP * 0.5
			_spawn_chunk.call_deferred(body.get_tree().current_scene, at, weight, boss, burst)
		, CONNECT_ONE_SHOT)
	if body.is_node_ready():
		connect_it.call()
	else:
		body.ready.connect(connect_it, CONNECT_ONE_SHOT)


## Gone in a burst of its own blood: hidden at once (no ragdoll shows) and
## freed next frame. On every machine (a puppet bursts too).
static func _burst(body: Node) -> void:
	var at := (body as Node3D).global_position + Vector3.UP * 1.2
	var blood: Variant = body.get(&"blood_color")
	BloodFX.spawn_mutation_explosion(body.get_tree().current_scene, at, blood if blood is Color else BloodFX.BLOOD_COLOR)
	(body as Node3D).visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.queue_free.call_deferred()


static func _spawn_chunk(world: Node, at: Vector3, weight: float, boss: bool, thrown: bool) -> void:
	if world == null:
		return
	var chunk := CarryItem.spawn_meat(world, at, weight, boss)
	if thrown:
		var out := Vector2.from_angle(randf() * TAU) * randf_range(2.0, 4.0)
		chunk.linear_velocity = Vector3(out.x, randf_range(5.0, 7.0), out.y)