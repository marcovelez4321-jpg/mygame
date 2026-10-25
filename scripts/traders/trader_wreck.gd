class_name TraderWreck
extends Node3D

## A dead trader's cart where he fell (the user's: tipped on its side, a wheel
## off, the banner in the dirt, the lanterns out) --
## left there for good, a landmark (TraderKeeper, from the facts). Every game
## sees it (NetEntities, made with .new()).

var look_seed := 1


func net_spawn_args() -> Dictionary:
	return {look = look_seed}


func net_restore(args: Dictionary) -> void:
	look_seed = int(args.get("look", 1))


func _ready() -> void:
	add_to_group(NetEntities.GROUP)
	var cart := Rickshaw.new(look_seed)
	add_child(cart)
	cart.wreck(self)
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).visibility_range_end = Trader.SEEN_RANGE
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.0, 2.8)
	shape.shape = box
	shape.position = Vector3(1.0, 0.5, 0.3)
	body.add_child(shape)
	add_child(body)
