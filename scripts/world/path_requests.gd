class_name PathRequests
extends Node

## Every navmesh path an enemy asks for, served a few per frame from one
## queue, so a crowd chasing you can't all path in the same frame. The
## time-sliced path queue big games use (Recast/Detour's query queue,
## Unreal's async path requests).
##   PathRequests.ask(tree, enemy, from, to) -- queued; at most `budget` are
##     worked out each physics frame, oldest first, and the answer goes to
##     enemy._on_path_found(path: PackedVector3Array).
## One request per enemy at a time: asking again replaces the waiting one.
## Rule 1 (co-op): paths are AI, and AI runs on the host.

## Paths worked out per physics frame, at most.
@export var budget: int = 6
## The most navmesh polygons one search may visit before it gives up with a
## partial path. Godot's default (4096) cut cross-map routes short on the
## open world's tiles (~78k polygons per km); enemies mostly chase nearby,
## so long searches are rare.
@export var max_search_polygons: int = 20000

var _queue: Array[Object] = []
## Requester -> [from, to] of its waiting request.
var _waiting := {}
var _query := NavigationPathQueryParameters3D.new()
var _result := NavigationPathQueryResult3D.new()


## Queues a path for `requester` (it gets _on_path_found(path) later).
static func ask(tree: SceneTree, requester: Node3D, from: Vector3, to: Vector3) -> void:
	if not is_instance_valid(_instance):
		_instance = PathRequests.new()
		_instance.name = "PathRequests"
		tree.root.add_child.call_deferred(_instance) # lives across level changes
	if not _instance._waiting.has(requester):
		_instance._queue.append(requester)
	_instance._waiting[requester] = [from, to]


static var _instance: PathRequests


func _ready() -> void:
	process_physics_priority = -10 # answers land before the enemies move
	_query.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	_query.path_search_max_polygons = max_search_polygons


func _physics_process(_delta: float) -> void:
	var done := 0
	while done < budget and not _queue.is_empty():
		var requester: Object = _queue.pop_front()
		var ends: Array = _waiting.get(requester, [])
		_waiting.erase(requester)
		if not is_instance_valid(requester) or ends.is_empty():
			continue
		var body := requester as Node3D
		_query.map = body.get_world_3d().navigation_map
		_query.start_position = ends[0]
		_query.target_position = ends[1]
		NavigationServer3D.query_path(_query, _result)
		body.call("_on_path_found", _result.path)
		done += 1
