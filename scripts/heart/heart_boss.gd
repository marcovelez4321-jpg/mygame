class_name HeartBoss
extends Node3D

## The heart boss (docs/HEART_BOSS.md), first pass: the real heart hanging in
## its cathedral (the Stack puts it there: StackBuilder.build_scene), chained
## up from every side, beating, dripping blood. While anyone's in the
## cathedral it plays its song's map (beat_map): on every snare its holes
## glow open and a beat later the volley blasts (BloodBeam); on every kick it
## beats and the whole cathedral shakes (HeartQuake). With no map yet:
## test_bpm, kick and snare taking turns.
## Values here are first picks (the user: "put the heart in"), all to change.
## Rule 1 (co-op): the host fires the beams (Network.send_blood_beam); its
## beating, chains and drips are looks, every game its own.

const HEART_MODEL := "res://art/heart_boss/realistic-human-heart/source/Heart.fbx"
const CHAIN_MODEL := "res://art/heart_boss/chain/chain.FBX"

## How tall the heart is (m).
@export var size: float = 40.0
## Its map: when its drums land. None: test_bpm, a beam every beat.
@export var beat_map: BeatMap
@export var test_bpm: float = 80.0
## Each snare's volley: one beam mainly at a player inside (the user's), and
## this many more off random spots on it, every way.
@export var aim_at_players: bool = true
@export var random_beams: int = 5
## And one at where each player inside is heading (the user's: in co-op,
## one for each of you), led the way the flying
## roaches lead their spit (FlyingRoach._spit_at) with the same values: their
## sideways speed fully (x PREDICTION), toward/away only PREDICTION_TOWARD of
## it, a random GUESS share of that lead each time plus up to GUESS_SIDEWAYS m
## across their way, AIM_PAST beyond them, SCATTER of a miss -- carried on
## for the time till it blasts (the glow).
@export var predicting_beam: bool = true
const PREDICTION := 0.8
const PREDICTION_TOWARD := 0.3
const GUESS := Vector2(0.4, 1.3)
const GUESS_SIDEWAYS := 1.2
const AIM_PAST := 0.4
const SCATTER := 0.25
## Chains: this many to the walls round it, this many up to the ceiling.
@export var wall_chains: int = 6
@export var ceiling_chains: int = 6
## How long one chain link is (m), and how far a chain sags (share of its length).
@export var link_length: float = 1.6
@export var sag: float = 0.06
## The cathedral (in the Stack's space), set by the Stack's bake.
@export var room := AABB()

## The beat (the user's): one big thump a kick -- swelling THUMP in a snap,
## easing back fast (THUMP_FALL a second) so quick kicks each land their own;
## its glow pulsing GLOW bright with it.
const THUMP := 0.2
const THUMP_RISE := 60.0
const THUMP_FALL := 9.0
const GLOW := 12.0
const DRIP_EVERY := 0.6
## Its health and the stun (the user's): MAX_HEALTH in all, flashing white
## each hit. Every STUN_EVERY damage it's stunned for STUN_TIME: the music
## scratches down to a stop like a record (SCRATCH_DOWN), it does nothing but
## beat -- a plain heartbeat, STUN_BPM at the first stun and STUN_BPM_STEP
## faster each one after, spraying blood every beat -- and every shot into
## it is an artery shot (HeartHitbox). Then the music spins back up like a
## DJ's scratch (SCRATCH_UP) from right where it stopped, and it fights on.
## At 0: it bursts, hangs still and silent, and the screen fades to black
## over DEATH_FADE.
## (Doubled, the user's 2026-10-18: were 700 and 150.)
const MAX_HEALTH := 1400.0
const STUN_EVERY := 300.0
const STUN_TIME := 10.0
const STUN_BPM := 60.0
const STUN_BPM_STEP := 10.0
const SCRATCH_DOWN := 0.7
const SCRATCH_UP := 0.5
const SCRATCH_LOW := 0.03
const DEATH_FADE := 7.0
## Black, then the words (the user's), then back to the game.
const DEATH_TEXT := "You've killed the heart... but what about the brain?"
const TEXT_IN := 1.0
const TEXT_HOLD := 4.0
const TEXT_OUT := 1.0
const FADE_BACK := 2.0
const HIT_FLASH := 0.08
## Hi-hats (the user's): a blood orb each (HeartOrb), swelling out of a
## random spot on it the beat before; at most MAX_ORBS about at once.
const MAX_ORBS := 10
## The song loops crossfading (the user's): its last LOOP_FADE seconds blend
## into its start, and the map starts over with it.
const LOOP_FADE := 2.0
const SILENT_DB := -40.0
## A kick (the user's): the cathedral's walls, columns and mezzanines judder
## (their meshes only -- the floor you stand on doesn't move) this far, for
## about this long; its lamps flicker and dim, then come back.
const JUDDER := 0.45
const JUDDER_TIME := 0.45
const JUDDER_RATE := 38.0
const FLICKER_TIME := 0.35
const ROOM_MESHES := ["Cathedral_plain", "Tower_5_concrete"]
## Its structures shift about (the user's), so there's no hiding behind the
## same wall: every SHIFT_EVERY kicks each one (a mezzanine with its ramps, a
## column, the pyramid, the slab, the stairs) picks a new spot within
## SHIFT_RANGE m of where it was built -- never into the open middle (ARENA)
## or out of the room -- and gets there in LURCHES lurches, one on each of
## the next kicks (a fifth of the way each, snapping over LURCH_TIME), then
## holds there till the next shift. The host picks; everyone lurches them.
const SHIFT_EVERY := 10
const LURCHES := 5
const LURCH_TIME := 0.25
## (The user's: 50 m -- 25 wasn't dramatic enough; and each move at least
## SHIFT_LEAST of it, so every shift's a clear rearrangement.)
const SHIFT_RANGE := 50.0
const SHIFT_LEAST := 0.5
const ARENA := 80.0
## Kept this far clear of the heart (its bounds swollen by a full thump), the
## user's: never clipping into it -- where it'd end up, and the way there.
const HEART_CLEARANCE := 6.0
## Its looks only run with someone this close (m).
const NEAR := 700.0

var _model: Node3D
var _radii := Vector3.ONE
var _chains: Array[Dictionary] = [] # {from (local), to (world), multimesh, links}
var _drips: GPUParticles3D
var _light: OmniLight3D
var _time := 0.0 # into the song (or the test beat)
var _beat_age := 10.0
var _next_beat := 0.0
var _next_beam := 0
var _drip_left := 0.0
## Stunned now (shots into it are artery shots); dead.
var stunned := false
var dead := false
var _stun_left := 0.0
var _stuns := 0
var _stun_meter := 0.0
var _stun_beat_left := 0.0
var _health: Health
var _hitbox: HeartHitbox
var _scratch: Tween
var _spray_points: Array[Node3D] = []
var _spray_wait := 0.0
var _room_meshes: Array[Node3D] = []
var _room_rests: Array[Vector3] = []
var _lamps: Array[Light3D] = []
var _lamp_energy: Array[float] = []
var _quake_age := 10.0
var _pieces: Array[AnimatableBody3D] = []
var _piece_home: Array[Vector3] = []
var _piece_to: Array[Vector3] = []
var _piece_extent: Array[AABB] = [] # each piece's own shape, round its origin
var _kicks := 0
var _piece_from: Array[Vector3] = [] # where this shift started
var _lurch_start: Array[Vector3] = [] # where this lurch started
var _lurches_done := LURCHES
var _lurch_age := 10.0
var _active := false
var _player: AudioStreamPlayer
## The map it's playing (yours if you've picked one: PlayerMovement.heart_song).
var _map: BeatMap
## The song's snares up to here have had their holes opened; hats, their orbs.
var _snares_to := -1.0
var _hats_to := -1.0
## The song as it fades out over a loop (the next pass is _player).
var _tail: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	add_to_group(&"heart_boss")
	_build_heart()
	_build_drips()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.15)
	_light.omni_range = size * 4.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_tail = AudioStreamPlayer.new()
	add_child(_tail)
	_build_hitbox()
	_build_chains.call_deferred() # once the cathedral's walls are in the physics
	_find_room.call_deferred()


func _process(delta: float) -> void:
	var near := _nearest_distance()
	_set_looks(near < NEAR)
	if near >= NEAR:
		return
	var inside := _anyone_inside()
	if inside and not _active:
		_start()
	elif not inside and _active:
		_stop()
	_beat_age += delta
	_spray_wait -= delta
	if dead:
		pass # (still: no beat, no attacks)
	elif stunned:
		_stunned_tick(delta)
	elif _active:
		_tick(delta)
	_shake_room(delta)
	# One thump, and the light pulsing with it.
	var thump := 0.0 if dead else (1.0 - exp(-_beat_age * THUMP_RISE)) * exp(-_beat_age * THUMP_FALL)
	_model.scale = Vector3.ONE * _base_scale * (1.0 + THUMP * thump)
	_light.light_energy = 1.0 + GLOW * thump
	if absf(thump - _chain_pulse) > 0.004:
		_chain_pulse = thump
		_update_chains(thump)
	# Dripping on the floor below.
	_drip_left -= delta
	if _drip_left <= 0.0 and not dead:
		_drip_left = DRIP_EVERY * randf_range(0.5, 1.5)
		var from := global_position + Vector3(randf_range(-_radii.x, _radii.x) * 0.6, -_radii.y * 0.8, randf_range(-_radii.z, _radii.z) * 0.6)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0, 1))
		if not hit.is_empty():
			BloodFX.spawn_splatter(get_tree().current_scene, hit.position, hit.normal, randf_range(0.8, 2.0))


# ---- Its health, the stun, its death ------------------------------------------------

## Its body for shots: the model's own shape (convex), where it hangs, with
## its Health (the host's to take damage).
func _build_hitbox() -> void:
	_hitbox = HeartHitbox.new()
	_hitbox.name = "Body"
	_hitbox.heart = self
	add_child(_hitbox)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		# The mesh as it sits here (at its resting size).
		var to_heart := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != self and walk is Node3D:
			to_heart = (walk as Node3D).transform * to_heart
			walk = walk.get_parent()
		# Its exact outline (not simplified: that cut in under its bulges),
		# as big as it swells on a thump -- so a shot that looks like a hit
		# on it is one, mid-beat too.
		var convex := mesh.mesh.create_convex_shape(true, false)
		var swollen := 1.0 + THUMP * 0.75
		var points := PackedVector3Array()
		for p in convex.points:
			points.append(to_heart * p * swollen)
		convex.points = points
		var shape := CollisionShape3D.new()
		shape.shape = convex
		_hitbox.add_child(shape)
	_health = Health.new()
	_health.name = "Health"
	_health.max_health = MAX_HEALTH
	_health.bleeds_out = false
	_hitbox.add_child(_health)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	# Spots on its surface its stunned beats spray out of.
	for i in 6:
		var way := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0), randf_range(-1.0, 1.0)).normalized()
		var spot := Node3D.new()
		_model.add_child(spot)
		spot.position = way * _radii * 0.8 / _base_scale
		spot.set_meta(&"out", way)
		_spray_points.append(spot)


## Hit (the host's Health): everyone sees it flash; every STUN_EVERY (not
## counting what lands while it's stunned) it's stunned.
func _on_damaged(amount: float, _attacker: int) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	Network.send_heart_event(&"hit")
	if stunned or dead:
		return
	_stun_meter += amount
	if _stun_meter >= STUN_EVERY and not _health.is_dead:
		_stun_meter -= STUN_EVERY
		Network.send_heart_event(&"stun")


func _on_died(_attacker: int, _critical: bool) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	Network.send_heart_event(&"die")


## Network.send_heart_event, on every game.
func event(kind: StringName) -> void:
	match kind:
		&"hit":
			HitFlash.flash(_model, Color.WHITE, HIT_FLASH)
		&"stun":
			_set_stunned(true)
		&"recover":
			_set_stunned(false)
		&"die":
			_die()


func _set_stunned(on: bool) -> void:
	if dead or on == stunned:
		return
	stunned = on
	if on:
		_stuns += 1
		_stun_left = STUN_TIME
		_stun_beat_left = 0.0
		_scratch_down(false)
	else:
		_scratch_up()


## Stunned: just its heartbeat, faster each stun, blood spraying every beat;
## the host ends it.
func _stunned_tick(delta: float) -> void:
	_stun_left -= delta
	_stun_beat_left -= delta
	if _stun_beat_left <= 0.0:
		_stun_beat_left = 60.0 / (STUN_BPM + STUN_BPM_STEP * (_stuns - 1))
		_beat_age = 0.0
		_spray_beat()
	if _stun_left <= 0.0 and not (Network.is_online() and not multiplayer.is_server()):
		Network.send_heart_event(&"recover")


## A stunned beat: blood spurting out of a few spots on it.
func _spray_beat() -> void:
	var world := get_tree().current_scene
	_spray_points.shuffle()
	for i in mini(3, _spray_points.size()):
		var spot := _spray_points[i]
		var out: Vector3 = spot.get_meta(&"out")
		BloodFX.spawn_artery_spurt(spot, 0.5, [_hitbox.get_rid()], Vector3.ZERO, (_model.global_basis.inverse() * out).normalized())
		BloodFX.spawn_impact(world, spot.global_position, out, BloodFX.BLOOD_COLOR, 4.0)


## An artery shot (while it's stunned): a spurt from where it was hit.
func artery_spray(at: Vector3, normal: Vector3) -> void:
	if _spray_wait > 0.0:
		return # (a shotgun's pellets: one spurt)
	_spray_wait = 0.15
	var wound := Node3D.new()
	_model.add_child(wound)
	wound.global_position = at
	BloodFX.spawn_artery_spurt(wound, 1.2, [_hitbox.get_rid()], Vector3.ZERO, (_model.global_basis.inverse() * normal).normalized())
	BloodFX.spawn_impact(get_tree().current_scene, at, normal, BloodFX.BLOOD_COLOR, 3.0)
	get_tree().create_timer(3.0).timeout.connect(wound.queue_free)


## The record scratch: the song slowing to a stop (`end`: and staying stopped).
func _scratch_down(end: bool) -> void:
	if _scratch:
		_scratch.kill()
	if _fade:
		_fade.kill()
	_tail.stop()
	_player.volume_db = 0.0
	if not _player.playing:
		return
	_scratch = create_tween()
	_scratch.tween_property(_player, "pitch_scale", SCRATCH_LOW, SCRATCH_DOWN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_scratch.tween_callback(func() -> void:
		if end:
			_player.stop()
		else:
			_player.stream_paused = true)


## The DJ's scratch back: spinning up to speed from where it stopped.
func _scratch_up() -> void:
	if _scratch:
		_scratch.kill()
	if _player.stream == null:
		return
	_player.pitch_scale = SCRATCH_LOW
	_player.stream_paused = false
	_scratch = create_tween()
	_scratch.tween_property(_player, "pitch_scale", 1.0, SCRATCH_UP).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 0 health: a burst of blood, still and silent in its chains, and (your
## screen) a slow fade to black.
func _die() -> void:
	if dead:
		return
	dead = true
	stunned = false
	_scratch_down(true)
	var world := get_tree().current_scene
	BloodFX.spawn_mutation_explosion(world, global_position)
	for i in 12:
		var way := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		BloodFX.spawn_impact(world, global_position + way * _radii * 0.9, way, BloodFX.BLOOD_COLOR, 5.0)
	_spray_beat()
	_drips.emitting = false
	_light.visible = false
	HitFlash.flash(_model, Color(0.6, 0.0, 0.0), 0.6)
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	var words := Label.new()
	words.text = DEATH_TEXT
	words.set_anchors_preset(Control.PRESET_FULL_RECT)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_theme_font_size_override("font_size", 40)
	words.modulate = Color(1.0, 1.0, 1.0, 0.0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(words)
	# To black; the words; back to the game.
	var fade := create_tween()
	fade.tween_property(black, "color:a", 1.0, DEATH_FADE)
	fade.tween_property(words, "modulate:a", 1.0, TEXT_IN)
	fade.tween_interval(TEXT_HOLD)
	fade.tween_property(words, "modulate:a", 0.0, TEXT_OUT)
	fade.tween_property(black, "color:a", 0.0, FADE_BACK)
	fade.tween_callback(layer.queue_free)


# ---- The beat ----------------------------------------------------------------------

func _start() -> void:
	_active = true
	_time = 0.0
	_next_beat = 0.0
	_next_beam = 0
	_map = _chosen_map()
	_snares_to = -1.0
	_hats_to = -1.0
	_player.volume_db = 0.0
	_player.stream = _map.song if _map else null
	_player.pitch_scale = 1.0
	_player.stream_paused = false
	if _player.stream:
		_player.play()


func _stop() -> void:
	_active = false
	_player.stop()
	_tail.stop()


## The song's end blending into its start (LOOP_FADE): the playing pass
## becomes the tail and fades out; the other player starts it over, fading
## in, and the map starts again with it.
func _loop() -> void:
	if _fade:
		_fade.kill()
	var old := _player
	_player = _tail
	_tail = old
	_player.stream = _tail.stream
	_player.pitch_scale = 1.0
	_player.stream_paused = false
	_player.volume_db = SILENT_DB
	_player.play()
	_time = 0.0
	_snares_to = -1.0
	_hats_to = -1.0
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_player, "volume_db", 0.0, LOOP_FADE).set_trans(Tween.TRANS_SINE)
	_fade.tween_property(_tail, "volume_db", SILENT_DB, LOOP_FADE).set_trans(Tween.TRANS_SINE)
	_fade.chain().tween_callback(_tail.stop)


## Your pick (the heart_song in your player's inspector), else its own.
func _chosen_map() -> BeatMap:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and player.is_multiplayer_authority() and player.heart_song and player.heart_song.song:
			return player.heart_song
	return beat_map if beat_map and beat_map.song else null


func _tick(delta: float) -> void:
	_time = _song_time() if _player.playing else _time + delta
	if _map:
		# Its map: every kick, the quake; every snare, the volley blasts ON it
		# (the user's) -- its holes glowing open the beat before.
		var beat := _map.beat()
		if not _map.between(BeatMap.Drum.KICK, _time - delta, _time).is_empty():
			_kick()
		var ahead := _time + beat
		for at in _map.between(BeatMap.Drum.SNARE, _snares_to, ahead):
			_fire(at - _time)
		_snares_to = maxf(_snares_to, ahead)
		for at in _map.between(BeatMap.Drum.HAT, _hats_to, ahead):
			_orb(at - _time)
		_hats_to = maxf(_hats_to, ahead)
		# Near its end: crossfading round to the start.
		var length := _player.stream.get_length() if _player.stream else 0.0
		if _player.playing and length > LOOP_FADE * 2.0 and _player.get_playback_position() >= length - LOOP_FADE:
			_loop()
		elif not _player.playing:
			_start() # (stopped some other way: round again)
		return
	# No map: test_bpm, kick and snare taking turns.
	var beat := 60.0 / maxf(test_bpm, 1.0)
	if _time >= _next_beat:
		_next_beat += beat
		if _next_beam % 2 == 0:
			_kick()
			_fire(beat) # (the snare's volley: glowing now, blasting on the next beat)
		_next_beam += 1


## A kick: it beats, and (the host's call) the cathedral quakes.
func _kick() -> void:
	_beat_age = 0.0
	if Network.is_online() and not multiplayer.is_server():
		return
	var inside: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		if _room_world().has_point((node as Node3D).global_position + Vector3.UP):
			inside.append(node as Node3D)
	Network.send_heart_kick(HeartQuake.pick_chunks(_room_world(), inside, global_position))
	_kicks += 1
	if _kicks % SHIFT_EVERY == 0 and not _pieces.is_empty():
		Network.send_heart_shift(_pick_shift())


## New spots for its structures: each within SHIFT_RANGE of where it was
## built (level: heights stay), in the room, out of the open middle.
func _pick_shift() -> PackedVector3Array:
	var room := _room_world()
	var heart := AABB(global_position - _radii * (1.0 + THUMP), _radii * 2.0 * (1.0 + THUMP)).grow(HEART_CLEARANCE)
	var spots := PackedVector3Array()
	for i in _pieces.size():
		var home := _piece_home[i]
		var now := _pieces[i].global_position if is_instance_valid(_pieces[i]) else home
		var chosen := now # (none clear: it stays)
		for attempt in 12:
			var flat := Vector2.from_angle(randf() * TAU) * SHIFT_RANGE * sqrt(randf_range(SHIFT_LEAST * SHIFT_LEAST, 1.0))
			var to := home + Vector3(flat.x, 0.0, flat.y)
			to.x = clampf(to.x, room.position.x + 8.0, room.end.x - 8.0)
			to.z = clampf(to.z, room.position.z + 8.0, room.end.z - 8.0)
			var from_middle := Vector2(to.x - global_position.x, to.z - global_position.z)
			var home_middle := Vector2(home.x - global_position.x, home.z - global_position.z)
			# (Not into the arena -- unless it was built nearer than that.)
			var least := minf(ARENA, home_middle.length())
			if from_middle.length() < least:
				from_middle = from_middle.normalized() * least if from_middle.length_squared() > 0.01 else home_middle
				to = Vector3(global_position.x + from_middle.x, to.y, global_position.z + from_middle.y)
			if _clear_of(heart, i, now, to):
				chosen = to
				break
		spots.append(chosen)
	return spots


## Whether piece i, sliding from `from` to `to`, stays out of `heart` the
## whole way (checked every couple of metres along it).
func _clear_of(heart: AABB, i: int, from: Vector3, to: Vector3) -> bool:
	var extent := _piece_extent[i]
	var steps := maxi(1, ceili(from.distance_to(to) / 2.0))
	for k in steps + 1:
		var at := from.lerp(to, float(k) / steps)
		if AABB(at + extent.position, extent.size).intersects(heart):
			return false
	return true


## Whether `point` is in its cathedral (the Stalker keeps out of it).
func room_contains(point: Vector3) -> bool:
	return _room_world().grow(5.0).has_point(point)


## Network.send_heart_shift, on every game: where they head now.
func shift(spots: PackedVector3Array) -> void:
	for i in mini(spots.size(), _piece_to.size()):
		_piece_from[i] = _pieces[i].global_position if is_instance_valid(_pieces[i]) else _piece_to[i]
		_piece_to[i] = spots[i]
	_lurches_done = 0 # (lurching from the next kick)


## Each lurch: a snap a fifth of the way on, fast then settling.
func _physics_process(delta: float) -> void:
	if _pieces.is_empty() or _lurch_age > LURCH_TIME:
		return
	_lurch_age += delta
	var t := clampf(_lurch_age / LURCH_TIME, 0.0, 1.0)
	var snap := 1.0 - pow(1.0 - t, 3.0)
	var share := float(_lurches_done) / LURCHES
	for i in _pieces.size():
		if is_instance_valid(_pieces[i]):
			var goal := _piece_from[i].lerp(_piece_to[i], share)
			_pieces[i].global_position = _lurch_start[i].lerp(goal, snap)


## Network.send_heart_kick, on every game.
func quake(spots: PackedVector3Array, decides: bool) -> void:
	_quake_age = 0.0
	_shaking = true
	# A shift under way: this kick's lurch.
	if _lurches_done < LURCHES and not _pieces.is_empty():
		_lurches_done += 1
		_lurch_age = 0.0
		for i in _pieces.size():
			if is_instance_valid(_pieces[i]):
				_lurch_start[i] = _pieces[i].global_position
	HeartQuake.hit(self, _room_world(), spots, decides)


## The cathedral's own meshes (to judder) and its lamps (to flicker).
func _find_room() -> void:
	var stack := get_parent()
	if stack == null:
		return
	for name: String in ROOM_MESHES:
		var mesh := stack.find_child(name, true, false) as Node3D
		if mesh:
			_room_meshes.append(mesh)
			_room_rests.append(mesh.position)
	var pieces := stack.find_child("CathedralPieces", true, false)
	if pieces:
		for node in pieces.get_children():
			if node is AnimatableBody3D:
				_pieces.append(node)
				_piece_home.append((node as Node3D).global_position)
				_piece_to.append((node as Node3D).global_position)
				_piece_from.append((node as Node3D).global_position)
				_lurch_start.append((node as Node3D).global_position)
				var extent := AABB()
				var first := true
				for shape_node in node.get_children():
					var shape := shape_node as CollisionShape3D
					if shape and shape.shape is BoxShape3D:
						var size := (shape.shape as BoxShape3D).size
						var part := shape.transform * AABB(-size * 0.5, size)
						extent = part if first else extent.merge(part)
						first = false
				_piece_extent.append(extent)
				# Its look judders with the kick too (its mesh only: the body, and
				# whoever's standing on it, stays steady).
				var mesh := node.get_node_or_null(^"Mesh") as Node3D
				if mesh:
					_room_meshes.append(mesh)
					_room_rests.append(mesh.position)
	var box := _room_world()
	for light in stack.find_children("*", "Light3D", true, false):
		if not is_ancestor_of(light) and box.has_point((light as Node3D).global_position):
			_lamps.append(light as Light3D)
			_lamp_energy.append((light as Light3D).light_energy)


## The kick's judder and flicker, easing off.
func _shake_room(delta: float) -> void:
	if not _shaking:
		return
	_quake_age += delta
	if _quake_age > maxf(JUDDER_TIME, FLICKER_TIME):
		_shaking = false # (this pass puts everything back at rest)
	var left := clampf(1.0 - _quake_age / JUDDER_TIME, 0.0, 1.0)
	for i in _room_meshes.size():
		if not is_instance_valid(_room_meshes[i]):
			continue
		var offset := Vector3.ZERO
		if left > 0.0:
			var t := _quake_age * JUDDER_RATE
			offset = Vector3(sin(t * 1.3 + i), sin(t * 0.9 + 2.0 * i) * 0.5, cos(t * 1.1 + i)) * JUDDER * left * left
		_room_meshes[i].position = _room_rests[i] + offset
	var flicker := _quake_age < FLICKER_TIME
	for i in _lamps.size():
		if is_instance_valid(_lamps[i]):
			_lamps[i].light_energy = _lamp_energy[i] * (randf_range(0.05, 0.5) if flicker else 1.0)


func _song_time() -> float:
	return _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


## A hi-hat's orb, swelling out of a random spot on it for `warn`, then off
## after a player inside (the host's call).
func _orb(warn: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if HeartOrb.alive.size() >= MAX_ORBS:
		return
	var inside: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as PlayerMovement
		if player and not player.is_dead() and _room_world().has_point(player.global_position + Vector3.UP):
			inside.append(player)
	if inside.is_empty():
		return
	var out := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var at := global_position + out * _radii * 0.9
	Network.send_heart_orb(HeartOrb.next_id(), at, out, inside[randi() % inside.size()].get_multiplayer_authority(), maxf(warn, 0.05))


## Its body (what its orbs pass through).
func body_rid() -> RID:
	return _hitbox.get_rid() if _hitbox else RID()


## A hole opening on it, `warn` seconds before it blasts (the host's call).
func _fire(warn: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	var target := Vector3.INF
	if aim_at_players:
		var inside: Array[Node3D] = []
		for node in get_tree().get_nodes_in_group("player"):
			var player := node as PlayerMovement
			if player and not player.is_dead() and _room_world().has_point(player.global_position + Vector3.UP):
				inside.append(player)
		if not inside.is_empty():
			var chosen := inside[randi() % inside.size()] as PlayerMovement
			target = chosen.global_position + Vector3.UP
			# A predicting beam for every player in there (the user's: in
			# co-op, one leading each of you), where they'll be by the blast
			# (the roaches' lead).
			if predicting_beam:
				for node in inside:
					var player := node as PlayerMovement
					var lead := _predict(player, global_position, warn)
					var lead_way := (lead - global_position).normalized()
					var lead_from := global_position + lead_way * _radii * 0.85
					Network.send_blood_beam(lead_from, (lead - lead_from).normalized(), maxf(warn, 0.05))
	var way := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.5), randf_range(-1.0, 1.0)).normalized()
	if target.is_finite():
		way = (target - global_position).normalized().slerp(way, 0.3).normalized()
	var from := global_position + way * _radii * 0.85
	var aim := (target - from).normalized() if target.is_finite() else way
	Network.send_blood_beam(from, aim, maxf(warn, 0.05))
	# The rest: out of random spots on it, straight out from them, any way.
	for i in random_beams:
		var out := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		Network.send_blood_beam(global_position + out * _radii * 0.85, out, maxf(warn, 0.05))


## Where `target` will be in `time` seconds, as the roaches guess it.
func _predict(target: PlayerMovement, from_point: Vector3, time: float) -> Vector3:
	var aim := Factions.aim_point(target)
	var to_target := Vector3(aim.x - from_point.x, 0.0, aim.z - from_point.z)
	var line := to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD
	var ground := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var toward_away := line * ground.dot(line)
	var sideways := ground - toward_away
	var lead := (sideways + toward_away * PREDICTION_TOWARD) * PREDICTION * randf_range(GUESS.x, GUESS.y)
	var sideways_guess := Vector3.ZERO
	if ground.length_squared() > 1.0:
		sideways_guess = ground.normalized().cross(Vector3.UP) * randf_range(-GUESS_SIDEWAYS, GUESS_SIDEWAYS)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * SCATTER
	return aim + line * AIM_PAST + sideways_guess + lead * time + scatter


# ---- Who's here -----------------------------------------------------------------

func _room_world() -> AABB:
	if not _room_known and is_inside_tree():
		var stack := get_parent() as Node3D
		_room_box = stack.global_transform * room if stack else room
		_room_known = true
	return _room_box


func _anyone_inside() -> bool:
	var box := _room_world()
	for node in get_tree().get_nodes_in_group("player"):
		if box.has_point((node as Node3D).global_position + Vector3.UP):
			return true
	return false


func _nearest_distance() -> float:
	var best := INF
	for node in get_tree().get_nodes_in_group("player"):
		best = minf(best, (node as Node3D).global_position.distance_to(global_position))
	var camera := get_viewport().get_camera_3d()
	if camera:
		best = minf(best, camera.global_position.distance_to(global_position))
	return best


# ---- Looks -------------------------------------------------------------------------

var _base_scale := 1.0
var _looks_on := true
var _chain_pulse := 0.0
## Its cathedral in the world (the Stack never moves: worked out once).
var _room_box := AABB()
var _room_known := false
## A kick's judder and flicker running (else _shake_room does nothing).
var _shaking := false


func _set_looks(on: bool) -> void:
	if on == _looks_on:
		return
	_looks_on = on
	_drips.emitting = on
	for chain in _chains:
		(chain.node as Node3D).visible = on


## The model, sized to `size` tall, centred on this node.
func _build_heart() -> void:
	var packed := load(HEART_MODEL) as PackedScene
	var model: Node3D = packed.instantiate() as Node3D if packed else Node3D.new()
	var box := _bounds(model)
	_base_scale = size / maxf(box.size.y, 0.001)
	# The holder it beats round: the model inside it, its middle on the holder's.
	_model = Node3D.new()
	add_child(_model)
	_model.add_child(model)
	model.position -= box.get_center()
	_model.scale = Vector3.ONE * _base_scale
	_radii = box.size * 0.5 * _base_scale
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var to_root := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk is Node3D:
			to_root = (walk as Node3D).transform * to_root
			if walk == root:
				break
			walk = walk.get_parent()
		var part := to_root * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Blood dripping off its underside the whole time.
func _build_drips() -> void:
	_drips = GPUParticles3D.new()
	_drips.amount = 80
	_drips.lifetime = 4.0
	_drips.local_coords = false
	_drips.draw_pass_1 = BloodFX.droplet_mesh()
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.visibility_aabb = AABB(Vector3(-size, -400.0, -size), Vector3(size * 2.0, 400.0 + size, size * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.25
	process.direction = Vector3.DOWN
	process.spread = 10.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, -14.0, 0.0)
	process.scale_min = 2.0
	process.scale_max = 4.0
	process.color = BloodFX.BLOOD_COLOR
	_drips.process_material = process
	add_child(_drips)
	_drips.position = Vector3.DOWN * _radii.y * 0.7
	_drips.emitting = true


## The chains: out from points on the heart to the walls round it and up to
## the ceiling (wherever a ray from it meets them), links laid along each
## with a sag, every other link turned a quarter.
func _build_chains() -> void:
	var packed := load(CHAIN_MODEL) as PackedScene
	if packed == null:
		return
	var source := packed.instantiate() as Node3D
	var mesh_node := source.find_children("*", "MeshInstance3D", true, false)
	if mesh_node.is_empty():
		source.free()
		return
	var mesh := (mesh_node[0] as MeshInstance3D).mesh
	var material := (mesh_node[0] as MeshInstance3D).get_active_material(0)
	source.free()
	var box := mesh.get_aabb()
	# Its long side runs along the chain; scaled so one is link_length long.
	var long_axis := box.get_longest_axis_index()
	var link_scale := link_length / maxf(box.size[long_axis], 0.001)
	var ways: Array[Vector3] = []
	for i in wall_chains:
		var angle := TAU * (i + 0.5) / maxf(wall_chains, 1)
		ways.append(Vector3(cos(angle), randf_range(-0.05, 0.15), sin(angle)).normalized())
	for i in ceiling_chains:
		var angle := TAU * i / maxf(ceiling_chains, 1)
		ways.append(Vector3(cos(angle) * 0.6, 1.0, sin(angle) * 0.6).normalized())
	var space := get_world_3d().direct_space_state
	for way in ways:
		var from := way * _radii * 0.8
		var start := global_position + from
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + way * 600.0, 1))
		if hit.is_empty():
			continue
		var to: Vector3 = hit.position
		var count := int(start.distance_to(to) / (link_length * 0.8))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = count
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		if material:
			node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.top_level = true
		node.global_transform = Transform3D.IDENTITY
		_chains.append({node = node, from = from, to = to, multimesh = multimesh, links = count,
				axis = long_axis, scale = link_scale, jolt = randf_range(0.6, 1.4)})
	_update_chains(0.0)


## Every link along its chain's sag; a beat jolts them (`pulse` 0..1).
## (Cheap, per frame: each link's turn worked out once, at rest -- a jolt
## barely turns them -- only where they sit is redone; and only when the
## pulse has moved: _process skips it while the heart's at rest.)
func _update_chains(pulse: float) -> void:
	var swell := _model.scale.x / _base_scale
	for chain in _chains:
		var start: Vector3 = global_position + (chain.from as Vector3) * swell
		var finish: Vector3 = chain.to
		var links: int = chain.links
		var droop := start.distance_to(finish) * sag * (1.0 - 0.35 * pulse * float(chain.jolt)) * 4.0
		var multimesh: MultiMesh = chain.multimesh
		var bases: Array = chain.get("bases", [])
		var first := bases.is_empty()
		var previous := start
		for i in links:
			var t := (i + 0.5) / links
			var at := start.lerp(finish, t) + Vector3.DOWN * droop * t * (1.0 - t)
			if first:
				var next_t := (i + 1.5) / links
				var ahead := start.lerp(finish, next_t) + Vector3.DOWN * droop * next_t * (1.0 - next_t)
				bases.append(_link_basis((ahead - previous).normalized(), int(chain.axis), i % 2 == 1) * Basis.from_scale(Vector3.ONE * float(chain.scale)))
				previous = at
			multimesh.set_instance_transform(i, Transform3D(bases[i], at))
		if first:
			chain["bases"] = bases


## A link's turn: its long axis (`axis` of the model) along the chain, every
## other one rolled a quarter turn round it.
static func _link_basis(along: Vector3, axis: int, roll: bool) -> Basis:
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := up.cross(along).normalized()
	up = along.cross(side).normalized()
	var basis := Basis(side, up, along)
	match axis:
		0:
			basis = Basis(along, up, along.cross(up))
		1:
			basis = Basis(side, along, side.cross(along))
	if roll:
		basis = Basis(along, PI * 0.5) * basis
	return basis
