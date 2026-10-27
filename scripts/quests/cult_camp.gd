class_name CultCamp
extends Node3D

## One of the cult's camps (the user's, 2026-10-27: three out in the wilds,
## rolled per world): a smaller flesh-root altar for its totem, a fire, and
## Cult.CAMP_PEOPLE of them round it -- let out by the host once anyone's
## within WAKE (so the far ones cost nothing), staying till they're killed
## (this session).
## Rule 1 (co-op): the host's (NetEntities: the camp, and its cultists).

const WAKE := 250.0
const SPREAD := 8.0

var camp_seed := 0

var _woken := false


func net_spawn_args() -> Dictionary:
	return {camp_seed = camp_seed}


func net_restore(args: Dictionary) -> void:
	camp_seed = int(args.get("camp_seed", 0))


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	add_to_group(&"cult_camps")
	set_meta(&"net_big", true)
	var totem := QuestProps.altar(0.55, camp_seed)
	add_child(totem)
	var fire := QuestProps.lit_fire()
	fire.position = Vector3(0.0, 0.0, 4.0)
	add_child(fire)
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = 500.0


func _physics_process(_delta: float) -> void:
	if _woken or NetEntities.is_puppet(self) or (Network.is_online() and not multiplayer.is_server()):
		return
	if Engine.get_physics_frames() % 30 != 0:
		return
	if not QuestWorld.anyone_within(get_tree(), global_position, WAKE):
		return
	_woken = true
	var dice := RandomNumberGenerator.new()
	dice.seed = camp_seed
	var count := dice.randi_range(Cult.CAMP_PEOPLE.x, Cult.CAMP_PEOPLE.y)
	for i in count:
		var a := TAU * i / count
		var at := QuestWorld.ground_at(get_tree(), global_position + Vector3(cos(a), 0.0, sin(a)) * SPREAD)
		if at.is_finite():
			Cult.cultist(get_tree().current_scene, at + Vector3.UP * 0.2)
