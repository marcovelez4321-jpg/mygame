class_name BiomeAtmosphere
extends Node

## The open world's air by biome (BiomeMap): the purple reef fog in the reef,
## the murky green-brown sewer fog everywhere else. Walking through a border
## the fog colour and distance, the valley haze, the fill light and the sky
## all crossfade, eased so it never pops. It reads the biome round the
## camera, so in co-op each player sees the air where they are.

@export var biomes: BiomeMap
## The world's WorldEnvironment (empty = the one next to this node).
@export var world_environment: WorldEnvironment
## The world's sun (empty = the one called Sun next to this node): tinted by
## biome too.
@export var sun: DirectionalLight3D
@export_group("Fog")
## ALL THE FOG, in one place. fog_distance pushes every biome's fog nearer
## (below 1) or further off (above 1) at once; reef_air and sewer_air are
## each biome's full set (fog colour, start, end, curve, valley haze,
## ambient light, sun) -- open them to tune any value. Changes show live.
@export_range(0.25, 3.0, 0.05) var fog_distance: float = 1.0:
	set(value):
		fog_distance = value
		_mix = -1.0 # re-apply
## The reef's air (empty = the environment as saved) and the sewer's
## (empty = AlienAtmosphere.sewer()).
@export var reef_air: AlienAtmosphere:
	set(value):
		reef_air = value
		_mix = -1.0
@export var sewer_air: AlienAtmosphere:
	set(value):
		sewer_air = value
		_mix = -1.0
## Below this height (world y) you're underground (the Stack's depths, its
## sewer tunnels): the valley haze -- which thickens the lower you go, made
## for the land's low ground -- is off there, or it'd be a solid wall that
## deep down. The rest of the fog stays.
@export var underground_y: float = -15.0
## Seconds the air takes to catch up with where you are.
@export var blend_time: float = 1.5
## How far round the camera the biome is averaged (metres): a wider look
## so the air doesn't flicker along a ragged border.
@export var sample_reach: float = 30.0

var _environment: Environment
var _refresh_left := 0.0
var _underground := false
## 0 = sewer air, 1 = reef air; -1 = not set yet.
var _mix := -1.0


func _ready() -> void:
	if world_environment == null:
		world_environment = get_parent().get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if sun == null:
		sun = get_parent().get_node_or_null(^"Sun") as DirectionalLight3D
	if world_environment == null or world_environment.environment == null or biomes == null:
		push_warning("BiomeAtmosphere: needs a BiomeMap and a WorldEnvironment next to it")
		set_process(false)
		return
	# Our own copy to change, never the saved file.
	_environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = _environment
	if reef_air == null:
		reef_air = AlienAtmosphere.from_environment(_environment)
	if sewer_air == null:
		sewer_air = AlienAtmosphere.sewer()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	var reach := sample_reach
	var target := (biomes.reef(at.x, at.z) * 2.0
			+ biomes.reef(at.x + reach, at.z) + biomes.reef(at.x - reach, at.z)
			+ biomes.reef(at.x, at.z + reach) + biomes.reef(at.x, at.z - reach)) / 6.0
	var mix := target if _mix < 0.0 else lerpf(_mix, target, 1.0 - exp(-delta / maxf(blend_time, 0.01)))
	# Re-applied as you move between biomes, and every so often anyway (so
	# tuning the airs in the inspector shows straight away).
	_refresh_left -= delta
	var underground := camera.global_position.y < underground_y
	if absf(mix - _mix) < 0.0005 and _refresh_left > 0.0 and underground == _underground:
		return
	_refresh_left = 0.5
	_mix = mix
	_underground = underground
	AlienAtmosphere.apply_blend(_environment, sewer_air, reef_air, _mix, sun, fog_distance)
	if underground:
		_environment.fog_height_density = 0.0
