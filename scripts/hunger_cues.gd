class_name HungerCues
extends CanvasLayer

## Starving's body cues (the user's, 2026-10-15: strong, under BELOW of the
## hunger meter -- Virus.hunger): your stomach growls about every
## GROWL_EVERY, your hands shake (the Viewmodel's tremble), the screen's
## edges dim up to DIM, and you breathe weakly. The growl and breathing are
## the user's to add (growl_sound, breath_sound); silent till then.
## Your own screen only (Rule 1: presentation); checked CHECK_EVERY, not
## every frame; the dimming's one shared shader on one rect.

const BELOW := 0.15
const GROWL_EVERY := 10.0
const DIM := 0.6
const CHECK_EVERY := 0.25

@export var growl_sound: AudioStream
@export var breath_sound: AudioStream

const VIGNETTE := "
shader_type canvas_item;
uniform float dim = 0.0;
void fragment() {
	float edge = smoothstep(0.35, 0.95, distance(UV, vec2(0.5)) * 1.4);
	COLOR = vec4(0.0, 0.0, 0.0, edge * dim);
}
"

var _player: PlayerMovement
var _viewmodel: Node
var _vignette: ColorRect
var _growl: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _check_left := 0.0
var _growl_left := 0.0
var _on := false


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	if _player == null or not _player.is_multiplayer_authority():
		queue_free()
		return
	layer = 5
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE
	var material := ShaderMaterial.new()
	material.shader = shader
	_vignette.material = material
	_vignette.visible = false
	add_child(_vignette)
	_growl = AudioStreamPlayer.new()
	_breath = AudioStreamPlayer.new()
	for player in [_growl, _breath]:
		player.bus = &"Player" if AudioServer.get_bus_index(&"Player") != -1 else &"Master"
		add_child(player)
	_viewmodel = _player.camera.get_node_or_null(^"Viewmodel")


func _process(delta: float) -> void:
	_check_left -= delta
	if _on:
		_growl_left -= delta
		if _growl_left <= 0.0:
			_growl_left = GROWL_EVERY * randf_range(0.8, 1.2)
			if growl_sound:
				_growl.stream = growl_sound
				_growl.play()
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	var starving := _player.virus != null and _player.virus.hunger < BELOW and not _player.is_dead()
	if starving == _on:
		return
	_on = starving
	_vignette.visible = _on
	(_vignette.material as ShaderMaterial).set_shader_parameter(&"dim", DIM if _on else 0.0)
	if _viewmodel:
		_viewmodel.set(&"tremble", 1.0 if _on else 0.0)
	_growl_left = 0.0 if _on else GROWL_EVERY
	if _on and breath_sound:
		_breath.stream = breath_sound
		_breath.play()
	elif not _on:
		_breath.stop()
