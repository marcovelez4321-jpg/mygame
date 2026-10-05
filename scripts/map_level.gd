class_name MapLevel
extends Node3D

## Base behavior for a level built from a TrenchBroom map: positions the
## player at wherever the map's info_player_start entity was placed, instead
## of a hardcoded transform baked into this scene, and bakes a walkable
## NavigationMesh from the level's own static geometry (see
## _bake_navigation()). Attach to any level scene that has a FuncGodotMap
## child (already built) and a Player child -- reusable across every future
## TrenchBroom map, not just this one. A hand-built test scene can also
## extend this directly (test_map.gd does) to get the same nav baking without
## duplicating it, calling super._ready() before its own setup.
##
## If the map has no info_player_start yet (not placed, or the map hasn't
## been rebuilt since adding it), the player just stays wherever it was
## hand-placed in the scene -- lets you keep testing a map before its spawn
## point exists.

@export var player_path: NodePath = ^"Player"

## Fed into the baked NavigationMesh's agent settings -- roughly matches the
## enemies' own collision capsule (enemy.tscn's CollisionShape3D: radius 0.4,
## height ~2.3) so the bake doesn't carve paths tighter or looser than what's
## actually walking them.
@export var nav_agent_radius: float = 0.4
@export var nav_agent_height: float = 2.0

## Every StaticBody3D under this level gets tagged into this group right
## before baking, so the NavigationMesh bake can find them via
## SOURCE_GEOMETRY_GROUPS_EXPLICIT even though they're level-root siblings
## (Ground, walls, the FuncGodotMap-built brushes), not children, of the
## NavigationRegion3D itself -- see _bake_navigation()'s own comment.
const NAV_SOURCE_GROUP := "level_static_geometry"

var navigation_region: NavigationRegion3D


func _ready() -> void:
	_bake_navigation()
	add_child(AmbiencePlayer.new())

	var start := get_tree().get_first_node_in_group("player_start")
	if start == null:
		push_warning("MapLevel: no info_player_start found in this map -- player stays at its scene-placed position.")
		return
	var player := get_node_or_null(player_path) as Node3D
	if player == null:
		return
	player.global_position = start.global_position
	player.global_rotation.y = start.global_rotation.y


## Bakes a walkable NavigationMesh from this level's own static collision
## geometry right when the level loads, instead of a hand-baked
## NavigationRegion3D saved in the scene -- func_godot bakes TrenchBroom
## brushes as StaticBody3D, same as any hand-built wall/floor, so this covers
## a map rebuilt in TrenchBroom automatically next time the level loads, with
## no separate manual re-bake step to remember. Baking runs on a background
## thread (bake_navigation_mesh()'s default), so pathfinding isn't available
## for the first instant after load -- fine in practice, since an enemy only
## starts pathing once it actually spots a player, not at load itself.
func _bake_navigation() -> void:
	_tag_static_geometry(self)

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = nav_agent_radius
	nav_mesh.agent_height = nav_agent_height
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_mesh.geometry_source_group_name = NAV_SOURCE_GROUP
	nav_mesh.geometry_collision_mask = 1 # world geometry only, same layer everything else here uses

	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "NavigationRegion3D"
	navigation_region.navigation_mesh = nav_mesh
	add_child(navigation_region)
	navigation_region.bake_navigation_mesh()


## Recursively tags every StaticBody3D under this level into NAV_SOURCE_GROUP
## -- see the group constant's own comment for why this is needed instead of
## just nesting the level's geometry under the NavigationRegion3D directly.
func _tag_static_geometry(node: Node) -> void:
	if node is StaticBody3D:
		node.add_to_group(NAV_SOURCE_GROUP)
	for child in node.get_children():
		_tag_static_geometry(child)
