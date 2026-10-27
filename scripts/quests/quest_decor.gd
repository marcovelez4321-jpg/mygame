class_name QuestDecor
extends StaticBody3D

## The quests' set pieces (QuestWorld places them; the host's, seen on every
## game through NetEntities):
##   CLIMBER_BODY -- the climber who fell, lying at the tallest tower's foot.
##   CAIRN -- the summit cairn on the tallest tower's top (the user's: F there
##     with his tags lays them on it -- Climb for him); his tags hang on it
##     once they're left.
##   OFFERING -- the offering left in the Stalker's home (Bones for the Voice).

const CLIMBER_BODY := &"climber_body"
const CAIRN := &"cairn"
const OFFERING := &"offering"
const CLIMBER_MODEL := "res://art/characters/Characters_psx/Models/Male/Character_14.fbx"

var kind: StringName = &""

var use_prompt: String = "Leave his tags"

var _tags: Node3D


func net_spawn_args() -> Dictionary:
	return {kind = kind}


func net_restore(args: Dictionary) -> void:
	kind = StringName(args.get("kind", ""))


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	match kind:
		CLIMBER_BODY:
			var body := QuestProps.human(CLIMBER_MODEL)
			if body:
				# On his back where he landed, an arm flung out.
				body.rotation = Vector3(-PI * 0.5, 0.4, 0.0)
				body.position = Vector3(0.0, 0.12, 0.9)
				add_child(body)
			var stain := MeshInstance3D.new()
			var pool := CylinderMesh.new()
			pool.top_radius = 1.1
			pool.bottom_radius = 1.1
			pool.height = 0.01
			stain.mesh = pool
			stain.material_override = QuestProps.material(Color(0.2, 0.03, 0.03))
			stain.position = Vector3(0.0, 0.02, 0.0)
			add_child(stain)
		CAIRN:
			add_to_group(PlayerMovement.USABLE_GROUP)
			add_child(QuestProps.cairn())
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.0, 1.0, 1.0)
			shape.shape = box
			shape.position = Vector3.UP * 0.5
			add_child(shape)
			set_meta(&"net_always", true)
			Network.fact_changed.connect(func(_name: StringName, _value: Variant) -> void: _show_tags())
			_show_tags()
		OFFERING:
			add_child(QuestProps.offering())


func _show_tags() -> void:
	if Quests.flag("climb.tags_left") and _tags == null:
		_tags = QuestProps.tags_on_cairn()
		add_child(_tags)


# ---- The cairn: F with his tags --------------------------------------------------------

func can_use() -> bool:
	if kind != CAIRN or Quests.state(Quests.CLIMB) != Quests.State.ACTIVE or Quests.flag("climb.tags_left"):
		return false
	var me := PlayerMovement.local_player(get_tree())
	return me != null and (me.hand.held_kind() == Backpack.Kind.TAGS or me.backpack.count_of(Backpack.Kind.TAGS) > 0)


func takes_held(_player: Node) -> bool:
	return can_use()


func use_by(player: Node) -> void:
	var p := player as PlayerMovement
	if p and p.is_multiplayer_authority() and can_use():
		Network.ask_quest(Quests.CLIMB, &"leave_tags")
