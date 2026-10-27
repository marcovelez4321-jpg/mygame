class_name QuestNpc
extends StaticBody3D

## A quest NPC (the user's, 2026-10-27): walk up and F ("[F] Talk") --
## QuestTalk's conversation, their lines in dialogue/<role>.tres. Each role
## brings its own place with it:
##   SHRINE -- the cultist, robed (Cult), at the cult's flesh-root altar.
##   BOUNTY -- the stranger, at his own fire; killable: his note on his body.
##   MARA -- the climber's sister, walking beside the torn-banner trader.
##   FANATIC -- on the 1.4 km tower with his sled, his junk-pile bomb growing
##     as he climbs; talked down, his explosives laid out on the sled to buy
##     (FANATIC_PRICES); threatened or hurt, he tears his coat open, beeps
##     KAMIKAZE_TIME and blows (KAMIKAZE_DAMAGE within KAMIKAZE_RADIUS).
## The models are picks the user can change (MODELS).
## Rule 1 (co-op): the host's (NetEntities: made in code); every game talks
## its own talks, the host decides (Quests).

const MODELS := {
	&"shrine": "res://art/characters/Characters_psx/Models/Male/Character_12.fbx",
	&"bounty": "res://art/characters/Characters_psx/Models/Male/Character_09.fbx",
	&"mara": "res://art/characters/Characters_psx/Models/Female/Character_Female_05.fbx",
	&"fanatic": "res://art/characters/Characters_psx/Models/Male/Character_28_HM.fbx",
}
const IDLE := "res://art/animations/Idle.res"
const WALK := "res://art/animations/Walk.res"
const HEALTH := {&"bounty": 60.0, &"fanatic": 80.0}
## Mara keeps this far off her trader's side, walking at most this fast.
const BESIDE := Vector3(2.2, 0.0, 0.8)
const MARA_SPEED := 3.0
const KAMIKAZE_TIME := 2.0
const KAMIKAZE_DAMAGE := 300.0
const KAMIKAZE_RADIUS := 25.0
## Talked down (the user's: cheap -- half the traders' price), on his sled.
const FANATIC_PRICES := [[13, 2], [12, 2], [9, 20]] # [TraderGoods.GOODS index, scrap]

var role: StringName = &""

var use_prompt: String = "Talk"

var _health: Health
var _animator: AnimationPlayer
var _playing := &""
var _last_at := Vector3.INF
var _sled: Node3D
var _sled_grown := -1.0
var _shop: Node3D
var _going_off := false
var _beep_left := 0.0
var _light: OmniLight3D


func net_spawn_args() -> Dictionary:
	return {role = role}


func net_restore(args: Dictionary) -> void:
	role = StringName(args.get("role", ""))


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	add_to_group(PlayerMovement.USABLE_GROUP)
	add_to_group(&"quest_npcs")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3.UP * 0.9
	add_child(shape)
	var model := QuestProps.human(str(MODELS.get(role, "")))
	if model:
		add_child(model)
		_animator = PlayerModel.animator_for(model)
		_play(IDLE)
		if role == &"shrine":
			Cult.robe_up.call_deferred(model)
	if HEALTH.has(role):
		_health = Health.new()
		_health.name = "Health"
		_health.max_health = HEALTH[role]
		add_child(_health)
		if _decides():
			_health.died.connect(_on_died)
			_health.damaged.connect(_on_damaged)
	match role:
		&"shrine":
			var altar := QuestProps.altar(1.0, 1)
			altar.position = Vector3(0.0, 0.0, -3.0)
			add_child(altar)
		&"bounty":
			var fire := QuestProps.lit_fire()
			fire.position = Vector3(0.0, 0.0, -1.8)
			add_child(fire)
		&"fanatic":
			_refresh_sled()
			Network.fact_changed.connect(_on_fact)
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = 300.0


func _decides() -> bool:
	return not NetEntities.is_puppet(self) and (not Network.is_online() or multiplayer.is_server())


# ---- Talking -------------------------------------------------------------------------------

func can_use() -> bool:
	return not _going_off and QuestTalk.can_talk(role, PlayerMovement.local_player(get_tree()))


## F with something in your hand talks too (handing it over).
func takes_held(_player: Node) -> bool:
	return can_use()


func use_by(player: Node) -> void:
	var p := player as PlayerMovement
	if p and p.is_multiplayer_authority():
		QuestTalk.talk(role, p)


# ---- Each frame ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if role == &"mara" and _decides():
		_follow_trader(delta)
	# Walking or standing (each game, from how it moves).
	if _last_at.is_finite():
		var moved := global_position.distance_to(_last_at) / maxf(delta, 0.0001)
		_play(WALK if moved > 0.4 else IDLE)
	_last_at = global_position
	if _going_off:
		_beep_left -= delta
		if _beep_left <= 0.0:
			_beep_left = 0.25
			_beep()


## Mara: beside her trader (the torn banner's), keeping up.
func _follow_trader(delta: float) -> void:
	var trader := _trader()
	if trader == null:
		return
	var want := trader.global_transform * BESIDE
	want.y = QuestWorld.ground_at(get_tree(), want).y if QuestWorld.ground_at(get_tree(), want).is_finite() else want.y
	var to := want - global_position
	if to.length() > 40.0:
		global_position = want # (left far behind: caught up)
		return
	var step := to.limit_length(MARA_SPEED * 1.5 * delta)
	if step.length() > 0.01:
		global_position += step
		var flat := Vector3(step.x, 0.0, step.z)
		if flat.length_squared() > 0.0001:
			global_basis = global_basis.slerp(Basis.looking_at(flat.normalized(), Vector3.UP), minf(delta * 4.0, 1.0)).orthonormalized()


func _trader() -> Node3D:
	var id := Quests.torn_trader()
	for node in Traders._all:
		if is_instance_valid(node) and str(node.get(&"trader_id")) == id:
			return node
	return null


func _play(path: String) -> void:
	if _animator == null or _playing == StringName(path) or not ResourceLoader.exists(path):
		return
	_playing = StringName(path)
	var animation := load(path) as Animation
	if not _animator.has_animation_library(&"npc"):
		_animator.add_animation_library(&"npc", AnimationLibrary.new())
	var library := _animator.get_animation_library(&"npc")
	var clip := StringName(path.get_file().get_basename())
	if not library.has_animation(clip):
		library.add_animation(clip, animation)
	animation.loop_mode = Animation.LOOP_LINEAR
	_animator.play(StringName("npc/" + clip), 0.3)


# ---- Hurt, killed --------------------------------------------------------------------------

func _on_damaged(_amount: float, attacker: int) -> void:
	if role == &"fanatic" and attacker > 0:
		var by := Network.body_of(attacker) if Network.is_online() else PlayerMovement.local_player(get_tree())
		Quests.kamikaze(get_tree(), by)


func _on_died(_attacker: int, _critical: bool) -> void:
	match role:
		&"bounty":
			Quests.bounty_man_killed(global_position, get_tree())
			_leave_body()
		&"fanatic":
			Quests.kamikaze(get_tree(), null)
			return # (he blows: go_off)
	queue_free()


## His body where he fell (an enemy's corpse, in his clothes).
func _leave_body() -> void:
	var path := "res://scenes/enemy/enemy.tscn"
	if not ResourceLoader.exists(path):
		return
	var body := (load(path) as PackedScene).instantiate() as Enemy
	var model := body.get_node_or_null(^"Model")
	if model and ResourceLoader.exists(str(MODELS.get(role, ""))):
		var variants: Array[PackedScene] = [load(str(MODELS[role])) as PackedScene]
		model.set(&"variants", variants)
	body.can_mutate = false
	body.corpse_time = 300.0
	body.set_meta(&"culled", true)
	get_tree().current_scene.add_child(body)
	body.global_transform = global_transform
	var health := body.get_node(^"Health") as Health
	health.take_damage(health.current_health + 1.0)


## Every game: he tears his coat open, beeping, KAMIKAZE_TIME -- then (the
## host's) the blast, and he's gone.
func go_off() -> void:
	if _going_off:
		return
	_going_off = true
	# The bomb strapped round him, its light.
	var vest := QuestProps.sled(0.0)
	vest.scale = Vector3.ONE * 0.35
	vest.position = Vector3(0.0, 1.0, -0.15)
	add_child(vest)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.1, 0.05)
	_light.omni_range = 4.0
	_light.position = Vector3(0.0, 1.4, -0.4)
	add_child(_light)
	if not _decides():
		return
	get_tree().create_timer(KAMIKAZE_TIME).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		var settings := Explosion.Settings.new()
		settings.damage = KAMIKAZE_DAMAGE
		settings.player_damage = KAMIKAZE_DAMAGE
		settings.radius = KAMIKAZE_RADIUS
		settings.knockback = 20.0
		Explosion.explode(get_tree().current_scene as Node3D, global_position + Vector3.UP, settings)
		queue_free())


static var _beep_stream: AudioStreamWAV


func _beep() -> void:
	if _light:
		_light.visible = not _light.visible
	if _beep_stream == null:
		var rate := 22050
		var samples := PackedByteArray()
		samples.resize(int(rate * 0.08) * 2)
		for i in samples.size() / 2:
			var value := int(sin(TAU * 1800.0 * i / rate) * 9000.0)
			samples.encode_s16(i * 2, value)
		_beep_stream = AudioStreamWAV.new()
		_beep_stream.format = AudioStreamWAV.FORMAT_16_BITS
		_beep_stream.mix_rate = rate
		_beep_stream.data = samples
	var player := AudioStreamPlayer3D.new()
	player.stream = _beep_stream
	player.max_distance = 60.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ---- The Fanatic's sled, his shop ----------------------------------------------------------

func _on_fact(_name: StringName, _value: Variant) -> void:
	_refresh_sled()


func _refresh_sled() -> void:
	if role != &"fanatic":
		return
	var grown := Quests.fanatic_grown()
	if not is_equal_approx(grown, _sled_grown):
		_sled_grown = grown
		if _sled:
			_sled.queue_free()
		_sled = QuestProps.sled(grown)
		_sled.position = Vector3(1.6, 0.0, 0.0)
		add_child(_sled)
	if Quests.flag("fanatic.shop") and _shop == null:
		_shop = Node3D.new()
		_shop.position = Vector3(1.6, 0.3 + grown * 0.6, 0.0)
		add_child(_shop)
		for i in FANATIC_PRICES.size():
			var good := FanaticGood.new()
			good.good = int(FANATIC_PRICES[i][0])
			good.price = int(FANATIC_PRICES[i][1])
			good.position = Vector3(0.0, 0.25, -0.6 + i * 0.6)
			_shop.add_child(good)


## One of the Fanatic's explosives laid out on his sled (F to buy; always in
## stock). The host takes the scrap (bag and hand) and puts it in your hand.
class FanaticGood extends StaticBody3D:
	var good := 0
	var price := 1
	var use_prompt: String:
		get:
			return "Buy: %s, %d scrap" % [TraderGoods.GOODS[good].name, price]

	func _ready() -> void:
		add_to_group(PlayerMovement.USABLE_GROUP)
		collision_layer = Trader.GOOD_LAYER | 1
		var data := TraderGoods.data_of(good)
		var model := CarryItem.model_for(data)
		if model:
			var bounds := BackpackView._bounds(model)
			var fit := 0.4 / maxf(bounds.get_longest_axis_size(), 0.001)
			model.scale = Vector3.ONE * fit
			model.position = -bounds.get_center() * fit
			add_child(model)
		var label := Label3D.new()
		label.font = JournalPage.font()
		label.font_size = 48
		label.pixel_size = 0.001
		label.modulate = JournalPage.PENCIL
		label.text = str(price)
		label.position = Vector3(0.0, 0.25, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.4
		shape.shape = box
		add_child(shape)

	func can_use() -> bool:
		return true

	func use_by(player: Node) -> void:
		var p := player as PlayerMovement
		if p == null or (Network.is_online() and not multiplayer.is_server()):
			return
		var hand := p.hand
		var in_hand := int(hand.data.get("amount", 0)) if hand.held_kind() == Backpack.Kind.SCRAP else 0
		if p.backpack.scrap + in_hand < price:
			if p.is_multiplayer_authority():
				MapIO.show_message(get_tree(), "Not enough scrap")
			return
		if in_hand > 0:
			hand.put_back()
		if not p.backpack.take(Backpack.Kind.SCRAP, price):
			return
		Network.send_backpack_take(p.get_multiplayer_authority(), Backpack.Kind.SCRAP, price)
		hand.give(TraderGoods.data_of(good))
