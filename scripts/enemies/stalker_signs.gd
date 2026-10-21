class_name StalkerSigns
extends RefCounted

## What the Stalker (the wendigo) leaves and does to the world that every
## game shows for itself (Rule 1: presentation; the host sends them with
## Network.send_stalker_sign): the wrong silence before a stunt, and the
## signs of it -- see play().
## Its own sounds go on their own bus (BUS), so the silence never mutes it.

## The Stalker's own sounds (its voices, skitter, breathing): never silenced.
const BUS := &"Stalker"
## The wrong silence (the user's: world only, over 4 s): the world's sounds
## -- ambience, wind, creatures -- fade out; your own steps and gun, and the
## music, stay. Held till the stunt's done, then back over SILENCE_BACK.
const SILENCED_BUSES := [&"Ambience", &"Enemies"]
const SILENCE_FADE := 4.0
const SILENCE_BACK := 3.0
const SILENCE_DB := -60.0
## Never held longer than this (s), whatever happens to the stunt.
const SILENCE_LONGEST := 90.0

static var _held := {} # bus -> its volume before the silence
static var _silence_tween: Tween
static var _silence_serial := 0


## The bus its sounds play on (made the first time: sends where Enemies does).
static func bus() -> StringName:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master")
	return BUS


## A sign shown here (Network.send_stalker_sign, on every game it's for).
static func play(tree: SceneTree, kind: StringName, at: Vector3, dir: Vector3) -> void:
	match kind:
		&"silence_on":
			silence(tree, true)
		&"silence_off":
			silence(tree, false)


## The world's sounds fading out (`on`) or back.
static func silence(tree: SceneTree, on: bool) -> void:
	if _silence_tween and _silence_tween.is_valid():
		_silence_tween.kill()
	_silence_serial += 1
	var serial := _silence_serial
	var levels := {}
	for name: StringName in SILENCED_BUSES:
		var index := AudioServer.get_bus_index(name)
		if index == -1:
			continue
		if on and not _held.has(name):
			_held[name] = AudioServer.get_bus_volume_db(index)
		if _held.has(name):
			levels[index] = [AudioServer.get_bus_volume_db(index), SILENCE_DB if on else float(_held[name])]
	if levels.is_empty():
		return
	_silence_tween = tree.create_tween()
	_silence_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_silence_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_silence_tween.tween_method(func(t: float) -> void:
		for index: int in levels:
			# Eased in linear volume (a dB ramp sounds like it drops off a cliff).
			var from := db_to_linear(levels[index][0])
			var to := db_to_linear(levels[index][1])
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(lerpf(from, to, t), 0.00001))),
			0.0, 1.0, SILENCE_FADE if on else SILENCE_BACK)
	if not on:
		_silence_tween.tween_callback(func() -> void: _held.clear())
	else:
		# A failsafe: never held for ever.
		tree.create_timer(SILENCE_LONGEST).timeout.connect(func() -> void:
			if serial == _silence_serial:
				silence(tree, false))
