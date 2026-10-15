class_name FireSource
extends Node3D

## A fire meat cooks at (CarryItem, PlayerHand): an upright column -- radius
## round this node, from its position up `height` -- and anything within
## the reach of it (on it, over it, or right beside it) counts.
## Every fire's in one static list, so "is there a fire near here?" is a
## short loop of distance checks -- no physics queries, nothing per frame.

@export var radius: float = 0.35
@export var height: float = 1.5

static var _fires: Array[FireSource] = []


func _enter_tree() -> void:
	_fires.append(self)


func _exit_tree() -> void:
	_fires.erase(self)


## Whether `at` is within `reach` of any fire.
static func near_point(at: Vector3, reach: float) -> bool:
	for fire in _fires:
		var base := fire.global_position
		var flat := Vector2(at.x - base.x, at.z - base.z).length() - fire.radius
		var up := 0.0
		if at.y < base.y:
			up = base.y - at.y
		elif at.y > base.y + fire.height:
			up = at.y - base.y - fire.height
		if maxf(flat, 0.0) ** 2 + up * up <= reach * reach:
			return true
	return false
