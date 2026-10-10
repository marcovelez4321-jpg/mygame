class_name WormDirector
extends Node

## The boss worm as an event in the open world, not a fixture: it lives
## under the megastructures, and comes up when players linger round one.
## Like Left 4 Dead's AI Director, it's driven by a hidden build-up, not a
## timer, so it never feels scheduled:
##   HUNGER: while a player's within lair_reach of a megastructure (a lair)
##   the hunger fills (in about hunger_time; every shot fired adds more) and
##   it drains away while nobody is. Only lairs not resting count.
##   It can only come once the cooldown since the last time is up (a random
##   cooldown_min..cooldown_max), so at most one every 15-20 minutes.
##   BUILD-UP (buildup_time): the ground rumbles louder and louder round the
##   lair, cameras shake, dust pours off the structure, and every eye
##   cluster near it opens and stares at it. Then it erupts beside the
##   structure, on the side facing the nearest player, in a leap at them.
##   IT LEAVES once every player's been leave_distance from it for
##   leave_grace seconds, or it's been up max_time: it dives and is gone. Or
##   it dies. Either way that lair then rests (lair_rest), so the next one
##   comes from somewhere else.
##   THE STACK (a walk-up Megastructure's Lair) is its home, and it doesn't
##   wait to get hungry there: arrive within arrival_range of one and it
##   comes (the build-up, then up), whatever the cooldown. Once per arrival:
##   it only comes again after everyone's left that range and come back.
## Rule 1 (co-op): the host runs all of it; the worm is a normal spawn.

@export var worm_scene: PackedScene = preload("res://scenes/enemy/burrow_worm.tscn")
## Seconds between events (a random time in this range after each).
@export var cooldown_min: float = 900.0
@export var cooldown_max: float = 1200.0
## A megastructure counts as a lair: one this tall at least (metres), and
## players within lair_reach of it feed the hunger.
@export var lair_min_height: float = 20.0
@export var lair_reach: float = 220.0
## Seconds near a lair to fill the hunger, and seconds each shot adds.
@export var hunger_time: float = 90.0
@export var shot_hunger: float = 1.5
@export var buildup_time: float = 15.0
## How far from the structure's side it comes up (metres).
@export var erupt_offset: float = 18.0
@export var leave_distance: float = 160.0
@export var leave_grace: float = 8.0
@export var max_time: float = 120.0
## Seconds a lair rests after its worm's been up.
@export var lair_rest: float = 3600.0
## A megastructure lair (its home) calls it up as soon as a player comes
## within this of it (metres, across the ground).
@export var arrival_range: float = 350.0
## The chunk streamer and the ground (empty = found next to this node).
@export var chunks: WorldChunks
@export var terrain: Node3D

const RUMBLE := preload("res://audio/sfx/worm_rumble.wav")
const DUST := Color(0.3, 0.27, 0.2)

enum State { WAITING, BUILDING, UP, LEAVING }

var _state := State.WAITING
var _cooldown := 0.0
var _hunger := 0.0
## Loaded lairs: chunk -> its tallest building's collision shape.
var _lairs := {}
## Resting lairs: chunk -> msec they can host again.
var _resting := {}
var _lair: CollisionShape3D
var _lair_chunk := Vector2i.ZERO
var _timer := 0.0
var _away := 0.0
var _worm: BurrowWorm
var _rumble: AudioStreamPlayer3D
var _tick := 0.0
var _hooked := {}
## Megastructure lairs players are at now (lair -> true): an arrival is a
## player coming in range of one that isn't in this.
var _at_home := {}


func _ready() -> void:
	if chunks == null:
		chunks = get_parent().get_node_or_null(^"WorldChunks") as WorldChunks
	if terrain == null:
		terrain = get_parent().get_node_or_null(^"Terrain3D") as Node3D
	if chunks == null or terrain == null:
		push_warning("WormDirector: needs a WorldChunks and a Terrain3D next to it")
		set_process(false)
		return
	chunks.chunk_loaded.connect(_on_chunk_loaded)
	chunks.chunk_unloading.connect(_on_chunk_unloading)
	# The first one can come a little sooner than the rest.
	_cooldown = randf_range(0.5, 1.0) * cooldown_min


func _on_chunk_loaded(chunk: Vector2i, root: Node3D) -> void:
	var tallest: CollisionShape3D = null
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var box := (node as CollisionShape3D).shape as BoxShape3D
		if box and box.size.y >= lair_min_height and (tallest == null or box.size.y > (tallest.shape as BoxShape3D).size.y):
			tallest = node
	if tallest:
		_lairs[chunk] = tallest


func _on_chunk_unloading(chunk: Vector2i, _root: Node3D) -> void:
	_lairs.erase(chunk)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer += delta
	if _state == State.BUILDING:
		_build_up(delta)
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0 # the rest is slow thinking: once a second
	match _state:
		State.WAITING:
			_hook_shots()
			_cooldown -= 1.0
			var home := _arrived_home()
			if home:
				_start(Vector2i(2000000, home.get_instance_id() % 100000), home)
				return
			var lair := _lair_near_players()
			if lair.is_empty():
				_hunger = maxf(_hunger - 0.5 / hunger_time, 0.0)
				return
			# Its home (a megastructure's Lair) makes it hungrier, faster.
			_hunger += float((lair.shape as Node).get_meta(&"hunger_scale", 1.0)) / hunger_time
			if _hunger >= 1.0 and _cooldown <= 0.0:
				_start(lair.chunk, lair.shape)
		State.UP:
			_watch_worm()
		State.LEAVING:
			if not is_instance_valid(_worm):
				_end()


## A megastructure lair a player has just come within arrival_range of
## (one nobody was at a moment ago), or null. Keeps note of who's at which.
func _arrived_home() -> CollisionShape3D:
	var arrived: CollisionShape3D = null
	for node in get_tree().get_nodes_in_group(Megastructure.LAIR_GROUP):
		var lair := node as CollisionShape3D
		if lair == null:
			continue
		var centre := lair.global_position
		var near := false
		for player in get_tree().get_nodes_in_group("player"):
			var at := (player as Node3D).global_position
			if Vector2(at.x - centre.x, at.z - centre.z).length() < arrival_range:
				near = true
		if near and not _at_home.has(lair) and arrived == null:
			arrived = lair
		if near:
			_at_home[lair] = true
		else:
			_at_home.erase(lair)
	return arrived


## The lair nearest any player, within lair_reach, that isn't resting:
## {chunk, shape}, or empty.
func _lair_near_players() -> Dictionary:
	var now := Time.get_ticks_msec()
	var best := {}
	var best_distance := lair_reach
	# Chunks' megastructures, and the walk-up megastructures (Megastructure's
	# Lair: it lives there -- the key just has to be its own).
	var lairs := _lairs.duplicate()
	# (Megastructure lairs come by arrival instead: _arrived_home.)
	for chunk: Vector2i in lairs:
		var shape: CollisionShape3D = lairs[chunk]
		if not is_instance_valid(shape) or int(_resting.get(chunk, 0)) > now:
			continue
		for node in get_tree().get_nodes_in_group("player"):
			var distance := (node as Node3D).global_position.distance_to(shape.global_position)
			if distance < best_distance:
				best_distance = distance
				best = {chunk = chunk, shape = shape}
	return best


## Every player's gun feeds the hunger with each shot (hooked as they appear).
func _hook_shots() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		for found in node.find_children("*", "WeaponController", true, false):
			var weapons := found as WeaponController
			if weapons and not _hooked.has(weapons):
				_hooked[weapons] = true
				weapons.shot_fired.connect(_on_shot)


func _on_shot() -> void:
	if _state == State.WAITING:
		_hunger += shot_hunger / hunger_time


func _start(chunk: Vector2i, shape: CollisionShape3D) -> void:
	_state = State.BUILDING
	_lair = shape
	_lair_chunk = chunk
	_timer = 0.0
	_rumble = AudioStreamPlayer3D.new()
	_rumble.stream = RUMBLE
	_rumble.volume_db = -20.0
	_rumble.max_distance = lair_reach * 1.5
	_rumble.unit_size = 30.0
	add_child(_rumble)
	_rumble.global_position = _foot_of(shape)
	_rumble.finished.connect(_rumble.play) # loops
	_rumble.play()
	EyeCluster.stare(shape.global_position, lair_reach, buildup_time + 6.0)


## The build-up: rumbling louder and louder, cameras shaking harder, dust
## pouring off the structure; then it comes up.
func _build_up(delta: float) -> void:
	if not is_instance_valid(_lair):
		_end() # its chunk went before it could come
		return
	var t := clampf(_timer / buildup_time, 0.0, 1.0)
	_rumble.volume_db = lerpf(-20.0, 6.0, t)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.4
		var foot := _foot_of(_lair)
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as Node3D
			var distance := player.global_position.distance_to(foot)
			if distance < lair_reach and player.get("camera") is CameraJuice:
				(player.get("camera") as CameraJuice).shake((0.4 + t * 2.5) * (1.0 - distance / lair_reach))
		_dust(t)
	if _timer >= buildup_time:
		_erupt()


## Dust and grit shaken off the structure's sides, more as it builds.
func _dust(t: float) -> void:
	var box := _lair.shape as BoxShape3D
	var half := box.size * 0.5
	for i in 1 + int(t * 4.0):
		var side := Vector3([-1.0, 1.0][randi() % 2] * half.x, randf_range(-0.2, 1.0) * half.y, randf_range(-1.0, 1.0) * half.z)
		if randf() < 0.5:
			side = Vector3(randf_range(-1.0, 1.0) * half.x, side.y, [-1.0, 1.0][randi() % 2] * half.z)
		BloodFX.spawn_impact(get_tree().current_scene, _lair.global_transform * side, Vector3.DOWN, DUST, 1.0 + t * 2.0)


## Up it comes: beside the structure, on the side facing the nearest
## player, straight into a leap at them.
func _erupt() -> void:
	var prey := _nearest_player(_lair.global_position)
	var centre := _lair.global_position
	var toward := Vector3.FORWARD
	if prey:
		toward = Vector3(prey.global_position.x - centre.x, 0.0, prey.global_position.z - centre.z)
		toward = toward.normalized() if toward.length_squared() > 0.01 else Vector3.FORWARD
	var box := _lair.shape as BoxShape3D
	var spot := centre + toward * (maxf(box.size.x, box.size.z) * 0.5 + erupt_offset)
	var data: Object = terrain.call("get_data")
	var ground: float = data.call("get_height", spot) if data else centre.y
	spot.y = ground if not is_nan(ground) else centre.y
	_worm = worm_scene.instantiate() as BurrowWorm
	_worm.position = spot # the world's root sits at the origin
	get_tree().current_scene.add_child(_worm)
	if prey:
		_worm.erupt_at_once.call_deferred(prey)
	_state = State.UP
	_timer = 0.0
	_away = 0.0
	_rumble.queue_free()
	_rumble = null


## Up: it leaves once everyone's got away from it for a while, or it's been
## up long enough.
func _watch_worm() -> void:
	if not is_instance_valid(_worm):
		_end() # killed
		return
	var nearest := _nearest_player(_worm.ground_position())
	var far := nearest == null or nearest.global_position.distance_to(_worm.ground_position()) > leave_distance
	_away = _away + 1.0 if far else 0.0
	if _away >= leave_grace or _timer >= max_time:
		_worm.retreat()
		_state = State.LEAVING


func _end() -> void:
	_resting[_lair_chunk] = Time.get_ticks_msec() + int(lair_rest * 1000.0)
	_state = State.WAITING
	_hunger = 0.0
	_cooldown = randf_range(cooldown_min, cooldown_max)
	_worm = null
	_lair = null
	if _rumble:
		_rumble.queue_free()
		_rumble = null


func _nearest_player(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not Factions.is_alive_target(player):
			continue
		var distance := player.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## The ground at the middle of a structure's foot.
func _foot_of(shape: CollisionShape3D) -> Vector3:
	var at := shape.global_position
	var data: Object = terrain.call("get_data")
	var ground: float = data.call("get_height", at) if data else at.y
	return Vector3(at.x, ground if not is_nan(ground) else at.y, at.z)
