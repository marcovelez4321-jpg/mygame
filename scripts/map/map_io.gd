class_name MapIO
extends RefCounted

## The wiring that connects interactive map pieces, the same scheme Quake and
## Quake 2 use (Quake 2's G_UseTargets() in g_utils.c): an entity's "target"
## is the name of what it activates, and every entity whose "targetname"
## matches gets its use() called. Mappers just type matching names in
## TrenchBroom -- one lever can open several doors, several buttons can open
## one door, and no Godot work is ever needed to connect them.
##
## Plus the small shared helpers every map piece needs: centre-screen
## messages, map units to meters, and Quake's "angle" key as a direction.
##
## Rule 1 (co-op): firing targets is gameplay and runs where the map pieces
## decide things -- the host, once co-op exists.

const TARGET_GROUP_PREFIX := "map_targetname_"
## Every entity with a non-empty "target", so a broken link can be found.
const LINK_GROUP := "map_links"
## Map settings to read the map scale from (32 TrenchBroom units = 1 meter).
const MAP_SETTINGS_PATH := "res://addons/func_godot/func_godot_default_map_settings.tres"

static var _units_per_meter := 0.0


## Makes `node` answer to `targetname` (does nothing for an empty name).
static func register_targetname(node: Node, targetname: String) -> void:
	if not targetname.is_empty():
		node.add_to_group(TARGET_GROUP_PREFIX + targetname)


## Remembers that `node` points at `target`, for find_broken_links().
static func register_target(node: Node, target: String) -> void:
	if not target.is_empty():
		node.add_to_group(LINK_GROUP)


## Calls use(activator) on everything named `target`.
static func fire_targets(from: Node, target: String, activator: Node) -> void:
	if target.is_empty() or not from.is_inside_tree():
		return
	for receiver in from.get_tree().get_nodes_in_group(TARGET_GROUP_PREFIX + target):
		if receiver.has_method("use"):
			receiver.call("use", activator)


## Every "target" in the level that nothing answers to -- nearly always a
## typo ("gate1" vs "gate_1"), which otherwise fails silently: the lever
## moves and nothing happens. MapLevel reports these when a level loads.
static func find_broken_links(tree: SceneTree) -> PackedStringArray:
	var problems: PackedStringArray = []
	for node in tree.get_nodes_in_group(LINK_GROUP):
		var target := str(node.get("target"))
		if tree.get_nodes_in_group(TARGET_GROUP_PREFIX + target).is_empty():
			problems.append("A %s targets \"%s\", but nothing has that targetname." % [node.call("describe"), target])
	return problems


## A Quake-style centre-screen message, like "You need the gold key".
## A pickup notice -- something added to your inventory -- the same pop-up as
## a weapon or ammo pickup (bottom centre of the HUD).
static func show_pickup(tree: SceneTree, text: String) -> void:
	if text.is_empty() or tree == null:
		return
	var hud := tree.get_first_node_in_group("hud")
	if hud and hud.has_method("show_pickup"):
		hud.call("show_pickup", text)


static func show_message(tree: SceneTree, text: String) -> void:
	if text.is_empty() or tree == null:
		return
	var hud := tree.get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.call("show_message", text)


## TrenchBroom units (what mappers type) to meters (what the game uses).
static func units_to_meters(units: float) -> float:
	if _units_per_meter <= 0.0:
		var settings := load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
		_units_per_meter = settings.inverse_scale_factor if settings else 32.0
	return units / _units_per_meter


## Quake's "angle" key as a direction: degrees around the vertical in
## TrenchBroom's top view (0 = east, 90 = north, 180 = west, 270 = south),
## or -1 = up and -2 = down. TrenchBroom's x (east) is Godot's +Z and its y
## (north) is Godot's +X -- the same swap func_godot makes for positions.
static func angle_to_direction(angle: float) -> Vector3:
	if is_equal_approx(angle, -1.0):
		return Vector3.UP
	if is_equal_approx(angle, -2.0):
		return Vector3.DOWN
	var radians := deg_to_rad(angle)
	return Vector3(sin(radians), 0.0, cos(radians))
