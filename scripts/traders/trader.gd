class_name Trader
extends AnimatableBody3D

## A trader (the user's, 2026-10-25; docs/QUESTS_TRADERS_WALKERS.md): an old
## man bent from pulling (TraderStoop), in a straw kasa hat, hauling his
## rickshaw shop (Rickshaw) with its goods on show, each with a paper tag on
## a string, its price in pencil.
##   WANDERERS walk their route between the landmarks at SPEED, resting
##   REST_TIME at each stop, and park for you once you're within PARK_RANGE.
##   PARKED ones stay put (under the Flesh Tree, at the Stack's plateau edge,
##   up the Stack).
##   A NEW MEETING -- everyone MEET_RANGE off for MEET_AWAY, then someone comes
##   back -- and his stock's re-rolled (TraderGoods).
## Buying: look at one of his goods -- "[F] Buy: Shotgun, 25 scrap" -- and F:
## the price comes off all your scrap (in your hand and in your bag), and the
## good goes into your right hand (whatever was in it goes in the bag).
## He babbles, no words (TraderVoice): as you come close, at the good you look
## at, at a sale, crossly when you can't pay -- and loud, calling for help.
## Creatures keep Traders.SAFE_RANGE off him (Traders.safe).
## ROBBED (the user's: hurting him is robbing him): it's marked on you for
## good (Traders: every trader charges you more, half refuse you); he calls
## for help -- HELPERS armed humans, mixed, coming for you from out of sight
## HELP_FROM off -- drops the shafts and runs FLEE_TIME, then turns on you:
## his fighting self an armed gunner (the user's: 500 hp, a pistol firing
## twice as fast as a gunner's, 2026-10-26). Everyone
## gone CALM_RANGE off for CALM_AFTER and he's back at his cart. Killed: his
## cart's left where it stood, tipped over (TraderWreck), his goods spilled
## out of it to take, and BACK_IN of play on, a replacement (TraderKeeper).
## Rule 1 (co-op): the host's -- it walks him, sells, re-rolls and fights;
## every game sees him through NetEntities (made with .new(): net_spawn_args /
## net_restore; net_state: his stock's seed, what's sold, walking, his mood,
## where he is by his cart) -- one shared cart (the user's).

enum Mood { CALM, FLEEING, FIGHTING }

const SPEED := 2.0
const PARK_RANGE := 10.0
const REST_TIME := 60.0 # (the user's: a minute)
const MEET_RANGE := 150.0
const MEET_AWAY := 600.0
const TURN_RATE := 1.5
const SETTINGS := "res://traders/trader_settings.tres"
const WALK := "res://art/animations/Walk.res"
const IDLE := "res://art/animations/Idle.res"
const RUN := "res://art/animations/Run.res"
const WALK_SPEED_SCALE := 0.75
## Greeted again once you've been this far off.
const GREET_AGAIN := 30.0
const HAT_COLOR := Color(0.72, 0.6, 0.36)
const HAT_MOSS := Color(0.2, 0.32, 0.18)
## His goods' own layer (F finds them; nothing walks into them).
const GOOD_LAYER := 1 << 21
## A gun on a hook is no longer than this (m).
const HOOK_LENGTH := 0.62
const TAG_SIZE := Vector2(0.07, 0.045)
## Seen (its parts drawn) out to this far.
const SEEN_RANGE := 160.0
## Robbed (the user's): his health, his call for help, his run, his gun.
const HEALTH := 500.0
const HELPERS := 8
const HELP_FROM := Vector2(60.0, 90.0)
const HELPER_SCENES := ["res://scenes/enemy/enemy.tscn", "res://scenes/enemy/enemy_gunner.tscn", "res://scenes/enemy/enemy_rusher.tscn"]
const HELPER_SIGHT := 120.0
const HELPER_MEMORY := 30.0
const HELPERS_GONE := 150.0
const FLEE_TIME := 6.0
const FLEE_SPEED := 4.0
const FIGHTER := "res://scenes/enemy/enemy_gunner.tscn"
## His pistol (the gunner's own) fires this many times as fast as a gunner's.
const FIRE_FASTER := 2.0
const CALM_RANGE := 200.0
const CALM_AFTER := 120.0
## A replacement after this much play (the user's: 80 minutes).
const BACK_IN := 4800.0
const CORPSE := "res://scenes/enemy/enemy.tscn"
const LOOT_SPREAD := 3.0

var trader_id := ""
var parked := false
var route := PackedVector3Array()
var look_seed := 1
var stock_seed := 1
var sold := 0
var walking := false
var mood := Mood.CALM

var _stock: Array[int] = []
var _shown_seed := -1
var _shown_sold := -1
var _cart: Rickshaw
var _cart_body: AnimatableBody3D
var _man: Node3D
var _man_shape: CollisionShape3D
var _model: Node3D
var _fit := 1.0
var _animator: AnimationPlayer
var _goods: Array[Node3D] = []
var _tags: Array[Label3D] = []
var _voice: TraderVoice
var _leg := 0
var _rest_left := 0.0
var _away_for := 0.0
var _last_position := Vector3.INF
var _greeted := false
var _looked := -1
var _tags_left := 0.0
var _terrain: Object
var _health: Health
var _playing := &""
var _robber: PlayerMovement
var _flee_left := 0.0
var _fighter: Enemy
var _quiet_for := 0.0
var _helpers: Array[Enemy] = []
var _helpers_left := 2.0
var _dead := false


func _init() -> void:
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = HEALTH
	add_child(_health)


# ---- Co-op (NetEntities) --------------------------------------------------------------

func net_spawn_args() -> Dictionary:
	return {id = trader_id, parked = parked, look = look_seed}


func net_restore(args: Dictionary) -> void:
	trader_id = str(args.get("id", ""))
	parked = bool(args.get("parked", false))
	look_seed = int(args.get("look", 1))


func net_state() -> Array:
	return [stock_seed | (sold << 20) | ((1 if walking else 0) << 40) | (int(mood) << 41), _man.position if _man else Rickshaw.PULL_POINT]


func net_apply(state: Variant) -> void:
	if not state is Array or (state as Array).size() < 2:
		return
	var packed := int(state[0])
	stock_seed = packed & 0xFFFFF
	sold = (packed >> 20) & 0xFFFFF
	walking = ((packed >> 40) & 1) == 1
	mood = ((packed >> 41) & 3) as Mood
	if _man:
		_man.position = state[1]
		_man.visible = mood != Mood.FIGHTING
		_follow_man()


# ---- Life -------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"traders")
	add_to_group(NetEntities.GROUP)
	add_to_group(PlayerMovement.USABLE_GROUP) # (selling him the last pack)
	sync_to_physics = true
	Traders.register(self)
	var scene := get_tree().current_scene
	_terrain = scene.get_node_or_null(^"Terrain3D") if scene else null
	_cart = Rickshaw.new(look_seed)
	add_child(_cart)
	for node in _cart.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = SEEN_RANGE
	# Him, where he stands to pull: a capsule (shots at him hurt him -- his
	# Health; it follows him off when he runs).
	_man = Node3D.new()
	_man.name = "Man"
	_man.position = Rickshaw.PULL_POINT
	add_child(_man)
	_man_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	_man_shape.shape = capsule
	add_child(_man_shape)
	_follow_man()
	# The cart: solid to walk into (its own body: shooting it doesn't hurt him).
	_cart_body = AnimatableBody3D.new()
	_cart_body.sync_to_physics = false
	var cart_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 1.2)
	cart_shape.shape = box
	cart_shape.position = Vector3(0.0, 0.8, 0.3)
	_cart_body.add_child(cart_shape)
	add_child(_cart_body)
	_build_man()
	_voice = TraderVoice.new()
	_voice.position = Vector3.UP * 1.4
	_man.add_child(_voice)
	Network.fact_changed.connect(func(_name: StringName, _value: Variant) -> void: _tags_left = 0.0)
	if not NetEntities.is_puppet(self) and not (Network.is_online() and not multiplayer.is_server()):
		_restock()
		_health.damaged.connect(_on_hurt)
		_health.died.connect(func(_attacker: int, _critical: bool) -> void: _die(true))
	_refresh_goods()


func _exit_tree() -> void:
	Traders.unregister(self)


# ---- Selling him the last pack (LastPack; the user's) ---------------------------------
# The pack in your hand, F on him: "[F] Sell the last pack: 50 scrap".

var use_prompt: String:
	get:
		return "Sell the last pack: %d scrap" % LastPack.PRICE


func can_use() -> bool:
	return mood == Mood.CALM and not _dead and _pack_near()


## Someone by him with the pack in their hand.
func _pack_near() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and player.global_position.distance_to(_man.global_position) < 5.0 and _holds_pack(player):
			return true
	return false


static func _holds_pack(player: PlayerMovement) -> bool:
	return player.hand != null and player.hand.is_holding() and int(player.hand.data.get("kind", -1)) == Backpack.Kind.CIGARETTES


## The host: the pack out of their hand, the scrap into their bag.
func use_by(by: Node) -> void:
	var player := by as PlayerMovement
	if (Network.is_online() and not multiplayer.is_server()) or player == null or not _holds_pack(player):
		return
	if GrandmaQuests.state(LastPack.QUEST) == GrandmaQuests.State.DONE:
		return
	player.hand.use_up()
	player.backpack.add(Backpack.Kind.SCRAP, LastPack.PRICE)
	player.hand.tell_owner_stored({kind = Backpack.Kind.SCRAP, amount = LastPack.PRICE})
	LastPack.sell(player)
	Network.send_trader_say(trader_id, &"sale")


func _follow_man() -> void:
	if _man_shape and _man:
		_man_shape.position = _man.position + Vector3.UP * 0.8
		_man_shape.disabled = mood == Mood.FIGHTING


## The old man: the settings' model, sized, turned to face the way he pulls,
## bent (TraderStoop), his kasa hat on.
func _build_man() -> void:
	var settings := _settings()
	if settings.model == null:
		return
	_model = settings.model.instantiate() as Node3D
	_man.add_child(_model)
	_model.rotation.y = PI # (Mixamo characters face +Z; he faces -Z)
	var bounds := BackpackView._bounds(_model)
	_fit = settings.height / maxf(bounds.size.y, 0.01)
	_model.scale = Vector3.ONE * _fit
	for node in _model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = SEEN_RANGE
	_animator = PlayerModel.animator_for(_model)
	if not _animator.has_animation_library(&"trader"):
		var library := AnimationLibrary.new()
		for pair: Array in [[&"walk", WALK], [&"idle", IDLE], [&"run", RUN]]:
			if ResourceLoader.exists(pair[1]):
				var clip := (load(pair[1]) as Animation).duplicate() as Animation
				clip.loop_mode = Animation.LOOP_LINEAR
				library.add_animation(pair[0], clip)
		_animator.add_animation_library(&"trader", library)
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var stoop := TraderStoop.new()
	stoop.degrees = settings.stoop_degrees
	skeleton.add_child(stoop)
	put_hat_on(skeleton, look_seed)


static func _settings() -> TraderSettings:
	return load(SETTINGS) as TraderSettings if ResourceLoader.exists(SETTINGS) else TraderSettings.new()


## His straw kasa hat, frayed, moss growing on it -- on `skeleton`'s head
## (sized against the skeleton's own scale), his or his fighting self's.
static func put_hat_on(skeleton: Skeleton3D, seed: int) -> void:
	if skeleton.find_bone("Head") < 0:
		return
	var fit := maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	var hat := Node3D.new()
	hat.scale = Vector3.ONE / fit
	hat.position = Vector3.UP * 0.16 / fit
	attach.add_child(hat)
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.36
	mesh.height = 0.17
	mesh.radial_segments = 14
	mesh.rings = 1
	cone.mesh = mesh
	var straw := StandardMaterial3D.new()
	straw.albedo_color = HAT_COLOR
	straw.roughness = 1.0
	cone.material_override = straw
	hat.add_child(cone)
	var dice := RandomNumberGenerator.new()
	dice.seed = seed
	var moss := StandardMaterial3D.new()
	moss.albedo_color = HAT_MOSS
	moss.roughness = 1.0
	for i in 3:
		var patch := MeshInstance3D.new()
		var piece := BoxMesh.new()
		piece.size = Vector3(dice.randf_range(0.06, 0.12), 0.02, dice.randf_range(0.05, 0.1))
		patch.mesh = piece
		patch.material_override = moss
		var angle := dice.randf() * TAU
		var out := dice.randf_range(0.08, 0.26)
		patch.position = Vector3(cos(angle) * out, 0.085 - out * 0.47 + 0.01, sin(angle) * out)
		patch.rotation = Vector3(0.0, angle, 0.45)
		hat.add_child(patch)


func _physics_process(delta: float) -> void:
	# The wheels turn with how far he's come (every game).
	if _last_position.is_finite() and _cart:
		var moved := global_position - _last_position
		_cart.roll(moved.dot(-global_basis.z))
	_last_position = global_position
	_animate()
	if NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	_helpers_tick(delta)
	match mood:
		Mood.CALM:
			_meet_tick(delta)
			if not parked:
				_walk_tick(delta)
		Mood.FLEEING:
			_flee_tick(delta)
		Mood.FIGHTING:
			_fight_tick(delta)


func _process(delta: float) -> void:
	_refresh_goods()
	_local_tick()
	_tags_left -= delta
	if _tags_left <= 0.0:
		_tags_left = 2.0
		_update_tags()


func _animate() -> void:
	if _animator == null:
		return
	var want := &"trader/run" if mood == Mood.FLEEING else (&"trader/walk" if walking else &"trader/idle")
	if want != _playing and _animator.has_animation(want):
		_playing = want
		_animator.play(want, 0.3, WALK_SPEED_SCALE if want == &"trader/walk" else 1.0)


## Host: a new meeting -- everyone off for MEET_AWAY, and someone's back.
func _meet_tick(delta: float) -> void:
	if _anyone_within(global_position, MEET_RANGE):
		if _away_for >= MEET_AWAY:
			_restock()
		_away_for = 0.0
	else:
		_away_for += delta


func _restock() -> void:
	stock_seed = 1 + (randi() & 0xFFFFE)
	sold = 0


## Host: along his route; parked for anyone within PARK_RANGE; resting at
## each stop.
func _walk_tick(delta: float) -> void:
	walking = false
	if route.is_empty() or _anyone_within(global_position, PARK_RANGE):
		return
	if _rest_left > 0.0:
		_rest_left -= delta
		return
	var target := route[_leg]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() < 1.5:
		_rest_left = REST_TIME # (every stop on his route's a rest)
		_leg = (_leg + 1) % route.size()
		return
	var heading := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	heading = heading.normalized() if heading.length_squared() > 0.0001 else to.normalized()
	var turn := heading.signed_angle_to(to.normalized(), Vector3.UP)
	heading = heading.rotated(Vector3.UP, clampf(turn, -TURN_RATE * delta, TURN_RATE * delta))
	var at := global_position + heading * SPEED * delta
	at.y = _ground(at)
	var front := at + heading * absf(Rickshaw.PULL_POINT.z)
	var rise := _ground(front) - at.y
	global_transform = Transform3D(Basis.looking_at(Vector3(heading.x, rise / absf(Rickshaw.PULL_POINT.z), heading.z).normalized(), Vector3.UP), at)
	walking = true


func _ground(at: Vector3) -> float:
	if _terrain:
		var data: Object = _terrain.get(&"data")
		if data and data.has_method(&"get_height"):
			var height: float = data.call(&"get_height", at)
			if not is_nan(height):
				return height
	return at.y


func _anyone_within(at: Vector3, reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(at) < reach:
			return true
	return false


# ---- Robbed -----------------------------------------------------------------------------

## Host: hurt -- by a player, it's a robbery (the user's).
func _on_hurt(_amount: float, attacker_id: int) -> void:
	if mood != Mood.CALM or _dead or attacker_id < 1:
		return
	var robber := Network.body_of(attacker_id) if Network.is_online() else PlayerMovement.local_player(get_tree())
	if robber == null:
		return
	_rob(robber)


## It's on them for good: every trader charges them more; half of them refuse
## them. He calls for help, drops the shafts and runs.
func _rob(robber: PlayerMovement) -> void:
	_robber = robber
	var who := Traders.id_of(robber)
	Network.send_fact(StringName("trader.robbed.%s" % who), true)
	var keeper := get_tree().get_first_node_in_group(&"trader_keeper") as TraderKeeper
	var everyone: Array = keeper.ids() if keeper else [trader_id]
	for id: String in everyone:
		if randf() < Traders.REFUSE_SHARE:
			Network.send_fact(StringName("trader.%s.refuses.%s" % [id, who]), true)
	mood = Mood.FLEEING
	walking = false
	_flee_left = FLEE_TIME
	Traders.unregister(self) # (no safe ground by him now)
	Network.send_trader_say(trader_id, &"help")
	for i in HELPERS:
		get_tree().create_timer(0.15 * i).timeout.connect(_send_helper.bind(i))


## One of his help: an armed human (mixed), from out of the robber's sight
## HELP_FROM off, coming for them.
func _send_helper(i: int) -> void:
	if not is_inside_tree() or not is_instance_valid(_robber):
		return
	var map := get_world_3d().navigation_map
	var look := -_robber.head.global_basis.z
	look.y = 0.0
	for attempt in 12:
		var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if out.dot(look.normalized()) > 0.3:
			continue # (not where they're looking)
		var want := _robber.global_position + out * randf_range(HELP_FROM.x, HELP_FROM.y)
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if on == Vector3.ZERO or Vector2(on.x - want.x, on.z - want.z).length() > 15.0:
			continue
		var scene := load(HELPER_SCENES[i % HELPER_SCENES.size()]) as PackedScene
		var helper := scene.instantiate() as Enemy
		helper.can_mutate = false
		helper.sight_range = HELPER_SIGHT
		helper.memory_time = HELPER_MEMORY
		get_tree().current_scene.add_child(helper)
		helper.global_position = on + Vector3.UP * 0.5
		helper.set_home(on)
		helper.hunt(_robber)
		_helpers.append(helper)
		return


## His help, gone once nobody's near them.
func _helpers_tick(delta: float) -> void:
	_helpers_left -= delta
	if _helpers_left > 0.0 or _helpers.is_empty():
		return
	_helpers_left = 2.0
	for i in range(_helpers.size() - 1, -1, -1):
		var helper := _helpers[i]
		if not is_instance_valid(helper):
			_helpers.remove_at(i)
		elif not _anyone_within(helper.global_position, HELPERS_GONE):
			helper.queue_free()
			_helpers.remove_at(i)


## Away from the robber, flat out (as an old man goes) -- then he turns.
func _flee_tick(delta: float) -> void:
	_flee_left -= delta
	var from := _robber.global_position if is_instance_valid(_robber) else global_position
	var away := _man.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else -global_basis.z
	var at := _man.global_position + away * FLEE_SPEED * delta
	at.y = _ground(at)
	_man.global_transform = Transform3D(Basis.looking_at(away, Vector3.UP), at)
	_follow_man()
	if _flee_left <= 0.0:
		_ambush()


## His fighting self: an armed gunner in his clothes and hat, the gunner's
## pistol firing FIRE_FASTER as fast, his health -- from cover, at the robber.
func _ambush() -> void:
	var scene := load(FIGHTER) as PackedScene
	var settings := _settings()
	var fighter := scene.instantiate() as Enemy
	var model := fighter.get_node_or_null(^"Model")
	if model and settings.model:
		var variants: Array[PackedScene] = [settings.model]
		model.set(&"variants", variants)
		model.set(&"fit_height", settings.height)
	fighter.attack_interval /= FIRE_FASTER
	fighter.attack_windup /= FIRE_FASTER
	fighter.attack_recovery /= FIRE_FASTER
	fighter.burst_shot_interval /= FIRE_FASTER
	fighter.sight_range = HELPER_SIGHT
	fighter.memory_time = HELPER_MEMORY
	fighter.can_mutate = false
	var fighter_health := fighter.get_node_or_null(^"Health") as Health
	if fighter_health:
		fighter_health.max_health = HEALTH
	get_tree().current_scene.add_child(fighter)
	fighter.global_transform = _man.global_transform
	if fighter_health:
		fighter_health.current_health = _health.current_health
		fighter_health.died.connect(func(_attacker: int, _critical: bool) -> void: _die(false))
	var skeletons := fighter.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		put_hat_on(skeleton, look_seed)
	if is_instance_valid(_robber):
		fighter.hunt(_robber)
	_fighter = fighter
	mood = Mood.FIGHTING
	_man.visible = false
	_follow_man()


## Fighting: everyone gone CALM_RANGE off for CALM_AFTER and he's back at his
## cart (what he's done stays done: the facts).
func _fight_tick(delta: float) -> void:
	if not is_instance_valid(_fighter):
		return
	_quiet_for = 0.0 if _anyone_within(_fighter.global_position, CALM_RANGE) else _quiet_for + delta
	if _quiet_for < CALM_AFTER:
		return
	var fighter_health := _fighter.get_node_or_null(^"Health") as Health
	if fighter_health:
		_health.current_health = fighter_health.current_health
	_fighter.queue_free()
	_fighter = null
	_quiet_for = 0.0
	_man.transform = Transform3D(Basis.IDENTITY, Rickshaw.PULL_POINT)
	_man.visible = true
	mood = Mood.CALM
	_follow_man()
	Traders.register(self)


## Dead: his cart left where it stood, tipped over (TraderWreck, for good),
## what he hadn't sold spilled out of it, his body (`corpse`: he died himself,
## not his fighting self), and BACK_IN of play till a replacement.
func _die(corpse: bool) -> void:
	if _dead:
		return
	_dead = true
	var scene := get_tree().current_scene
	var at := global_transform
	Network.send_fact(StringName("trader.%s.wreck" % trader_id), at.origin)
	Network.send_fact(StringName("trader.%s.wreck_yaw" % trader_id), rotation.y)
	Network.send_fact(StringName("trader.%s.wreck_look" % trader_id), look_seed)
	Network.send_fact(StringName("trader.%s.back_in" % trader_id), BACK_IN)
	var wreck := TraderWreck.new()
	wreck.look_seed = look_seed
	scene.add_child(wreck)
	wreck.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), at.origin)
	for i in _stock.size():
		if sold & (1 << i) == 0:
			var spill := Vector3(randf_range(-LOOT_SPREAD, LOOT_SPREAD), 0.0, randf_range(-LOOT_SPREAD, LOOT_SPREAD))
			var where := at.origin + spill
			where.y = _ground(where) + 0.8
			CarryItem.spawn(scene, where, TraderGoods.data_of(_stock[i]))
	if corpse and ResourceLoader.exists(CORPSE):
		var body := (load(CORPSE) as PackedScene).instantiate() as Enemy
		var settings := _settings()
		var model := body.get_node_or_null(^"Model")
		if model and settings.model:
			var variants: Array[PackedScene] = [settings.model]
			model.set(&"variants", variants)
			model.set(&"fit_height", settings.height)
		body.can_mutate = false
		body.corpse_time = 300.0
		body.set_meta(&"culled", true) # (nothing dropped: his goods are)
		scene.add_child(body)
		body.global_transform = _man.global_transform
		var health := body.get_node(^"Health") as Health
		health.take_damage(health.current_health + 1.0)
	queue_free()


# ---- His goods --------------------------------------------------------------------------

## The cart's goods as his stock and what's sold say (every game).
func _refresh_goods() -> void:
	if _cart == null:
		return
	if stock_seed != _shown_seed:
		_shown_seed = stock_seed
		_shown_sold = -1
		_stock = TraderGoods.roll(stock_seed)
		for node in _goods:
			if is_instance_valid(node):
				node.queue_free()
		_goods.clear()
		_tags.clear()
		var free := {&"hook": [], &"shelf": [], &"eave": []}
		for i in _cart.slots.size():
			(free[_cart.slots[i].show] as Array).append(i)
		for i in _stock.size():
			var slot := _take_slot(free, TraderGoods.GOODS[_stock[i]].show)
			if slot < 0:
				_goods.append(null)
				_tags.append(null)
				continue
			_make_good(i, _cart.slots[slot])
		_tags_left = 0.0
	if sold != _shown_sold:
		_shown_sold = sold
		for i in _goods.size():
			var good := _goods[i]
			if good == null:
				continue
			var gone := sold & (1 << i) != 0
			good.visible = not gone
			var body := good.get_node_or_null(^"Good") as CollisionObject3D
			if body:
				body.collision_layer = 0 if gone else GOOD_LAYER


func _take_slot(free: Dictionary, want: StringName) -> int:
	for kind: StringName in [want, &"shelf", &"hook", &"eave"]:
		var spots: Array = free[kind]
		if not spots.is_empty():
			return spots.pop_front()
	return -1


## One good on show: its model (real size; a gun on a hook no longer than
## HOOK_LENGTH), its paper tag on a string, and what F finds (Good).
func _make_good(i: int, slot: Dictionary) -> void:
	var holder := Node3D.new()
	_cart.add_child(holder)
	holder.transform = slot.xf
	_goods.append(holder)
	var data := TraderGoods.data_of(_stock[i])
	var grenade := load("res://weapons/grenade.tres") as WeaponData if ResourceLoader.exists("res://weapons/grenade.tres") else null
	var model := CarryItem.model_for(data, grenade)
	var size := 0.2
	if model:
		var real := CarryItem.size_of(data) / (1.0 if int(data.kind) == Backpack.Kind.GUN else CarryItem.ITEM_SIZE)
		if slot.show == &"hook":
			real = minf(real, HOOK_LENGTH)
		var bounds := BackpackView._bounds(model)
		var fit := real / maxf(bounds.get_longest_axis_size(), 0.001)
		var pivot := Node3D.new()
		holder.add_child(pivot)
		pivot.add_child(model)
		pivot.scale = Vector3.ONE * fit
		model.position = -bounds.get_center()
		if slot.show == &"shelf":
			pivot.position.y = bounds.size.y * fit * 0.5
		size = real
		for node in model.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).visibility_range_end = SEEN_RANGE
	# Hung on a string under the eave.
	if slot.show == &"eave":
		var string := MeshInstance3D.new()
		var thread := BoxMesh.new()
		thread.size = Vector3(0.006, 0.22, 0.006)
		string.mesh = thread
		string.material_override = Rickshaw._material(Rickshaw.WORN)
		string.position = Vector3.UP * (size * 0.5 + 0.11)
		holder.add_child(string)
	# Its tag: torn paper on a string, the price in pencil (yours: _update_tags).
	var tag := Node3D.new()
	tag.position = Vector3(size * 0.5 + 0.03, -0.02, 0.04)
	holder.add_child(tag)
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TAG_SIZE
	paper.mesh = quad
	var paper_look := StandardMaterial3D.new()
	paper_look.albedo_color = JournalPage.PAPER.lightened(0.15)
	paper_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	paper.material_override = paper_look
	paper.rotation.z = 0.15
	tag.add_child(paper)
	var label := Label3D.new()
	label.font = JournalPage.font()
	label.font_size = 48
	label.pixel_size = 0.0006
	label.modulate = JournalPage.PENCIL
	label.outline_size = 0
	label.position = Vector3(0.0, 0.0, 0.002)
	label.rotation.z = 0.15
	tag.add_child(label)
	_tags.append(label)
	# What F finds.
	var body := Good.new()
	body.name = "Good"
	body.trader = self
	body.index = i
	body.collision_layer = GOOD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * maxf(size, 0.18)
	shape.shape = box
	body.add_child(shape)
	holder.add_child(body)


## The tags' prices -- yours (robbed or not, a discount or not).
func _update_tags() -> void:
	var me := PlayerMovement.local_player(get_tree()) if is_inside_tree() else null
	for i in _tags.size():
		var label := _tags[i]
		if label == null or i >= _stock.size():
			continue
		var text := str(TraderGoods.price(_stock[i], trader_id, me))
		if label.text != text:
			label.text = text


## Your own game: his greeting as you come close, his price as you look at a
## good.
func _local_tick() -> void:
	var me := PlayerMovement.local_player(get_tree())
	if me == null or _voice == null or mood != Mood.CALM:
		return
	var gap := me.global_position.distance_to(global_position)
	if gap < PARK_RANGE and not _greeted:
		_greeted = true
		_voice.babble(&"greet")
	elif gap > GREET_AGAIN:
		_greeted = false
	var looking := -1
	var usable: Node = me.usable_in_view
	if usable is Good and (usable as Good).trader == self:
		looking = (usable as Good).index
	if looking != _looked:
		_looked = looking
		if looking >= 0:
			_voice.babble(&"price")


func babble(kind: StringName) -> void:
	if _voice:
		_voice.babble(kind)


## "Buy: Shotgun, 25 scrap" -- for whoever's looking (your own game).
func prompt_for(i: int) -> String:
	if i >= _stock.size():
		return ""
	var me := PlayerMovement.local_player(get_tree())
	if Traders.refuses(trader_id, me):
		return "He won't sell to you"
	return "Buy: %s, %d scrap" % [TraderGoods.GOODS[_stock[i]].name, TraderGoods.price(_stock[i], trader_id, me)]


func on_sale(i: int) -> bool:
	return mood == Mood.CALM and i < _stock.size() and sold & (1 << i) == 0


## The host: `player` buys his `i`th good -- paid from all their scrap (hand
## and bag), into their right hand; a cross babble if they can't pay (or
## he won't sell to them).
func buy(i: int, player: PlayerMovement) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if player == null or not on_sale(i):
		return
	if Traders.refuses(trader_id, player):
		Network.send_trader_say(trader_id, &"no")
		return
	var price := TraderGoods.price(_stock[i], trader_id, player)
	var hand := player.hand
	var in_hand := int(hand.data.get("amount", 0)) if hand.is_holding() and int(hand.data.get("kind", -1)) == Backpack.Kind.SCRAP else 0
	if player.backpack.scrap + in_hand < price:
		Network.send_trader_say(trader_id, &"no")
		return
	if in_hand > 0:
		hand.put_back() # (the scrap in your hand back in the bag: paid from there)
	if not player.backpack.take(Backpack.Kind.SCRAP, price):
		return
	Network.send_backpack_take(player.get_multiplayer_authority(), Backpack.Kind.SCRAP, price)
	sold |= 1 << i
	hand.give(TraderGoods.data_of(_stock[i]))
	Network.send_trader_say(trader_id, &"sale")


## One of his goods, as F finds it (PlayerMovement's usables).
class Good extends StaticBody3D:
	var trader: Trader
	var index := 0
	var use_prompt: String:
		get:
			return trader.prompt_for(index) if is_instance_valid(trader) else ""

	func _ready() -> void:
		add_to_group(PlayerMovement.USABLE_GROUP)

	func can_use() -> bool:
		return is_instance_valid(trader) and trader.on_sale(index)

	func use_by(player: Node) -> void:
		if is_instance_valid(trader):
			trader.buy(index, player as PlayerMovement)
