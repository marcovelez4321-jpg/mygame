class_name SoundPlayer
extends RefCounted

## Plays SoundEvents. The whole point of this file: every gameplay script
## that wants a sound calls ONE of these three functions and hands it a
## SoundEvent -- it never touches AudioStreamPlayer nodes, bus names, or
## randomization itself. Same shape as BloodFX/HitFlash (a static helper, not
## an autoload): playing a sound is a fire-and-forget one-shot effect, not
## something that needs persistent state, so there's nothing an autoload
## would give us that a static function doesn't (Rule 2: no complexity that
## isn't earning its keep).
##
## Rule 1 (co-op): purely local presentation, same as every other FX helper
## here. Each client plays its own copy of a sound the moment the gameplay
## signal it's listening to fires locally -- nothing about sound itself goes
## over the network. Enemy state (health.gd, enemy.gd) is already
## host-authoritative and replicated, so both players' games already receive
## the SAME state changes and can each play sound off them independently,
## exactly like enemy_animator.gd already does for animation.

## Non-positional: full volume regardless of listener position. Used for
## sounds that should always read clearly no matter where the camera is
## pointed -- your OWN gunshots, footsteps, hit markers, pickups -- the same
## reason an FPS doesn't quietly fade out the sound of your own gun as you
## spin the camera around.
static func play_2d(event: SoundEvent) -> AudioStreamPlayer:
	if event == null:
		return null
	var clip := event.pick_clip()
	if clip == null:
		return null # stub event, no audio assigned yet -- silently do nothing

	var player := AudioStreamPlayer.new()
	player.stream = clip
	player.volume_db = event.roll_volume_db()
	player.pitch_scale = event.roll_pitch_scale()
	player.bus = _resolve_bus(event.bus)

	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


## Positional: gets quieter with distance and pans with direction, played at
## a fixed world point. Used for anything the player should be able to
## LOCATE by ear -- enemy sounds, world impacts, eventually other players'
## guns -- which matters in a shooter (you should be able to tell an enemy is
## behind you before you see it).
static func play_3d(event: SoundEvent, position: Vector3, world: Node) -> AudioStreamPlayer3D:
	if event == null:
		return null
	var clip := event.pick_clip()
	if clip == null:
		return null

	var player := AudioStreamPlayer3D.new()
	player.stream = clip
	player.volume_db = event.roll_volume_db()
	player.pitch_scale = event.roll_pitch_scale()
	player.bus = _resolve_bus(event.bus)

	world.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
	return player


## A looping, positional sound that follows a moving node -- an enemy's
## constant idle growl/breathing, an ambient hum. Parented directly to
## `follow` so it tracks its position for free every frame with no extra
## code (same trick BloodFX.spawn_artery_spurt() uses, parenting its
## particles to the neck bone instead of updating a world position by hand).
##
## Reconnects `finished -> play()` instead of relying on the audio file's own
## loop import setting, so any .wav/.ogg works here without the artist having
## to remember to flip that flag on import.
##
## Returns the player so the caller can stop() it later (e.g. on death) and
## queue_free() it -- stop() doesn't fire `finished`, so it won't restart
## itself first.
static func play_loop_3d(event: SoundEvent, follow: Node3D) -> AudioStreamPlayer3D:
	if event == null:
		return null
	var clip := event.pick_clip()
	if clip == null:
		return null

	var player := AudioStreamPlayer3D.new()
	player.stream = clip
	player.volume_db = event.roll_volume_db()
	player.pitch_scale = event.roll_pitch_scale()
	player.bus = _resolve_bus(event.bus)

	follow.add_child(player)
	player.finished.connect(player.play)
	player.play()
	return player


## Falls back to "Master" if the named bus doesn't exist (yet) -- see
## SoundEvent.bus's own comment. AudioServer.get_bus_index returns -1 for an
## unknown name, so every SoundEvent is safe to leave pointed at "SFX" before
## that bus has actually been created in the project's Audio panel.
static func _resolve_bus(bus_name: String) -> String:
	if AudioServer.get_bus_index(bus_name) == -1:
		return "Master"
	return bus_name
