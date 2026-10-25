class_name WorldChange
extends Node3D

## A piece of the world that changes with what's happened (the user's,
## 2026-10-25: subtle to not subtle -- graffiti, a corpse, a burned landmark,
## a tower's top gone). Its children are there only while a world fact
## (WorldFacts) is -- or isn't -- what it names. A swap is two of them on the
## same fact: the landmark under one that's there until it's burned, the
## wreck under one that's there once it is.
## Taken out of the tree while they're not there (nothing drawn, no
## collision, nothing processing: they cost nothing), and put back the moment
## the fact changes (the user's: at once), on every game (the facts are
## mirrored). Scenery only: no enemies or other networked things under it.

## The fact, e.g. "quest.fanatic.outcome".
@export var fact: StringName
## What it has to be, as text ("true", "2", "smoked"); empty: set at all.
@export var value: String = ""
## On: the children are there while it matches. Off: gone while it matches.
@export var present_when_matching := true

var _kept: Array[Node] = []
var _present := true


func _ready() -> void:
	Network.fact_changed.connect(_on_fact_changed)
	_apply()


func _on_fact_changed(name: StringName, _value: Variant) -> void:
	if name == fact:
		_apply()


func matches() -> bool:
	if not Network.facts.has(fact):
		return false
	return value.is_empty() or str(Network.facts[fact]) == value


func _apply() -> void:
	var want := matches() == present_when_matching
	if want == _present:
		return
	_present = want
	if want:
		for child in _kept:
			add_child(child)
		_kept.clear()
	else:
		for child in get_children():
			_kept.append(child)
			remove_child(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for child in _kept:
			if is_instance_valid(child):
				child.free()
		_kept.clear()
