class_name MuzzleFlash
extends Node3D

## A first-person muzzle flash: a PS1-era look lit the modern way.
##
## The look (what a PS1 shooter drew): a chunky, low-res star sprite facing
## you (16 x 16, nearest-filtered, additive), plus two flame "petals" along
## the barrel so it still reads from the side, popping in stepped frames --
## a big frame, a smaller dimmer one, gone -- with a random spin and size
## each shot (Doom, Quake, Half-Life 1, Medal of Honor).
## The lighting (how a modern game sells it): two lights with a sharp attack
## and a fast falloff --
##   a KEY light, small and strong, set off to the side of the muzzle
##     (WeaponData.muzzle_light_offset) so the shot rakes across the gun and
##     the arm from one angle, the cinematic side-light of a film muzzle
##     flash (Call of Duty, Battlefield light their flashes this way);
##   a FILL light at the muzzle, wider and softer, that lights the room.
## One of these per hand, made once and reused for every shot (Rule 2).
## Presentation only (Rule 1).

## The flash's frames: how long each lasts and how big/bright it is.
const FRAME_SCALES: Array[float] = [1.0, 0.65]
const FRAME_ALPHAS: Array[float] = [1.0, 0.55]

@export var sprite_size: float = 0.14
@export var petal_length: float = 0.22
@export var petal_width: float = 0.07
@export var color: Color = Color(1.0, 0.82, 0.45)
## Key light (beside the gun) and fill light (at the muzzle).
@export var key_energy: float = 5.0
@export var key_range: float = 1.6
@export var fill_energy: float = 2.5
@export var fill_range: float = 8.0
## Each shot's colour drifts this much toward white or deep orange.
@export var color_jitter: float = 0.12

static var _texture: Texture2D

var _sprite: MeshInstance3D
var _petals: Array[MeshInstance3D] = []
var _key: OmniLight3D
var _fill: OmniLight3D
var _material: StandardMaterial3D
var _time := -1.0
var _duration := 0.05
var _scale := 1.0
## What it follows while it's showing: a gun model and the muzzle on it,
## plus the key light's place beside it (camera space).
var _gun: Node3D
var _muzzle := Vector3.ZERO
var _key_offset := Vector3.ZERO


func _ready() -> void:
	top_level = true
	visible = false
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.albedo_texture = _star_texture()
	_material.albedo_color = color
	_sprite = _quad(Vector2(sprite_size, sprite_size))
	# Petals: two crossed cards along the barrel (-Z), from the muzzle out.
	for turn in [0.0, PI * 0.5]:
		var petal := _quad(Vector2(petal_width, petal_length))
		petal.transform = Transform3D(Basis(Vector3.FORWARD, turn) * Basis(Vector3.RIGHT, -PI * 0.5),
				Vector3(0.0, 0.0, -petal_length * 0.5))
		_petals.append(petal)
	_key = _light(key_range)
	_fill = _light(fill_range)


## Fires it: `gun` is the gun model, `muzzle` the muzzle in its space, and
## `key_offset` where the key light goes, from the muzzle, in camera space.
func flash(gun: Node3D, muzzle: Vector3, key_offset: Vector3, duration: float) -> void:
	_gun = gun
	_muzzle = muzzle
	_key_offset = key_offset
	_duration = maxf(duration, 0.02)
	_time = 0.0
	_scale = randf_range(0.8, 1.2)
	_sprite.rotation.z = randf() * TAU
	var tint := color.lerp(Color.WHITE if randf() < 0.5 else Color(1.0, 0.55, 0.2), randf() * color_jitter * 4.0)
	_material.albedo_color = tint
	_key.light_color = tint
	_fill.light_color = tint
	_sprite.visible = true
	for petal in _petals:
		petal.visible = true
	visible = true
	_follow()
	_show_frame()


## F2 > L: holds just the lights on at full, so moving the key light shows
## its lighting live. stop() ends it.
func preview(gun: Node3D, muzzle: Vector3, key_offset: Vector3) -> void:
	_gun = gun
	_muzzle = muzzle
	_key_offset = key_offset
	_time = -1.0
	visible = true
	_sprite.visible = false
	for petal in _petals:
		petal.visible = false
	_key.light_color = color
	_fill.light_color = color
	_key.light_energy = key_energy
	_fill.light_energy = fill_energy
	_follow()


func stop() -> void:
	_time = -1.0
	visible = false


func _process(delta: float) -> void:
	if _time < 0.0:
		return
	_time += delta
	if _time >= _duration or not is_instance_valid(_gun):
		_time = -1.0
		visible = false
		return
	_follow()
	_show_frame()


## Stays on the muzzle as the gun kicks and sways, facing the camera.
func _follow() -> void:
	if not is_instance_valid(_gun):
		return
	var camera := get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera else _gun.global_basis.orthonormalized()
	global_transform = Transform3D(facing, _gun.global_transform * _muzzle)
	_key.position = _key_offset


## The stepped frames: each holds still for its share of the time (no smooth
## fade -- that's the PS1 pop), and the lights fall off fast after the peak.
func _show_frame() -> void:
	var t := _time / _duration
	var frame := mini(int(t * FRAME_SCALES.size()), FRAME_SCALES.size() - 1)
	var size := FRAME_SCALES[frame] * _scale
	_sprite.scale = Vector3.ONE * size
	for petal in _petals:
		petal.scale = Vector3(1.0, size, 1.0) # longer/shorter along the barrel
	_material.albedo_color.a = FRAME_ALPHAS[frame]
	var falloff := pow(1.0 - t, 2.0)
	_key.light_energy = key_energy * falloff
	_fill.light_energy = fill_energy * falloff


func _quad(size: Vector2) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh


func _light(light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.omni_range = light_range
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.light_energy = 0.0
	add_child(light)
	return light


## A 16 x 16 star burst, drawn once: a hot middle and four to eight ragged
## spikes, like a hand-pixelled PS1 flash.
static func _star_texture() -> Texture2D:
	if _texture:
		return _texture
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var middle := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y) - middle
			var angle := d.angle()
			var spikes := pow(absf(cos(angle * 3.0)), 6.0) * 0.6 + pow(absf(cos(angle * 2.0 + 0.4)), 10.0) * 0.4
			var reach := 2.5 + spikes * 5.5
			var value := clampf(1.0 - d.length() / reach, 0.0, 1.0)
			value = snappedf(value, 0.25) # a few hard steps, no smooth gradient
			image.set_pixel(x, y, Color(1.0, 0.9 + 0.1 * value, 0.6 + 0.4 * value, value))
	_texture = ImageTexture.create_from_image(image)
	return _texture
