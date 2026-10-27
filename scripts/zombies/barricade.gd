class_name Barricade
extends StaticBody3D

## A window the horde comes in through (the user's, 2026-10-27: half the
## windows can be crawled through, boarded; the other half are painted, like
## before -- docs/ZOMBIES_DIRECTION.md). Its origin is the opening's middle;
## its -Z looks out.
##   The horde: WindowSpawner sends one here (Enemy.window); it walks up to
##   the outside, tears the boards off one at a time (TEAR_TIME each), then
##   crawls in (CRAWL_TIME) and hunts. Others queue behind it.
##   You: F at it puts a board back (REPAIR_TIME between; free for now --
##   points come with the rounds).
## While it's boarded it blocks the opening; torn open, it doesn't (the use
## ray still finds it on a layer nothing walks into).
## Rule 1 (co-op): the host's -- it drives the horde through and decides the
## boards, every game shows them (_net_boards).

const BOARDS := 6
const TEAR_TIME := 1.4
const CRAWL_TIME := 1.0
const REPAIR_TIME := 0.7
## The opening (width, height), and how far its floor is below its middle
## (a small window low down; the Stack's grid windows are 3 x 3.75, their
## sills 2.25 up: 4.125).
@export var size := Vector2(1.6, 1.6)
@export var drop := 1.7
## How thick the wall it's in is.
@export var depth := 2.0
const WOOD := Color(0.3, 0.22, 0.15)
const OPEN_LAYER := 1 << 21

var use_prompt: String = "Repair the barricade"

var boards := BOARDS
var _boards: Array[MeshInstance3D] = []
var _queue: Array = []
var _tear_left := TEAR_TIME
var _crawler: Enemy
var _crawl_t := 0.0
var _repair_left := 0.0


func _ready() -> void:
	add_to_group(&"barricades")
	add_to_group(PlayerMovement.USABLE_GROUP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, maxf(depth - 0.2, 0.4))
	shape.shape = box
	add_child(shape)
	var look := StandardMaterial3D.new()
	look.albedo_color = WOOD
	look.roughness = 1.0
	for i in BOARDS:
		var board := MeshInstance3D.new()
		var plank := BoxMesh.new()
		plank.size = Vector3(size.x + 0.3, 0.2, 0.05)
		board.mesh = plank
		board.material_override = look
		var y := lerpf(-size.y * 0.42, size.y * 0.42, float(i) / (BOARDS - 1))
		board.position = Vector3(0.0, y, 0.05 + 0.03 * (i % 2))
		board.rotation.z = 0.22 if i % 2 == 0 else -0.18
		add_child(board)
		_boards.append(board)
	_show()


## Where the horde stands to tear it open, and comes out inside (the world).
func outside_point() -> Vector3:
	return global_transform * Vector3(0.0, -drop, -depth * 0.5 - 0.4)


func inside_point() -> Vector3:
	return global_transform * Vector3(0.0, -drop, depth * 0.5 + 0.2)


## Where WindowSpawner puts a new one (a little further out).
func spawn_point() -> Vector3:
	return global_transform * Vector3(0.0, -drop + 0.1, -depth * 0.5 - 2.0)


## The host: `enemy` is coming in here.
func claim(enemy: Enemy) -> void:
	if not _queue.has(enemy):
		_queue.append(enemy)


## The host: `enemy` isn't coming after all (grabbed, killed).
func forget(enemy: Enemy) -> void:
	_queue.erase(enemy)
	if _crawler == enemy:
		_crawler = null


## The host, each of `enemy`'s physics ticks while it's coming in (Enemy).
func drive(enemy: Enemy, delta: float) -> void:
	_queue = _queue.filter(func(one: Variant) -> bool: return is_instance_valid(one) and (one as Enemy).get_state() != Enemy.State.DEAD)
	if not _queue.has(enemy):
		_queue.append(enemy)
	if enemy == _crawler:
		_crawl(enemy, delta)
		return
	var place := _queue.find(enemy)
	var out := -global_basis.z
	var stand := outside_point() - out * (1.1 * place)
	var to := stand - enemy.global_position
	to.y = 0.0
	_face(enemy, -out)
	if to.length() > 0.4:
		var step := to.normalized() * enemy.move_speed
		enemy.velocity.x = step.x
		enemy.velocity.z = step.z
		enemy.window_pose(true)
	else:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
		enemy.window_pose(false)
		if place == 0 and _crawler == null:
			if boards > 0:
				_tear_left -= delta
				if _tear_left <= 0.0:
					_tear_left = TEAR_TIME
					_set_boards(boards - 1)
			else:
				_crawler = enemy
				_crawl_t = 0.0
				enemy.get_node(^"CollisionShape3D").set_deferred(&"disabled", true)
	if not enemy.is_on_floor():
		enemy.velocity.y -= enemy.gravity * delta
	enemy.move_and_slide()


## Over the sill and in.
func _crawl(enemy: Enemy, delta: float) -> void:
	_crawl_t += delta / CRAWL_TIME
	var t := clampf(_crawl_t, 0.0, 1.0)
	var lift := sin(t * PI) * drop * 0.8
	enemy.global_position = outside_point().lerp(inside_point(), t) + Vector3.UP * lift
	if t >= 1.0:
		_crawler = null
		_queue.erase(enemy)
		enemy.get_node(^"CollisionShape3D").set_deferred(&"disabled", false)
		enemy.window = null
		var nearest: PlayerMovement = null
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as PlayerMovement
			if player and not player.is_dead() and (nearest == null or player.global_position.distance_to(enemy.global_position) < nearest.global_position.distance_to(enemy.global_position)):
				nearest = player
		if nearest:
			enemy.hunt(nearest)


func _face(enemy: Enemy, way: Vector3) -> void:
	var flat := Vector3(way.x, 0.0, way.z)
	if flat.length_squared() > 0.001:
		enemy.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)


# ---- You: F puts a board back --------------------------------------------------------------

func can_use() -> bool:
	return boards < BOARDS and _crawler == null


func use_by(player: Node) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if not can_use() or _repair_left > 0.0 or player == null:
		return
	_repair_left = REPAIR_TIME
	_set_boards(boards + 1)


func _process(delta: float) -> void:
	_repair_left = maxf(_repair_left - delta, 0.0)


func _set_boards(count: int) -> void:
	_apply_boards(count)
	if Network.is_online() and multiplayer.is_server():
		_net_boards.rpc(count)


@rpc("authority", "call_remote", "reliable")
func _net_boards(count: int) -> void:
	_apply_boards(count)


func _apply_boards(count: int) -> void:
	boards = clampi(count, 0, BOARDS)
	_show()


func _show() -> void:
	for i in _boards.size():
		_boards[i].visible = i < boards
	collision_layer = 1 if boards > 0 else OPEN_LAYER
