class_name BeatMap
extends Resource

## A song's drum hits for the heart boss (docs/HEART_BOSS.md): when every
## kick, snare and hi-hat lands (seconds from the song's start), tapped out in
## the beat mapper (scenes/tools/beat_mapper.tscn). The heart fires its
## attacks on them. Every list kept in order.

enum Drum { KICK, SNARE, HAT }

@export var song: AudioStream
## The song's tempo and where its first beat lands (the mapper's snap grid).
@export var bpm: float = 120.0
@export var offset: float = 0.0
@export var kicks := PackedFloat32Array()
@export var snares := PackedFloat32Array()
@export var hats := PackedFloat32Array()


func hits(drum: int) -> PackedFloat32Array:
	match drum:
		Drum.KICK:
			return kicks
		Drum.SNARE:
			return snares
	return hats


func set_hits(drum: int, list: PackedFloat32Array) -> void:
	match drum:
		Drum.KICK:
			kicks = list
		Drum.SNARE:
			snares = list
		_:
			hats = list


## A hit at `time` (kept in order). False if there's one there already
## (within `near` seconds).
func add(drum: int, time: float, near: float = 0.01) -> bool:
	var list := hits(drum)
	var at := list.bsearch(time)
	if (at > 0 and absf(list[at - 1] - time) < near) or (at < list.size() and absf(list[at] - time) < near):
		return false
	list.insert(at, time)
	set_hits(drum, list)
	return true


## Takes out the hit nearest `time` if it's within `near` seconds; true if one was.
func remove(drum: int, time: float, near: float = 0.01) -> bool:
	var list := hits(drum)
	var at := list.bsearch(time)
	for i: int in [at - 1, at]:
		if i >= 0 and i < list.size() and absf(list[i] - time) <= near:
			list.remove_at(i)
			set_hits(drum, list)
			return true
	return false


## The hits of `drum` from `from` up to (not including) `to`: the boss asks
## each frame for what's coming.
func between(drum: int, from: float, to: float) -> PackedFloat32Array:
	var list := hits(drum)
	return list.slice(list.bsearch(from), list.bsearch(to))


## One beat (seconds).
func beat() -> float:
	return 60.0 / maxf(bpm, 1.0)
