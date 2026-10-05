class_name PhysicsAudio
extends RefCounted

## Valve's physics impact pipeline (Source SDK physics.cpp + vphysics_sound.h,
## AUDIO_DESIGN.md section 1c), shared by everything physical that makes
## noise: ragdoll bones now, props later. Callers report impacts; once per
## physics frame they're merged and played:
##   - volume grows with speed squared, so taps are quiet and slams are loud
##   - same-material impacts in one frame merge into ONE sound (volumes add,
##     loudest position wins) -- a whole body landing is one thud, not 15 clicks
##   - past MERGE_ALL_AFTER entries in a frame, everything merges
##   - never more than MAX_VOICES impact sounds playing at once
## The per-object 0.05 s cooldown and speed gate live with the caller, which
## owns the per-object state (see RagdollAudio).
## Rule 1 (co-op): cosmetic and local, every client runs its own.

## Slowest hit that makes any sound, m/s (Source: 70 units/s).
const MIN_SPEED := 1.8
## Hit speed that plays at full volume, m/s (Source: 320 units/s).
const FULL_VOLUME_SPEED := 8.0
const MERGE_ALL_AFTER := 4
## The PS1 had 24 hardware voices; physics gets half, the rest of the game
## keeps the other half.
const MAX_VOICES := 12


class Impact:
	var surface: SurfaceAudio
	var hit: SurfaceAudio
	var volume: float
	var speed: float
	var position: Vector3


## Ticks once per physics frame, after every other node (high priority
## number), and plays that frame's merged impacts. Created on first use and
## parked on the tree root so it survives level restarts.
class Flusher extends Node:
	func _ready() -> void:
		process_physics_priority = 1000

	func _physics_process(_delta: float) -> void:
		PhysicsAudio.flush(get_tree().current_scene)


static var _queue: Array[Impact] = []
static var _voices: Array = []
static var _flusher: Node


## Volume (0..1) for a hit at `speed`, Source's speed² / 320² curve.
static func impact_volume(speed: float) -> float:
	return clampf(speed * speed / (FULL_VOLUME_SPEED * FULL_VOLUME_SPEED), 0.0, 1.0)


## `surface` is the material making the sound; `hit` is what it hit (decides
## soft vs hard). `volume_scale` turns the whole thing down, e.g. for a
## quieter secondary layer.
static func report_impact(tree: SceneTree, surface: SurfaceAudio, hit: SurfaceAudio, speed: float,
		position: Vector3, volume_scale: float = 1.0) -> void:
	if surface == null or speed < MIN_SPEED:
		return
	_ensure_flusher(tree)
	var volume := impact_volume(speed) * volume_scale
	for i in range(_queue.size() - 1, -1, -1):
		var impact: Impact = _queue[i]
		if impact.surface == surface or _queue.size() > MERGE_ALL_AFTER:
			if volume > impact.volume:
				impact.position = position
				impact.hit = hit
			impact.volume += volume
			impact.speed = maxf(impact.speed, speed)
			return
	var added := Impact.new()
	added.surface = surface
	added.hit = hit
	added.volume = volume
	added.speed = speed
	added.position = position
	_queue.append(added)


static func flush(world: Node) -> void:
	if _queue.is_empty():
		return
	_voices = _voices.filter(func(player: Variant) -> bool: return is_instance_valid(player))
	if world != null:
		for impact: Impact in _queue:
			if _voices.size() >= MAX_VOICES:
				break
			var event: SoundEvent = impact.surface.impact_sound(impact.hit, impact.speed)
			var player: AudioStreamPlayer3D = SoundPlayer.play_3d(event, impact.position, world, minf(impact.volume, 1.0))
			if player:
				_voices.append(player)
	_queue.clear()


static func _ensure_flusher(tree: SceneTree) -> void:
	if is_instance_valid(_flusher):
		return
	_flusher = Flusher.new()
	_flusher.name = "PhysicsAudioFlusher"
	tree.root.add_child.call_deferred(_flusher)
