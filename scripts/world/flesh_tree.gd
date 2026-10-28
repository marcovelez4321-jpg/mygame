class_name FleshTree
extends Node3D

## The Flesh Tree (the user's, 2026-10-15 -- docs/CLIMB_VISION.md): a dead
## oak of raw red muscle and bone, grown from the ritual spot, its roots
## arching round Grandma's yard. The diegetic mutation picker:
##   PODS: once a player's virus reaches Virus.POINTS_TO_MUTATE, three pale
##   glowing pods ripen near the top, each holding a random mutation that
##   player doesn't have ("something is ripening", a heartbeat). Grapple
##   one off (CarryItem, into your hand) and eat it; the other two shrivel.
##   GROWTH: it starts start_height tall and grows grow_step per mutation
##   taken (shrinks back a step when one withers on death) -- only while
##   nobody can see it, and each time its branches are laid out anew (the
##   user's: so it varies).
##   CLIMBING: thick limbs spiral up it every branch_every metres.
## Every look setting is an export: tune it live (the user's: it has to look
## perfect); rebuild() remakes it from them.
## Cheap: the whole tree is ONE mesh (two surfaces: muscle, bone -- two draw
## calls) and ONE trimesh collider, made once per growth; the creatures share
## their scenes; "can anyone see it" is the engine's own frustum notifier.
## Rule 1 (co-op): the host owns its growth (_steps, _seed) and the pods
## (CarryItems: NetEntities shows them to clients); each machine says when it
## can see the tree (_net_seen), the host regrows only when nobody can, and
## everyone builds the same tree from the same numbers (_net_build).

## Its skins (the user's, 2026-10-28): the tape worm's, the Eldritch pack's
## M9 and M4, in patches (SKIN_SHADER).
const SKIN_SHADER := preload("res://shaders/flesh_tree.gdshader")
const SKINS := ["res://art/props/PSX Creatures/Textures/tape_worm.png", "res://New assets/Eldritch/Textures/M9.png",
		"res://New assets/Eldritch/Textures/M4.png"]
const CREATURE_DIR := "res://New assets/Eldritch/Separate_Objects/"
## A few of the user's eldritch creatures (the user's: not all of them).
const CREATURE_KINDS := ["Creature_1.fbx", "Creature_4.fbx", "Creature_6.fbx", "Creature_10.fbx", "Creature_12.fbx"]
const RIPE_TEXT := "something is ripening"
const POD_COUNT := 3

@export_group("Size")
@export var start_height: float = 500.0
@export var grow_step: float = 500.0
## The trunk's width at start_height; it keeps its shape as it grows (thicker).
@export var trunk_width: float = 25.0
@export_range(0.02, 1.0, 0.01) var top_width_share: float = 0.15
@export_group("Limbs")
## The climb: a limb about every branch_every metres up, spiralling round.
@export var branch_every: float = 10.0
@export var branch_length_min: float = 14.0
@export var branch_length_max: float = 28.0
@export var branch_radius_min: float = 1.8
@export var branch_radius_max: float = 3.0
## How much a limb climbs as it reaches out (share of its length).
@export var branch_rise: float = 0.2
## Limbs ending in bare bone.
@export_range(0.0, 1.0, 0.05) var bone_share: float = 0.3
@export_group("Roots")
@export var roots: int = 7
@export var root_reach: float = 55.0
## How high a root arches before it dives back into the ground.
@export var root_arch: float = 8.0
## Two more over Grandma's house (the user's, 2026-10-19): one over its roof
## and off the front-left corner, one onto the back of the roof and down its
## back wall between the windows -- solid like the rest (walk them, grapple
## them). Their paths in the house's own space at real size (GrandmasHouse:
## front -Z, the ground at 0; scaled by its SIZE, radii too), from where they leave the ground behind it to where they
## dive back in; [points, radius leaving the trunk, radius at the end].
const HOUSE_ROOTS := [
	[[Vector3(-2.5, 1.0, 14.0), Vector3(-2.8, 4.5, 8.0), Vector3(-3.0, 7.4, 4.6), Vector3(-3.0, 8.95, 2.0),
		Vector3(-3.1, 10.6, 0.0), Vector3(-3.3, 8.95, -2.0), Vector3(-3.8, 7.0, -4.3), Vector3(-5.4, 4.5, -5.0),
		Vector3(-6.6, 1.5, -6.0), Vector3(-7.2, -1.5, -6.6)], 2.0, 0.4],
	[[Vector3(1.2, 1.5, 15.0), Vector3(1.4, 6.0, 9.5), Vector3(1.5, 8.45, 2.5), Vector3(1.5, 7.0, 4.6),
		Vector3(1.6, 5.0, 4.7), Vector3(1.7, 2.5, 4.75), Vector3(1.9, 0.3, 4.9), Vector3(2.2, -1.5, 5.4)], 1.9, 0.35],
]
## Fed (the user's, Feed the Tree: two more draping roots over the house, four
## in all): the first two's mirror images, on the other sides.
const FED_ROOTS := [
	[[Vector3(2.8, 1.0, 14.0), Vector3(3.2, 4.5, 8.0), Vector3(3.6, 7.4, 4.6), Vector3(3.8, 8.95, 2.0),
		Vector3(3.9, 10.6, 0.0), Vector3(4.0, 8.95, -2.0), Vector3(4.4, 7.0, -4.3), Vector3(5.6, 4.5, -5.0),
		Vector3(6.7, 1.5, -6.0), Vector3(7.3, -1.5, -6.6)], 1.8, 0.35],
	[[Vector3(-0.8, 1.5, 15.0), Vector3(-0.6, 6.0, 9.5), Vector3(-0.5, 8.45, 2.5), Vector3(-0.5, 7.0, 4.6),
		Vector3(-0.6, 5.0, 4.7), Vector3(-0.7, 2.5, 4.75), Vector3(-0.9, 0.3, 4.9), Vector3(-1.2, -1.5, 5.4)], 1.7, 0.3],
]
@export_group("Shape")
## How crooked everything is (share of a part's thickness).
@export var gnarl: float = 0.35
## Sides round every limb (PS1: few).
@export var sides: int = 8
@export_group("Look")
@export var muscle_tint: Color = Color(1.0, 1.0, 1.0)
## Its skins' patches: metres across one, and how softly they blend at their
## edges (0: sharp, 1: very soft).
@export var skin_patch_metres: float = 18.0
@export var skin_blend: float = 0.35
@export var bone_color: Color = Color(0.86, 0.8, 0.68)
## Metres one repeat of the muscle texture covers.
@export var texture_metres: float = 6.0
@export_group("Creatures")
## (The user's: none for now -- the models came off the tree.)
@export var creatures: int = 0
@export var creature_size_min: float = 3.0
@export var creature_size_max: float = 9.0
@export var creature_seen_range: float = 1500.0
@export_group("Towers")
## The Zombies Stacks (the user's, 2026-10-27; docs/ZOMBIES_DIRECTION.md):
## standing in the middle of a cluster of towers, its branches are tentacles
## twisting out to the towers' corners and gripping them round like a squid's
## -- one in each band of grip_heights at every corner facing it -- and the
## mutation orbs grow at the end of every one (orbs_everywhere). Empty: the
## open world's oak.
@export var grip_towers: Array[AABB] = []
## Bands of height (min, max metres) a branch grips a corner at.
@export var grip_heights := PackedVector2Array()
## A branch's thickness leaving the trunk, and at its tip.
@export var grip_radius := Vector2(4.0, 1.2)
## A branch carrying on from where a bridge runs into the trunk (global; INF:
## none): from walkway_from (the bridge's end) it wraps round the trunk at
## that height, flat on top, walkable, then out to walkway_to and into the
## wall there.
@export var walkway_from := Vector3.INF
@export var walkway_to := Vector3.INF
@export var walkway_radius: float = 3.0
## Ripe: an orb at every branch's tip, each a random mutation that player
## doesn't have (not the open world's three near the top).
@export var orbs_everywhere: bool = false
## How close you have to be to read an orb's mutation.
@export var orb_read_range: float = 15.0
## The spiral of limbs starts this high (the open world's from 12 m; the
## Stacks': only in its crown, above the towers).
@export var limbs_from: float = 12.0
## The flare at its foot: this much wider at the ground, easing off over
## flare_reach metres (0: a twelfth of its height, the open world's).
@export var flare_share: float = 0.6
@export var flare_reach: float = 0.0
## Set down on the ground under it as it starts (off: it's placed exactly).
@export var sit_on_ground: bool = true
@export_group("Testing")
## The user's, for testing: three pods are ripe the moment the scene starts.
@export var pods_on_start: bool = true

## The host's: mutations grown (the tree's height) and the layout's seed.
## Static: kept while the level reloads on death.
static var _steps := 0
static var _seed := 1
static var _tree: FleshTree

var _built_steps := -1
var _built_seed := -1
var _pods: Array[CarryItem] = []
## Where pods hang: near the top, off three different limbs.
var _pod_spots: Array[Vector3] = []
## Host: peer -> can see the tree. Everyone: whether this machine can.
var _seen := {}
var _seen_here := false
var _check_left := 0.0
var _mesh: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _creatures: Node3D
var _notifier: VisibleOnScreenNotifier3D
var _sound: AudioStreamPlayer

static var _muscle: ShaderMaterial
static var _bone: StandardMaterial3D
static var _creature_scenes := {}
static var _beat: AudioStreamWAV


# ---- From outside (Virus, PlayerHand) ------------------------------------------------

## Someone's virus is full: three pods ripen (if none are already), rolled
## from what that player doesn't have. The host's.
static func ripen_for(player: PlayerMovement) -> void:
	if _tree == null or not _tree._decides() or not _tree._pods.is_empty():
		return
	var pool: Array[StringName] = []
	if player and player.virus:
		pool = player.virus.missing()
	else:
		for mutation: StringName in Virus.MUTATIONS:
			pool.append(mutation)
	if pool.is_empty():
		return
	if _tree.orbs_everywhere:
		# An orb on every branch (the user's): each a random one of them.
		for i in _tree._pod_spots.size():
			_tree._grow_pod(pool.pick_random(), i)
		_tree._net_ripened.rpc()
		return
	# The newest mutations first (the user's): the pool is in the order they
	# were made (Virus.MUTATIONS), so the last made come up first.
	pool.reverse()
	for i in mini(POD_COUNT, pool.size()):
		_tree._grow_pod(pool[i], i)
	_tree._net_ripened.rpc()


## A pod was grappled off: the others stay till one's eaten (the user's:
## you read it in your hand first -- mutation_eaten()).
## Remade (for everyone, once nobody's looking): fed, its new roots.
static func refresh() -> void:
	if _tree and is_instance_valid(_tree):
		_tree._built_steps = -1


## Raw meat (a big one's: not rotten, not cooked) in player's hand.
static func raw_in_hand(player: PlayerMovement) -> bool:
	return player != null and player.hand.held_kind() == Backpack.Kind.MEAT and not CarryItem.is_rotten_data(player.hand.data)


## Its body, as F finds it: Feed the Tree (the user's: hold the meat, F on
## the trunk -- the bark takes it). The host decides (Quests.fed).
class Trunk extends StaticBody3D:
	var use_prompt: String = "Feed it"

	func _ready() -> void:
		add_to_group(PlayerMovement.USABLE_GROUP)

	func can_use() -> bool:
		return Quests.state(Quests.FEED) == Quests.State.ACTIVE and not Quests.tree_fed() \
				and FleshTree.raw_in_hand(PlayerMovement.local_player(get_tree()))

	func takes_held(_player: Node) -> bool:
		return can_use()

	func use_by(player: Node) -> void:
		var p := player as PlayerMovement
		if p == null or (Network.is_online() and not multiplayer.is_server()) or not FleshTree.raw_in_hand(p):
			return
		if Quests.state(Quests.FEED) != Quests.State.ACTIVE or Quests.tree_fed():
			return
		p.hand.use_up()
		Quests.fed(p)


static func pod_taken(pod: CarryItem) -> void:
	if _tree == null:
		return
	pod.remove_meta(&"on_tree") # (the hand flies it in; it stays frozen till then)
	_tree._pods.erase(pod)


## A pod was eaten: the ones left on the tree shrivel and fade.
static func mutation_eaten() -> void:
	if _tree == null:
		return
	for other in _tree._pods:
		if is_instance_valid(other):
			other.shrivel()
	_tree._pods.clear()


## A mutation taken (+1) or withered (-1): it'll grow (or shrink) a step,
## with a new layout, once nobody can see it.
static func grow(steps: int) -> void:
	_steps = maxi(_steps + steps, 0)
	_seed = randi() % 1000000 + 1


## A pod: a translucent pale-pink glowing sac, the mutation curled inside.
static func pod_model(mutation: StringName) -> Node3D:
	var holder := Node3D.new()
	var sac := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	sac.mesh = sphere
	sac.material_override = _pod_skin()
	sac.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(sac)
	holder.add_child(_inside_of(mutation))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.62, 0.7)
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	glow.shadow_enabled = false
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 120.0
	glow.distance_fade_length = 40.0
	holder.add_child(glow)
	return holder


# ---- Life -----------------------------------------------------------------------------

func _ready() -> void:
	_tree = self
	_sound = AudioStreamPlayer.new()
	_sound.bus = &"Master"
	add_child(_sound)
	_notifier = VisibleOnScreenNotifier3D.new()
	add_child(_notifier)
	_notifier.screen_entered.connect(_on_seen.bind(true))
	_notifier.screen_exited.connect(_on_seen.bind(false))
	await get_tree().physics_frame
	await get_tree().physics_frame
	if sit_on_ground:
		_sit_on_ground()
	_build(_steps, _seed)
	# Built after the navmesh was read: read again, so nothing walks into it.
	var navigation := get_tree().current_scene.get_node_or_null(^"WorldNavigation")
	if navigation and navigation.has_method(&"refresh_static"):
		navigation.call(&"refresh_static")
	if not _decides():
		_net_ask.rpc_id(1)
	elif pods_on_start:
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			ripen_for(PlayerMovement.local_player(get_tree())))


func _exit_tree() -> void:
	if _tree == self:
		_tree = null


## Host, once a second: grown (or shrunk) and nobody sees it -> remade, for
## everyone.
func _process(delta: float) -> void:
	if not _decides() or _mesh == null:
		return # (not built the first time yet)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 1.0
	if _built_steps == _steps and _built_seed == _seed:
		return
	if _seen_here or _seen.values().has(true):
		return
	_build(_steps, _seed)
	if Network.is_online():
		_net_build.rpc(_steps, _seed)


func _on_seen(on: bool) -> void:
	_seen_here = on
	if not _decides():
		_net_seen.rpc_id(1, on)


func _sit_on_ground() -> void:
	var from := global_position + Vector3.UP * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 500.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = (hit.position as Vector3) + Vector3.DOWN * 2.0 # sunk in a little


# ---- Building it --------------------------------------------------------------------------

## Remade from the exports (for tuning live: call it from the inspector's
## script or the remote tree).
func rebuild() -> void:
	_build(_steps, _seed)


func _build(steps: int, layout_seed: int) -> void:
	_built_steps = steps
	_built_seed = layout_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var height := start_height + grow_step * steps
	var scale_up := height / start_height
	var base_radius := trunk_width * 0.5 * scale_up
	var muscle := SurfaceTool.new()
	muscle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var limbs: Array[PackedVector3Array] = []
	var tips: Array[Vector3] = []
	var any_bone := false

	# The trunk: a crooked column, flared at the foot, tapering to the crown.
	var trunk := PackedVector3Array()
	var trunk_radii := PackedFloat32Array()
	var drift := Vector2.ZERO
	var rings := maxi(int(height / 12.0), 8)
	for i in rings + 1:
		var t := float(i) / rings
		drift += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * base_radius * gnarl * 0.15
		drift = drift.limit_length(base_radius * gnarl * 2.0)
		trunk.append(Vector3(drift.x, t * height, drift.y))
		var flare_over := flare_reach if flare_reach > 0.0 else height / 12.0
		var flare := 1.0 + flare_share * pow(1.0 - minf(t * height / flare_over, 1.0), 2.0)
		trunk_radii.append(lerpf(base_radius, base_radius * top_width_share, pow(t, 0.8)) * flare)
	_tube(muscle, trunk, trunk_radii, Vector3.RIGHT)

	# The limbs: spiralling up, every branch_every metres.
	var angle := rng.randf() * TAU
	var y := limbs_from
	while y < height - 6.0:
		angle += deg_to_rad(137.5) + rng.randf_range(-0.4, 0.4) # the golden angle round
		var t := y / height
		var at := _along(trunk, y, height)
		var trunk_r := lerpf(base_radius, base_radius * top_width_share, pow(t, 0.8))
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var length := rng.randf_range(branch_length_min, branch_length_max) * lerpf(1.2, 0.7, t)
		var radius := rng.randf_range(branch_radius_min, branch_radius_max)
		var bare := rng.randf() < bone_share
		var limb := PackedVector3Array()
		var limb_radii := PackedFloat32Array()
		var start := at + out * trunk_r * 0.7
		for k in 6:
			var u := k / 5.0
			var crook := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)) * radius * gnarl * u
			limb.append(start + out * (trunk_r * 0.3 + length * u) + Vector3.UP * (sin(u * PI * 0.8) * length * branch_rise) + crook)
			limb_radii.append(lerpf(radius, radius * 0.35, u))
		if bare:
			any_bone = true
			# Muscle out to two-thirds, bare bone beyond.
			_tube(muscle, limb.slice(0, 5), limb_radii.slice(0, 5), Vector3.UP)
			var bone_radii := PackedFloat32Array([limb_radii[3] * 0.7, limb_radii[4] * 0.6, limb_radii[5] * 0.5])
			_tube(bone, limb.slice(3, 6), bone_radii, Vector3.UP, true)
		else:
			_tube(muscle, limb, limb_radii, Vector3.UP, true)
		limbs.append(limb)
		tips.append(limb[limb.size() - 1])
		y += branch_every + rng.randf_range(-2.0, 2.0)

	# The roots: arching out round the yard and diving back in.
	for i in roots:
		var root_angle := TAU * i / maxi(roots, 1) + rng.randf_range(-0.3, 0.3)
		var way := Vector3(cos(root_angle), 0.0, sin(root_angle))
		var reach := root_reach * scale_up * rng.randf_range(0.75, 1.15)
		var root := PackedVector3Array()
		var root_radii := PackedFloat32Array()
		for k in 7:
			var u := k / 6.0
			var crook := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * base_radius * gnarl * 0.3 * u
			root.append(way * (base_radius * 0.6 + reach * u) + Vector3.UP * (base_radius * 0.3 * (1.0 - u) + sin(u * PI) * root_arch * scale_up - u * 4.0) + crook)
			root_radii.append(lerpf(base_radius * 0.35, base_radius * 0.06, u))
		_tube(muscle, root, root_radii, Vector3.UP, true)
	_house_roots(muscle, base_radius)

	# The Stacks': tentacles out to the towers' corners, gripping them.
	var grip_tips := _grip_branches(rng, muscle, trunk, height, base_radius)
	# Pods hang off the three highest limbs (round different sides) -- or
	# (orbs_everywhere) one off the tip of every gripping branch.
	_pod_spots.clear()
	if orbs_everywhere and not grip_tips.is_empty():
		for tip in grip_tips:
			_pod_spots.append(tip + Vector3.DOWN * 1.2)
	for i in range(tips.size() - 1, -1, -1):
		if not _pod_spots.is_empty() and (orbs_everywhere or _pod_spots.size() >= POD_COUNT):
			break
		_pod_spots.append(tips[i] + Vector3.DOWN * 1.2)

	var mesh := ArrayMesh.new()
	muscle.generate_normals()
	muscle.commit(mesh)
	mesh.surface_set_material(0, _muscle_material())
	if any_bone:
		bone.generate_normals()
		bone.commit(mesh)
		mesh.surface_set_material(1, _bone_material())
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_mesh)
		_body = Trunk.new()
		add_child(_body)
		_shape = CollisionShape3D.new()
		_body.add_child(_shape)
	_mesh.mesh = mesh
	_shape.shape = mesh.create_trimesh_shape()
	var reach_out := maxf(root_reach * scale_up * 1.2, branch_length_max * 1.2 + base_radius)
	for tip in grip_tips:
		reach_out = maxf(reach_out, Vector2(tip.x, tip.z).length() + 20.0)
	_notifier.aabb = AABB(Vector3(-reach_out, -10.0, -reach_out), Vector3(reach_out * 2.0, height + 20.0, reach_out * 2.0))
	_place_creatures(rng, trunk, limbs, base_radius, height)
	# Ripe pods move with the limbs.
	for i in _pods.size():
		if is_instance_valid(_pods[i]) and i < _pod_spots.size():
			_pods[i].global_position = to_global(_pod_spots[i])


## The roots over Grandma's house (HOUSE_ROOTS), if she has one here: out of
## the trunk's foot toward it, then along their paths, smoothed.
func _house_roots(muscle: SurfaceTool, base_radius: float) -> void:
	var house := get_tree().get_first_node_in_group(&"grandmas_house") as Node3D
	if house == null:
		return
	for spec: Array in HOUSE_ROOTS + (FED_ROOTS if Quests.tree_fed() else []):
		var path := PackedVector3Array()
		for point: Vector3 in spec[0]:
			path.append(to_local(house.to_global(point * GrandmasHouse.SIZE)))
		var toward := Vector3(path[0].x, 0.0, path[0].z).normalized()
		path.insert(0, toward * base_radius * 0.6 + Vector3.UP * base_radius * 0.3)
		var smooth := _smoothed(path, 5)
		var radii := PackedFloat32Array()
		for i in smooth.size():
			var u := float(i) / maxi(smooth.size() - 1, 1)
			radii.append(lerpf(spec[1], spec[2], pow(u, 0.6)) * GrandmasHouse.SIZE)
		_tube(muscle, smooth, radii, Vector3.UP, true)


## The Stacks' tentacle branches (grip_towers): out of the trunk, twisting
## across the air to a tower's corner, laid along the face it comes to, round
## the corner and onto the other face, the tip curling off it -- one in each
## band of grip_heights, at every corner with a face toward the tree. Left
## out: any whose way there runs through a tower. Then the walkway (walkway_to).
## The tips, in its own space (where the orbs hang).
func _grip_branches(rng: RandomNumberGenerator, muscle: SurfaceTool, trunk: PackedVector3Array, height: float, base_radius: float) -> Array[Vector3]:
	var tips: Array[Vector3] = []
	if grip_towers.is_empty():
		return tips
	var boxes: Array[AABB] = []
	for box in grip_towers:
		boxes.append(AABB(box.position - global_position, box.size).grow(-0.5))
	for box in boxes:
		var middle := box.get_center()
		for cx: float in [box.position.x, box.end.x]:
			for cz: float in [box.position.z, box.end.z]:
				var corner := Vector3(cx, 0.0, cz)
				var face_x := Vector3(signf(cx - middle.x), 0.0, 0.0)
				var face_z := Vector3(0.0, 0.0, signf(cz - middle.z))
				var to_tree := -corner
				to_tree.y = 0.0
				if face_x.dot(to_tree) <= 0.0 and face_z.dot(to_tree) <= 0.0:
					continue # (round the back of its tower)
				var lay := face_x if face_x.dot(to_tree) >= face_z.dot(to_tree) else face_z
				var wrap := face_z if lay == face_x else face_x
				for band in grip_heights:
					# (A few tries: a twist that swings it through a tower is rerolled.)
					var path := PackedVector3Array()
					for attempt in 5:
						var top := minf(rng.randf_range(band.x, band.y), box.end.y - 10.0)
						if top < band.x:
							break
						path = _grip_path(rng, corner, lay, wrap, top, trunk, height, base_radius, boxes)
						if not path.is_empty():
							break
					if path.is_empty():
						continue
					var radii := PackedFloat32Array()
					for i in path.size():
						var u := float(i) / maxi(path.size() - 1, 1)
						radii.append(lerpf(grip_radius.x, grip_radius.y, pow(u, 0.7)))
					_tube(muscle, path, radii, Vector3.UP, true)
					tips.append(path[path.size() - 1])
	if walkway_to.is_finite() and walkway_from.is_finite():
		_walkway(rng, muscle, trunk, height, base_radius)
	return tips


## One gripping branch's path (empty: its way runs through a tower).
func _grip_path(rng: RandomNumberGenerator, corner: Vector3, lay: Vector3, wrap: Vector3, top: float,
		trunk: PackedVector3Array, height: float, base_radius: float, boxes: Array[AABB]) -> PackedVector3Array:
	var hug := grip_radius.y + 0.8
	# Along the face it comes to, round the corner, onto the other, sliding
	# down as it wraps; the tip curling off the wall.
	var onto := corner + lay * (hug + 0.6) - wrap * rng.randf_range(6.0, 14.0) + Vector3.UP * (top + 5.0)
	var round_it := corner + (lay + wrap).normalized() * (hug + 1.0) + Vector3.UP * (top + 1.5)
	var past := corner + wrap * hug - lay * rng.randf_range(4.0, 9.0) + Vector3.UP * (top - 2.0)
	var curl := past + wrap * 2.0 - lay * 2.5 + Vector3.UP * 1.5
	# Out of the trunk lower down (it reaches up to its grip).
	var low := clampf(top * rng.randf_range(0.55, 0.85), 6.0, height * 0.95)
	var axis := _along(trunk, low, height)
	var out := Vector3(onto.x - axis.x, 0.0, onto.z - axis.z).normalized()
	var start := axis + out * _trunk_radius(low, height, base_radius) * 0.7
	for box in boxes:
		if box.intersects_segment(start, onto):
			return PackedVector3Array()
	# Twisting on the way, like a tentacle feeling for it.
	var side := out.cross(Vector3.UP).normalized()
	var span := start.distance_to(onto)
	var twist := span * rng.randf_range(0.08, 0.16) * (1.0 if rng.randf() < 0.5 else -1.0)
	var bend_a := start.lerp(onto, 0.33) + side * twist + Vector3.UP * span * 0.05
	var bend_b := start.lerp(onto, 0.66) - side * twist * 0.7
	var path := _smoothed(PackedVector3Array([start, bend_a, bend_b, onto, round_it, past, curl]), 4)
	for i in path.size() - 1:
		for box in boxes:
			if i < path.size() - 8 and box.intersects_segment(path[i], path[i + 1]):
				return PackedVector3Array() # (the twist swung it through a tower)
	return path


## The walkway: from the bridge's end (walkway_from), round the trunk hugging
## it at that height (the way round chosen at random), then out to
## walkway_to and into the wall there; its top at the bridge's height.
func _walkway(rng: RandomNumberGenerator, muscle: SurfaceTool, trunk: PackedVector3Array, height: float, base_radius: float) -> void:
	var from := to_local(walkway_from) + Vector3.DOWN * walkway_radius
	var to := to_local(walkway_to) + Vector3.DOWN * walkway_radius
	var y := from.y
	var axis := _along(trunk, y, height)
	axis.y = y
	var hug := _trunk_radius(y, height, base_radius) + walkway_radius * 0.4
	var a0 := atan2(from.z - axis.z, from.x - axis.x)
	var a1 := atan2(to.z - axis.z, to.x - axis.x)
	var sweep := wrapf(a1 - a0, -PI, PI)
	if absf(absf(sweep) - PI) < 0.3:
		sweep = absf(sweep) * (1.0 if rng.randf() < 0.5 else -1.0)
	# (Starting out under the bridge's end.)
	var points := PackedVector3Array([axis + Vector3(cos(a0), 0.0, sin(a0)) * (hug + 6.0)])
	var steps := maxi(int(absf(sweep) * hug / 8.0), 3)
	for k in steps + 1:
		var a := a0 + sweep * float(k) / steps
		points.append(axis + Vector3(cos(a), 0.0, sin(a)) * hug)
	var out := Vector3(cos(a1), 0.0, sin(a1))
	points.append(axis + out * (hug + (Vector2(to.x - axis.x, to.z - axis.z).length() - hug) * 0.5))
	points.append(Vector3(to.x, y, to.z) + out * 1.5)
	var path := _smoothed(points, 3)
	for i in path.size():
		path[i].y = y # (flat: walkable all the way)
	var radii := PackedFloat32Array()
	for i in path.size():
		radii.append(walkway_radius)
	_tube(muscle, path, radii, Vector3.UP)

## The trunk's radius `y` up (no flare).
func _trunk_radius(y: float, height: float, base_radius: float) -> float:
	return lerpf(base_radius, base_radius * top_width_share, pow(clampf(y / height, 0.0, 1.0), 0.8))


## `points` as a smooth curve through them (Catmull-Rom), `steps` a stretch.
static func _smoothed(points: PackedVector3Array, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := points.size()
	for i in count - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, count - 1)]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(points[count - 1])
	return out


## About `creatures` of the user's eldritch things grown into the trunk and
## the limbs, at random sizes.
func _place_creatures(rng: RandomNumberGenerator, trunk: PackedVector3Array, limbs: Array[PackedVector3Array], base_radius: float, height: float) -> void:
	if _creatures:
		_creatures.queue_free()
	_creatures = Node3D.new()
	add_child(_creatures)
	for i in creatures:
		var scene := _creature_scene(CREATURE_KINDS[rng.randi() % CREATURE_KINDS.size()])
		if scene == null:
			continue
		var at: Vector3
		var normal: Vector3
		if i % 2 == 0 or limbs.is_empty():
			var y := rng.randf_range(height * 0.03, height * 0.9)
			var around := rng.randf() * TAU
			normal = Vector3(cos(around), 0.0, sin(around))
			var trunk_r := lerpf(base_radius, base_radius * top_width_share, pow(y / height, 0.8))
			at = _along(trunk, y, height) + normal * trunk_r * 0.9
		else:
			var limb: PackedVector3Array = limbs[rng.randi() % limbs.size()]
			at = limb[rng.randi_range(1, limb.size() - 2)]
			normal = Vector3.UP
		var creature := scene.instantiate() as Node3D
		_creatures.add_child(creature)
		var box := BackpackView._bounds(creature)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var size := rng.randf_range(creature_size_min, creature_size_max)
		var side := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var lie := Basis(side, normal, side.cross(normal)).rotated(normal, rng.randf() * TAU)
		creature.transform = Transform3D(lie.scaled(Vector3.ONE * size / maxf(longest, 0.001)), at)
		for node in creature.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.visibility_range_end = creature_seen_range


## Where the trunk is `y` up.
static func _along(trunk: PackedVector3Array, y: float, height: float) -> Vector3:
	var f := clampf(y / height, 0.0, 1.0) * (trunk.size() - 1)
	var i := mini(int(f), trunk.size() - 2)
	return trunk[i].lerp(trunk[i + 1], f - i)


## A tube along `points` (`radii` at each), `sides` round, UVs in
## texture_metres; `cap` closes its far end in a point.
func _tube(tool: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, reference: Vector3, cap: bool = false) -> void:
	var count := points.size()
	if count < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var along := 0.0
	var vs := PackedFloat32Array()
	for i in count:
		var forward := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := forward.cross(reference)
		if side.length_squared() < 0.0001:
			side = forward.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(forward).normalized()
		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(points[i] + (side * cos(a) + up * sin(a)) * radii[i])
		rings.append(ring)
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		vs.append(along / texture_metres)
	for i in count - 1:
		var round_u := TAU * radii[i] / texture_metres
		for s in sides:
			var n := (s + 1) % sides
			var u0 := round_u * s / sides
			var u1 := round_u * (s + 1) / sides
			_quad(tool, rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s],
					Vector2(u0, vs[i]), Vector2(u1, vs[i]), Vector2(u1, vs[i + 1]), Vector2(u0, vs[i + 1]))
	if cap:
		var tip := points[count - 1] + (points[count - 1] - points[count - 2]).normalized() * radii[count - 1]
		var last := rings[count - 1]
		for s in sides:
			tool.set_uv(Vector2(0.5, vs[count - 1]))
			tool.add_vertex(last[s])
			tool.set_uv(Vector2(0.5, vs[count - 1]))
			tool.add_vertex(last[(s + 1) % sides])
			tool.set_uv(Vector2(0.5, vs[count - 1] + 0.2))
			tool.add_vertex(tip)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for pair: Array in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		tool.set_uv(pair[1])
		tool.add_vertex(pair[0])


## Its skin: three in patches blending into each other (shaders/
## flesh_tree.gdshader; the user's, 2026-10-28: the bright flesh stood out).
## Fleshy, not shiny: matte, a dark red rim where it turns away from you.
func _muscle_material() -> ShaderMaterial:
	if _muscle == null:
		_muscle = ShaderMaterial.new()
		_muscle.shader = SKIN_SHADER
		for pair: Array in [[&"worm_skin", SKINS[0]], [&"veined_skin", SKINS[1]], [&"raw_skin", SKINS[2]]]:
			if ResourceLoader.exists(pair[1]):
				_muscle.set_shader_parameter(pair[0], load(pair[1]) as Texture2D)
	_muscle.set_shader_parameter(&"tint", muscle_tint)
	_muscle.set_shader_parameter(&"patch_metres", skin_patch_metres)
	_muscle.set_shader_parameter(&"blend", skin_blend)
	return _muscle


func _bone_material() -> StandardMaterial3D:
	if _bone == null:
		_bone = StandardMaterial3D.new()
		_bone.roughness = 0.8
		_bone.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bone.albedo_color = bone_color
	return _bone


static func _creature_scene(file: String) -> PackedScene:
	var path := CREATURE_DIR + file
	if not _creature_scenes.has(path):
		_creature_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _creature_scenes[path]


# ---- Pods ----------------------------------------------------------------------------------

func _grow_pod(mutation: StringName, slot: int) -> void:
	if slot >= _pod_spots.size():
		return
	var pod := CarryItem.spawn(self, to_global(_pod_spots[slot]), {kind = CarryItem.POD, mutation = mutation})
	pod.set_meta(&"on_tree", true)
	pod.set_meta(&"net_big", true) # seen by clients from well below (NetEntities)
	pod.set_meta(&"highlight_range", orb_read_range) # read up close (the user's: not from the ground)
	pod.freeze = true
	_pods.append(pod)


static var _pod_material: StandardMaterial3D
static var _inside_material: StandardMaterial3D


static func _pod_skin() -> StandardMaterial3D:
	if _pod_material == null:
		_pod_material = StandardMaterial3D.new()
		_pod_material.albedo_color = Color(1.0, 0.78, 0.82, 0.45)
		_pod_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pod_material.emission_enabled = true
		_pod_material.emission = Color(1.0, 0.55, 0.65)
		_pod_material.emission_energy_multiplier = 0.8
		_pod_material.roughness = 0.2
		_pod_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _pod_material


## The mutation, curled up dark inside the sac (simple shapes for now).
static func _inside_of(mutation: StringName) -> Node3D:
	if _inside_material == null:
		_inside_material = StandardMaterial3D.new()
		_inside_material.albedo_color = Color(0.35, 0.04, 0.06)
	var holder := Node3D.new()
	var parts: Array = []
	match mutation:
		Virus.WINGS:
			parts = [[_box(Vector3(0.35, 0.02, 0.16)), Vector3(-0.15, 0.0, 0.0), 20.0], [_box(Vector3(0.35, 0.02, 0.16)), Vector3(0.15, 0.0, 0.0), -20.0]]
		Virus.CHITIN:
			parts = [[_box(Vector3(0.3, 0.06, 0.2)), Vector3(0.0, -0.1, 0.0), 0.0], [_box(Vector3(0.26, 0.06, 0.18)), Vector3(0.0, 0.0, 0.0), 8.0], [_box(Vector3(0.22, 0.06, 0.16)), Vector3(0.0, 0.1, 0.0), -8.0]]
		Virus.ROACH_GUT:
			var gut := TorusMesh.new()
			gut.inner_radius = 0.08
			gut.outer_radius = 0.18
			parts = [[gut, Vector3.ZERO, 30.0]]
		Virus.RAT_LUNGS:
			parts = [[_ball(0.12), Vector3(-0.1, 0.0, 0.0), 0.0], [_ball(0.12), Vector3(0.1, 0.0, 0.0), 0.0]]
		Virus.MANTIS:
			parts = [[_stick(0.35, 0.03), Vector3(-0.08, 0.0, 0.0), 35.0], [_stick(0.35, 0.03), Vector3(0.08, 0.0, 0.0), -35.0]]
		Virus.SPINNERETS:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.08
			cone.height = 0.22
			parts = [[cone, Vector3(-0.08, 0.0, 0.0), 0.0], [cone, Vector3(0.08, 0.0, 0.0), 0.0], [cone, Vector3(0.0, 0.0, 0.1), 0.0]]
		Virus.TENDRILS:
			parts = [[_stick(0.4, 0.02), Vector3(-0.06, 0.0, 0.0), 15.0], [_stick(0.4, 0.02), Vector3(0.0, 0.0, 0.0), 0.0], [_stick(0.4, 0.02), Vector3(0.06, 0.0, 0.0), -15.0]]
		Virus.WHIP:
			var coil := TorusMesh.new()
			coil.inner_radius = 0.12
			coil.outer_radius = 0.16
			parts = [[coil, Vector3.ZERO, 70.0]]
		Virus.SEEDED:
			# A seed with five shoots.
			parts = [[_ball(0.1), Vector3(0.0, -0.08, 0.0), 0.0], [_stick(0.3, 0.02), Vector3(-0.08, 0.06, 0.0), 25.0], [_stick(0.32, 0.02), Vector3(-0.04, 0.08, 0.0), 10.0], [_stick(0.34, 0.02), Vector3(0.0, 0.09, 0.0), 0.0], [_stick(0.32, 0.02), Vector3(0.04, 0.08, 0.0), -10.0], [_stick(0.3, 0.02), Vector3(0.08, 0.06, 0.0), -25.0]]
	for part: Array in parts:
		var shape := MeshInstance3D.new()
		shape.mesh = part[0]
		shape.material_override = _inside_material
		shape.position = part[1]
		shape.rotation_degrees = Vector3(0.0, 0.0, part[2])
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(shape)
	return holder


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _ball(radius: float) -> SphereMesh:
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	return ball


static func _stick(length: float, radius: float) -> CapsuleMesh:
	var stick := CapsuleMesh.new()
	stick.radius = radius
	stick.height = length
	return stick


# ---- Co-op ----------------------------------------------------------------------------------

func _decides() -> bool:
	return not Network.is_online() or multiplayer.is_server()


## A client tells the host whether it can see the tree.
@rpc("any_peer", "call_remote", "reliable")
func _net_seen(on: bool) -> void:
	if _decides():
		_seen[multiplayer.get_remote_sender_id()] = on


## A client just arrived: what tree to build.
@rpc("any_peer", "call_remote", "reliable")
func _net_ask() -> void:
	if _decides():
		_net_build.rpc_id(multiplayer.get_remote_sender_id(), _steps, _seed)


@rpc("authority", "call_remote", "reliable")
func _net_build(steps: int, layout_seed: int) -> void:
	_steps = steps
	_seed = layout_seed
	_build(steps, layout_seed)


## Pods ripened: everyone's told, and hears it.
@rpc("authority", "call_local", "reliable")
func _net_ripened() -> void:
	MapIO.show_message(get_tree(), RIPE_TEXT)
	if _beat == null:
		_beat = _make_beat()
	_sound.stream = _beat
	_sound.play()


## A deep, wet heartbeat (a stand-in sound): three slow beats.
static func _make_beat() -> AudioStreamWAV:
	var rate := 22050
	var frames := int(3.2 * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / rate
		var sample := 0.0
		for at: float in [0.0, 0.35, 1.1, 1.45, 2.2, 2.55]:
			var u := t - at
			if u >= 0.0 and u < 0.5:
				sample += sin(TAU * 42.0 * u + sin(TAU * 7.0 * u) * 2.0) * exp(-u * 9.0) * 0.8
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
