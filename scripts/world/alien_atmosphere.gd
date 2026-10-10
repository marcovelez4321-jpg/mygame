class_name AlienAtmosphere
extends Resource

## The alien land's air (docs/WORLD.md): purple fog, the PS1 way and the
## modern way at once.
##   Distance fog: a plain fade from fog_start to fog_end (Silent Hill's
##   trick) -- the land dissolves into purple well before the edge of
##   what's loaded, so streaming never shows.
##   Height fog: a low haze pooling in the valleys and thinning up the hills.
##   Until the skyboxes are in, the background is the fog colour, so the
##   horizon melts away; ambient light is purple, so the shaded sides of
##   hills read purple, not black.
## make_environment() builds the Environment; the world bake tool saves it
## as a file next to the world, so it's tuned in the inspector from then on.

@export_group("Distance Fog")
@export var fog_color: Color = Color(0.40, 0.31, 0.56)
## Where the fog starts and where it's fully solid (metres).
@export var fog_start: float = 33.0
@export var fog_end: float = 242.0
## Fade shape (1 = linear, more = stays clear longer then closes fast).
@export var fog_curve: float = 1.2
## How much the fog also covers the sky (lower it once a skybox is in).
@export_range(0.0, 1.0, 0.05) var fog_sky_affect: float = 1.0

@export_group("Valley Haze")
## Height fog: everything below haze_height (metres) gets extra fog, thicker
## the deeper (haze_density).
@export var haze_height: float = 18.0
@export var haze_density: float = 0.054

@export_group("Light")
## Fill light from everywhere, tinted, and how strong.
@export var ambient_color: Color = Color(0.36, 0.30, 0.55)
@export var ambient_energy: float = 0.7


func make_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = fog_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = fog_color
	environment.fog_depth_begin = fog_start
	environment.fog_depth_end = fog_end
	environment.fog_depth_curve = fog_curve
	environment.fog_sky_affect = fog_sky_affect
	environment.fog_height = haze_height
	environment.fog_height_density = haze_density
	return environment

## The sewer/hive biome's air: murky green-brown, thicker and closer in,
## heavier in the valleys, dim yellowish fill (the levels' sewer fog, out in
## the open).
static func sewer() -> AlienAtmosphere:
	var air := AlienAtmosphere.new()
	air.fog_color = Color(0.27, 0.29, 0.16)
	air.fog_start = 22.0
	air.fog_end = 192.5
	air.fog_curve = 1.2
	air.haze_height = 14.0
	air.haze_density = 0.081
	air.ambient_color = Color(0.32, 0.31, 0.20)
	air.ambient_energy = 0.65
	return air


## The settings an Environment has now (e.g. the world's saved, hand-tuned one).
static func from_environment(environment: Environment) -> AlienAtmosphere:
	var air := AlienAtmosphere.new()
	air.fog_color = environment.fog_light_color
	air.fog_start = environment.fog_depth_begin
	air.fog_end = environment.fog_depth_end
	air.fog_curve = environment.fog_depth_curve
	air.fog_sky_affect = environment.fog_sky_affect
	air.haze_height = environment.fog_height
	air.haze_density = environment.fog_height_density
	air.ambient_color = environment.ambient_light_color
	air.ambient_energy = environment.ambient_light_energy
	return air


## Puts the blend of `a` and `b` (t: 0 = a, 1 = b) on an Environment.
static func apply_blend(environment: Environment, a: AlienAtmosphere, b: AlienAtmosphere, t: float) -> void:
	var fog := a.fog_color.lerp(b.fog_color, t)
	environment.fog_light_color = fog
	environment.background_color = fog
	environment.fog_depth_begin = lerpf(a.fog_start, b.fog_start, t)
	environment.fog_depth_end = lerpf(a.fog_end, b.fog_end, t)
	environment.fog_depth_curve = lerpf(a.fog_curve, b.fog_curve, t)
	environment.fog_height = lerpf(a.haze_height, b.haze_height, t)
	environment.fog_height_density = lerpf(a.haze_density, b.haze_density, t)
	environment.ambient_light_color = a.ambient_color.lerp(b.ambient_color, t)
	environment.ambient_light_energy = lerpf(a.ambient_energy, b.ambient_energy, t)
