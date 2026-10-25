class_name TraderKeeper
extends Node

## The host's: every trader's plan (TraderDirector: where each parks, each
## wanderer's route) and what's become of them, from the world's facts
## (WorldFacts, kept between sessions):
##   trader.<id>.wreck / .wreck_yaw / .wreck_look  where one died: his cart
##     left there, tipped over (TraderWreck) -- a landmark, for good;
##   trader.<id>.back_in  play time (s) till a replacement takes his place or
##     his route (the user's: 80 minutes -- 4 x 20-minute days, the tension
##     cycle's, till day and night exist), counted while playing.

const SAVE_EVERY := 30.0

var plans := {}
var _counting := {}
var _save_left := SAVE_EVERY
var _check_left := 1.0


func _ready() -> void:
	name = "TraderKeeper"
	add_to_group(&"trader_keeper")
	var scene := get_tree().current_scene
	for id: String in plans:
		var wreck: Variant = WorldFacts.get_fact(StringName("trader.%s.wreck" % id), null)
		if wreck is Vector3:
			var cart := TraderWreck.new()
			cart.look_seed = int(WorldFacts.get_fact(StringName("trader.%s.wreck_look" % id), 1))
			scene.add_child(cart)
			cart.global_transform = Transform3D(Basis(Vector3.UP, float(WorldFacts.get_fact(StringName("trader.%s.wreck_yaw" % id), 0.0))), wreck)
		var left := _left_of(id)
		if left > 0.0:
			_counting[id] = left
		else:
			TraderDirector.spawn(scene, id, plans[id])


## Every trader there is (the robbed ones' refusals: Traders).
func ids() -> Array:
	return plans.keys()


static func _left_of(id: String) -> float:
	var value: Variant = WorldFacts.get_fact(StringName("trader.%s.back_in" % id), 0.0)
	return float(value) if value != null else 0.0


func _process(delta: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 1.0
	# A death since (Trader._die): its countdown starts.
	for id: String in plans:
		if not _counting.has(id) and _left_of(id) > 0.0:
			_counting[id] = _left_of(id)
	var save := false
	_save_left -= 1.0
	if _save_left <= 0.0:
		_save_left = SAVE_EVERY
		save = true
	for id: String in _counting.keys():
		var left := float(_counting[id]) - 1.0
		if left <= 0.0:
			_counting.erase(id)
			Network.send_fact(StringName("trader.%s.back_in" % id), 0.0)
			TraderDirector.spawn(get_tree().current_scene, id, plans[id], true) # (his replacement)
			continue
		_counting[id] = left
		if save:
			Network.send_fact(StringName("trader.%s.back_in" % id), left)
