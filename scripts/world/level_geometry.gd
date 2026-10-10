class_name LevelGeometry
extends RefCounted

## What a ray or shape query hit, sorted: the level itself (the ground and
## anything bolted in place) or something that moves.
## Why this exists: Terrain3D's in-game collision (the open world's ground)
## has no body node. A hit on it reports the Terrain3D node as its collider,
## not a StaticBody3D, so the old `collider is StaticBody3D` tests took the
## hills for something passing by and rays went straight through them (the
## Harvestman walked through a hill). Every "is this the level?" test goes
## through here instead.


## The open world's ground (a Terrain3D). A hit with no collider object at
## all is a body made straight on the physics server -- only Terrain3D
## makes those here -- so that counts as ground too.
static func is_terrain(collider: Object) -> bool:
	return collider == null or collider.is_class("Terrain3D")


## Level geometry that never moves: map brushes, hand-built walls and floors,
## the open world's megastructures and its ground. Not an AnimatableBody3D
## (spiders, lifts) -- those move.
static func is_static(collider: Object) -> bool:
	if collider is StaticBody3D:
		return not collider is AnimatableBody3D
	return is_terrain(collider)


## Any StaticBody3D (AnimatableBody3D included) or the ground: for the older
## tests that counted every StaticBody3D as solid world.
static func is_solid(collider: Object) -> bool:
	return collider is StaticBody3D or is_terrain(collider)
