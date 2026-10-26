class_name BellWraith
extends StaticBody3D

## A BELL-WRAITH (the user's, 2026-10-25/26): a great corroded bell (SIZE)
## hanging in the dark, its clapper a long grasping arm coiled up inside it.
## Only the place's own bells and machines wake it (the Ossuary's bell as it
## settles and rises): AWAKE for AWAKE_TIME, and once -- if anyone's within
## REACH -- its arm whips down and out at them: HIT and a SHOVE that throws
## them (a lash, no hold). Asleep, it's just a bell: bullets clang off; awake,
## HEALTH and it falls dead.
## Every game hangs the same ones (the Ossuary's: OssuaryLife); the host's
## wakes them, lashes and decides when one dies, and tells every game
## (Network.send_wraith_event).

const SIZE := 5.0
const REACH := 20.0
const AWAKE_TIME := 10.0
const HIT := 20.0
const SHOVE := 20.0
const HEALTH := 80.0
const LASH_TIME := 0.35
const ARM_PIECES := 14
const BRONZE := Color(0.5, 0.55, 0.4)
const ARM := Color(0.5, 0.48, 0.45)
## Anyone within this, its arm hangs out of its mouth (HANG long), swinging
## like a clapper (SWING_ANGLE either way, once every SWING_PERIOD).
const NEAR := 30.0
const HANG := 8.0
const SWING_ANGLE := deg_to_rad(35.0)
const SWING_PERIOD := 2.4
## Optimizing: who's near looked at every NEAR_EVERY.
const NEAR_EVERY := 0.25

var wraith_id := 0

var _health: Health
var _awake_left := 0.0
var _lashed := false
var _lash_t := -1.0
var _lash_to := Vector3.ZERO
## Its arm's pieces, all one draw (a MultiMesh).
var _arm: MultiMesh
var _hand: MeshInstance3D
var _bell: Node3D
var _swing := 0.0
## How far out its arm hangs (0: coiled up inside, 1: HANG out).
var _hang := 0.0
var _near := false
var _near_left := 0.0
var _seen := false
## Coiled up, and posed so: nothing to pose till it moves.
var _posed_still := false
var _dead := false

static var _bronze: StandardMaterial3D
static var _skin: StandardMaterial3D


func _init() -> void:
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = HEALTH
	add_child(_health)


func _ready() -> void:
	add_to_group(&"bell_wraiths")
	_bell = Node3D.new()
	add_child(_bell)
	var bell := MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = SIZE * 0.3
	body.bottom_radius = SIZE * 0.5
	body.height = SIZE * 0.8
	body.radial_segments = 16
	body.rings = 2
	body.cap_bottom = false
	bell.mesh = body
	bell.material_override = bronze()
	bell.position = Vector3.DOWN * SIZE * 0.4
	_bell.add_child(bell)
	var crown := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = SIZE * 0.3
	dome.height = SIZE * 0.35
	crown.mesh = dome
	crown.material_override = bronze()
	_bell.add_child(crown)
	var chain := MeshInstance3D.new()
	var link := BoxMesh.new()
	link.size = Vector3(0.3, 6.0, 0.3)
	chain.mesh = link
	chain.material_override = bronze()
	chain.position = Vector3.UP * 3.0
	add_child(chain)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = SIZE * 0.5
	cylinder.height = SIZE * 0.9
	shape.shape = cylinder
	shape.position = Vector3.DOWN * SIZE * 0.4
	add_child(shape)
	# Its arm, coiled up inside it (a clapper, hanging).
	var bone := CylinderMesh.new()
	bone.top_radius = 0.28
	bone.bottom_radius = 0.22
	bone.height = 1.0
	bone.radial_segments = 6
	bone.rings = 1
	_arm = MultiMesh.new()
	_arm.transform_format = MultiMesh.TRANSFORM_3D
	_arm.mesh = bone
	_arm.instance_count = ARM_PIECES
	var arm := MultiMeshInstance3D.new()
	arm.multimesh = _arm
	arm.material_override = skin()
	add_child(arm)
	# Optimizing: its arm's posed only while it's on your screen (or lashing).
	var seen := VisibleOnScreenNotifier3D.new()
	seen.aabb = AABB(Vector3(-HANG, -SIZE - HANG - 2.0, -HANG), Vector3(HANG * 2.0, SIZE * 1.5 + HANG + 2.0, HANG * 2.0))
	seen.screen_entered.connect(func() -> void: _seen = true)
	seen.screen_exited.connect(func() -> void: _seen = false)
	add_child(seen)
	_hand = MeshInstance3D.new()
	var claw := SphereMesh.new()
	claw.radius = 0.55
	claw.height = 0.9
	_hand.mesh = claw
	_hand.material_override = skin()
	add_child(_hand)
	_pose_arm(0.0)
	_health.damaged.connect(_on_damaged)
	if not (Network.is_online() and not multiplayer.is_server()):
		_health.died.connect(func(_attacker: int, _critical: bool) -> void: Network.send_wraith_event(wraith_id, &"dead", Vector3.ZERO))


static func bronze() -> StandardMaterial3D:
	if _bronze == null:
		_bronze = StandardMaterial3D.new()
		_bronze.albedo_color = BRONZE
		# Seen from outside and in (its open mouth), and never lost in the dark.
		_bronze.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bronze.metallic = 0.2
		_bronze.roughness = 0.6
		_bronze.emission_enabled = true
		_bronze.emission = BRONZE
		_bronze.emission_energy_multiplier = 0.15
	return _bronze


static func skin() -> StandardMaterial3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.albedo_color = ARM
		_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
		_skin.roughness = 0.8
	return _skin


## Asleep it's just a bell: bullets clang off (the hurt's undone).
func _on_damaged(_amount: float, _attacker: int) -> void:
	if _awake_left <= 0.0 and not _dead:
		_health.current_health = _health.max_health
		WalkerSound.play("bell", global_position, get_tree().current_scene, 200.0, -12.0, 10.0)


## Its place's bell has tolled (every game): awake AWAKE_TIME.
func wake() -> void:
	if _dead:
		return
	_awake_left = AWAKE_TIME
	_lashed = false
	_swing = 1.0


## The lash, toward `at` (every game: the host's word).
func lash(at: Vector3) -> void:
	_lash_to = at
	_lash_t = 0.0
	WalkerSound.play("lash", global_position, get_tree().current_scene, 120.0, 0.0, 12.0)


func kill() -> void:
	if _dead:
		return
	_dead = true
	WalkerSound.play("bell", global_position, get_tree().current_scene, 400.0, 0.0, 20.0)
	BloodFX.spawn_burst(get_tree().current_scene, global_position + Vector3.DOWN * SIZE * 0.5, 1.5)
	queue_free()


func _process(delta: float) -> void:
	# It sways as it wakes, settling still again.
	if _swing > 0.0:
		_swing = maxf(_swing - delta * 0.15, 0.0)
		_bell.rotation.z = sin(Time.get_ticks_msec() * 0.003) * 0.25 * _swing
	# Anyone near: its arm hangs out, swinging (each game's own look).
	_near_left -= delta
	if _near_left <= 0.0:
		_near_left = NEAR_EVERY
		_near = _anyone_near()
	_hang = move_toward(_hang, 1.0 if _near else 0.0, delta * 0.5)
	if _lash_t >= 0.0:
		_lash_t += delta
		var out := _lash_t / LASH_TIME
		_pose_arm(clampf(out, 0.0, 1.0) if out < 1.0 else clampf(2.0 - out, 0.0, 1.0), to_local(_lash_to))
		_posed_still = false
		if out >= 2.0:
			_lash_t = -1.0
		return
	# Coiled up and posed so, or off your screen: nothing to pose.
	if (_hang <= 0.0 and _posed_still) or not _seen:
		return
	_posed_still = _hang <= 0.0
	var hang_to := Vector3.ZERO
	if _hang > 0.0:
		var t := Time.get_ticks_msec() * 0.001 * TAU / SWING_PERIOD
		var down := Vector3.DOWN.rotated(Vector3.BACK, sin(t) * SWING_ANGLE).rotated(Vector3.RIGHT, sin(t * 0.7) * SWING_ANGLE * 0.4)
		hang_to = Vector3.DOWN * SIZE * 0.6 + down * HANG
	_pose_arm(_hang, hang_to)


func _anyone_near() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(global_position) < NEAR:
			return true
	return false


func _physics_process(delta: float) -> void:
	if _dead or (Network.is_online() and not multiplayer.is_server()):
		return
	if _awake_left <= 0.0:
		return
	_awake_left -= delta
	if _lashed:
		return
	# Once a waking: at whoever's within its reach.
	var mouth := global_position + Vector3.DOWN * SIZE * 0.8
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and player.global_position.distance_to(mouth) < REACH:
			_lashed = true
			var at := player.global_position + Vector3.UP
			Network.send_wraith_event(wraith_id, &"lash", at)
			get_tree().create_timer(LASH_TIME).timeout.connect(_land_lash.bind(player, at))
			return


## The lash's end: still there, they're hit and thrown.
func _land_lash(player: PlayerMovement, at: Vector3) -> void:
	if _dead or not is_instance_valid(player) or player.is_dead() or player.global_position.distance_to(at) > 4.0:
		return
	var out := player.global_position - global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
	player.health.take_damage(HIT)
	player.shove(out * SHOVE + Vector3.UP * SHOVE * 0.3)


## The arm from the bell's mouth: coiled up inside (0) to out at `local_to`
## (1; its own space) -- the lash's target, or where it's swinging to.
func _pose_arm(out: float, local_to := Vector3.ZERO) -> void:
	var mouth := Vector3.DOWN * SIZE * 0.6
	var tip := mouth + Vector3.DOWN * 1.2
	if out > 0.0:
		tip = (mouth + Vector3.DOWN * 1.2).lerp(local_to, out)
	# Coiled up, only its first two pieces show.
	_arm.visible_instance_count = ARM_PIECES if out > 0.0 else 2
	for i in ARM_PIECES:
		var a := mouth.lerp(tip, float(i) / ARM_PIECES)
		var b := mouth.lerp(tip, float(i + 1) / ARM_PIECES)
		# A whip's curve: sagging in the middle as it goes.
		var sag := Vector3.DOWN * sin(PI * (float(i) + 0.5) / ARM_PIECES) * out * (1.0 - out) * 6.0
		var dir := (b - a)
		var length := maxf(dir.length(), 0.01)
		var turn := Basis(Quaternion(Vector3.UP, dir.normalized())) if absf(dir.normalized().dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
		_arm.set_instance_transform(i, Transform3D(turn * Basis.from_scale(Vector3(1.0, length, 1.0)), (a + b) * 0.5 + sag))
	_hand.position = tip
